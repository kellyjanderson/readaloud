import 'dart:async';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/pronunciation_artifact.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/tts_artifact.dart';
import 'package:read_aloud/src/services/english_speech_preprocessor.dart';
import 'package:read_aloud/src/services/kokoro_ipa_adapter.dart';
import 'package:read_aloud/src/services/kokoro_tokenization_worker.dart';

void fakeWorker(KokoroTokenizationWorkerInput input) async {
  final commands = ReceivePort();
  input.reply.send(commands.sendPort);
  await for (final raw in commands) {
    final request = Map<String, Object?>.from(raw as Map);
    if (request['text'] == 'held') {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    input.reply.send({
      ...request,
      if (request['text'] == 'stale') 'bindingRevision': -1,
      'result': KokoroTokenizationResult(
        requestId: request['requestId']! as String,
        documentRevision: request['documentRevision']! as int,
        bindingRevision: request['bindingRevision']! as int,
        workerName: Isolate.current.debugName!,
        tokens: [1],
        finalPhonemeString: request['text']! as String,
        phonemeTraceLines: const [],
      ),
    });
  }
}

void crashWorker(KokoroTokenizationWorkerInput input) => Isolate.exit();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KokoroTokenizerAssets assets;
  setUpAll(() async {
    assets = KokoroTokenizerAssets(
      vocabularyJson: await rootBundle.loadString(
        'assets/tokenizer_vocab.json',
      ),
      lexiconJson: await rootBundle.loadString('assets/lexicon.json'),
      goldJson: await rootBundle.loadString('assets/us_gold.json'),
      silverJson: await rootBundle.loadString('assets/us_silver.json'),
    );
  });

  Future<Tokenizer> baseline() async {
    final tokenizer = Tokenizer(
      config: const TokenizerConfig(lexiconPath: 'assets/lexicon.json'),
    );
    await tokenizer.ensureInitialized();
    await tokenizer.phonemizeWithTokens('warmup', 'en-us');
    return tokenizer;
  }

  for (final text in [
    'Quizzaciously wuglike xyzzy.',
    'Are you okay? The morning is quiet.',
    'John said, "Wait!"\n  café—tea\t123',
    '[John](/dʒɑn/) and (Mary): don\'t rush.',
  ]) {
    test('cold worker-first fallback preserves pinned output: $text', () async {
      final worker = KokoroTokenizationWorker(assets: assets);
      addTearDown(worker.shutdown);
      // This must be the first phonemization on this fresh tokenizer. Computing
      // a caller expectation first masked lazy rootBundle access in the old test.
      final actual = await worker.tokenizeText(text, 'en-us');
      final caller = await baseline();
      final expected = await caller.phonemize(
        prepareEnglishSpeechTextForPhonemizer(text),
        lang: 'en-us',
      );
      expect(actual.finalPhonemeString, expected);
      expect(actual.tokens, caller.tokenize(expected));
      expect(actual.workerName, isNot(Isolate.current.debugName));
    });
  }

  test(
    'raw CMU dictionary is parsed by worker and preserves translated said',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: assets,
        rawDictionary: ';;; fixture\nSAID S EH1 D\nSAID(2) S EH0 D\n',
      );
      addTearDown(worker.shutdown);
      final actual = await worker.prepare(_spec(), 'en-us');
      expect(actual.translatedChunk!.payloadUnits.map((unit) => unit.value), [
        'dʒˈɑn',
        ' ',
        'sˈɛd',
        ',',
      ]);
    },
  );

  test('startup and request failures preserve remote worker stack', () async {
    final invalid = KokoroTokenizationWorker(
      assets: KokoroTokenizerAssets(
        vocabularyJson: 'malformed json',
        lexiconJson: assets.lexiconJson,
        goldJson: assets.goldJson,
        silverJson: assets.silverJson,
      ),
    );
    try {
      await invalid.tokenizeText('first', 'en-us');
      fail('Malformed vocabulary should fail before readiness.');
    } catch (error, stack) {
      expect(error, isStateError);
      expect('$stack', contains('KokoroAssetTokenizer.ensureInitialized'));
    } finally {
      await invalid.shutdown();
    }
    final worker = KokoroTokenizationWorker(assets: assets);
    addTearDown(worker.shutdown);
    try {
      await worker.tokenizeText('', 'en-us');
      fail('Empty speech should fail.');
    } catch (error, stack) {
      expect(error, isStateError);
      expect('$stack', contains('_tokenizeText'));
    }
    expect(
      (await worker.tokenizeText('recovered', 'en-us')).tokens,
      isNotEmpty,
    );
  });

  test(
    'optional malformed custom lexicon keeps warmed fallback behavior',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: KokoroTokenizerAssets(
          vocabularyJson: assets.vocabularyJson,
          lexiconJson: 'invalid custom lexicon',
          goldJson: assets.goldJson,
          silverJson: assets.silverJson,
        ),
      );
      addTearDown(worker.shutdown);
      final actual = await worker.tokenizeText(
        'Quizzaciously wuglike.',
        'en-us',
      );
      final caller = Tokenizer(
        config: const TokenizerConfig(
          lexiconPath: 'missing-optional-lexicon.json',
        ),
      );
      await caller.ensureInitialized();
      await caller.phonemizeWithTokens('warmup', 'en-us');
      final expected = await caller.phonemize(
        'Quizzaciously wuglike.',
        lang: 'en-us',
      );
      expect(actual.finalPhonemeString, expected);
      expect(actual.tokens, caller.tokenize(expected));
    },
  );

  test(
    'direct vocabulary token limit and unknown-character filtering are unchanged',
    () async {
      final worker = KokoroTokenizationWorker(assets: assets);
      addTearDown(worker.shutdown);
      await expectLater(
        worker.tokenizeText('wuglike ' * 100, 'en-us'),
        throwsStateError,
      );
      final actual = await worker.tokenizeText('hello ☃', 'en-us');
      final caller = await baseline();
      final expected = await caller.phonemize('hello ☃', lang: 'en-us');
      expect(actual.finalPhonemeString, expected);
      expect(actual.tokens, caller.tokenize(expected));
    },
  );

  for (final explicitSuffix in [false, true]) {
    test(
      'preserves ${explicitSuffix ? 'explicit suffix' : 's-class allomorph'} phoneme and token sequence',
      () async {
        final worker = KokoroTokenizationWorker(
          assets: assets,
          dictionaryEntries: const {},
        );
        addTearDown(worker.shutdown);
        final result = await worker.prepare(
          _spec(
            text: "John's",
            representation: explicitSuffix
                ? 'explicit_suffix_phoneme'
                : 'normalized_spoken_text',
            value: explicitSuffix ? 'z' : 'Johnz',
            diagnostics: const ['pronunciation.resolved.possessive_allomorph'],
          ),
          'en-us',
        );
        final tokenizer = await baseline();
        final base = await tokenizer.phonemize(
          prepareEnglishSpeechTextForPhonemizer('John'),
          lang: 'en-us',
        );
        expect(result.finalPhonemeString, '${base}z');
        expect(result.tokens, tokenizer.tokenize('${base}z'));
        expect(
          result.phonemeTraceLines.single,
          startsWith(explicitSuffix ? 'explicitSuffix' : 'englishSClass'),
        );
        expect(
          () => result.translatedChunk!.payloadUnits.clear(),
          throwsUnsupportedError,
        );
      },
    );
  }

  test(
    'shutdown settles active and pending owners and rejects new requests',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {},
        workerEntryPoint: fakeWorker,
      );
      final active = worker.tokenizeText('held', 'en-us');
      final pending = worker.tokenizeText('pending', 'en-us');
      final activeTerminal = expectLater(
        active,
        throwsA(isA<KokoroTokenizationCancelled>()),
      );
      final pendingTerminal = expectLater(
        pending,
        throwsA(isA<KokoroTokenizationCancelled>()),
      );
      await Future.wait([
        worker.shutdown(),
        worker.shutdown(),
        activeTerminal,
        pendingTerminal,
      ]);
      expect(worker.activeCount, 0);
      expect(worker.pendingCount, 0);
      await expectLater(
        worker.tokenizeText('closed', 'en-us'),
        throwsStateError,
      );
    },
  );

  test(
    'real initialized tokenizer snapshot runs off caller isolate with exact plain tokens',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {},
      );
      addTearDown(worker.shutdown);
      const text = 'Are you okay? The morning is quiet.';
      // Execute the worker before constructing/priming any caller baseline.
      final result = await worker.tokenizeText(
        text,
        'en-us',
        requestId: 'owner:r7',
        documentRevision: 7,
        bindingRevision: 3,
      );
      final tokenizer = await baseline();
      final expected = await tokenizer.phonemize(
        prepareEnglishSpeechTextForPhonemizer(text),
        lang: 'en-us',
      );
      expect(result.tokens, tokenizer.tokenize(expected));
      expect(result.finalPhonemeString, expected);
      expect(result.workerName, isNot(Isolate.current.debugName));
      expect(result.requestId, 'owner:r7');
      expect(result.documentRevision, 7);
      expect(result.bindingRevision, 3);
      expect(() => result.tokens.add(42), throwsUnsupportedError);
      await worker.shutdown();
      await worker.shutdown();
    },
  );

  test(
    'dictionary snapshot preserves explicit-word indexing and trace without duplicated said',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {'said': 'sˈɛd'},
      );
      addTearDown(worker.shutdown);
      final result = await worker.prepare(_spec(), 'en-us');
      expect(result.translatedChunk!.payloadUnits.map((unit) => unit.value), [
        'dʒˈɑn',
        ' ',
        'sˈɛd',
        ',',
      ]);
      expect(result.translatedChunk!.missingFallbackWordCount, 0);
      final tokenizer = await baseline();
      final punctuation = await tokenizer.phonemize(',', lang: 'en-us');
      final john = adaptStandardIpaToKokoroPhonemes('dʒˈɑn');
      final said = adaptStandardIpaToKokoroPhonemes('sˈɛd');
      expect(result.tokens, [
        ...tokenizer.tokenize(john),
        ...tokenizer.tokenize(said),
        ...tokenizer.tokenize(punctuation),
      ]);
      expect(result.finalPhonemeString, '$john $said $punctuation');
      expect(
        result.phonemeTraceLines.where((line) => line.contains('sˈɛd')).length,
        1,
      );
      expect(
        result.translatedChunk!.pronunciationArtifacts.map((a) => a.artifactId),
        contains('john'),
      );
    },
  );

  test(
    'one active and only latest pending settle coalesced request explicitly',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {},
        workerEntryPoint: fakeWorker,
      );
      addTearDown(worker.shutdown);
      final first = worker.tokenizeText('held', 'en-us');
      final oldPending = worker.tokenizeText('old', 'en-us');
      final cancelled = expectLater(
        oldPending,
        throwsA(isA<KokoroTokenizationCancelled>()),
      );
      final latest = worker.tokenizeText('latest', 'en-us');
      expect(worker.activeCount, 1);
      expect(worker.pendingCount, 1);
      await cancelled;
      expect((await first).finalPhonemeString, 'held');
      expect((await latest).finalPhonemeString, 'latest');
    },
  );

  test(
    'cancel kills pure active owner, suppresses late result, and permits fresh work',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {},
        workerEntryPoint: fakeWorker,
      );
      addTearDown(worker.shutdown);
      final active = worker.tokenizeText('held', 'en-us');
      final cancelled = expectLater(
        active,
        throwsA(isA<KokoroTokenizationCancelled>()),
      );
      worker.cancel();
      final replacement = worker.tokenizeText('new', 'en-us');
      await cancelled;
      expect((await replacement).finalPhonemeString, 'new');
      await worker.shutdown();
      expect(worker.activeCount, 0);
      expect(worker.pendingCount, 0);
      await expectLater(
        worker.tokenizeText('closed', 'en-us'),
        throwsStateError,
      );
    },
  );

  test(
    'mismatched terminal identity fails only its owner and allows recovery',
    () async {
      final worker = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {},
        workerEntryPoint: fakeWorker,
      );
      addTearDown(worker.shutdown);
      await expectLater(
        worker.tokenizeText('stale', 'en-us', bindingRevision: 9),
        throwsStateError,
      );
      expect(
        (await worker.tokenizeText(
          'fresh',
          'en-us',
          bindingRevision: 10,
        )).bindingRevision,
        10,
      );
    },
  );

  test('timeout drains worker exit before replacement and shutdown', () async {
    final worker = KokoroTokenizationWorker(
      assets: assets,
      dictionaryEntries: const {},
      workerEntryPoint: fakeWorker,
      timeout: const Duration(milliseconds: 150),
    );
    addTearDown(worker.shutdown);
    await expectLater(
      worker.tokenizeText('held', 'en-us'),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      (await worker.tokenizeText('recovered', 'en-us')).finalPhonemeString,
      'recovered',
    );
    await worker.shutdown();
  });

  test(
    'worker crash and empty token failure settle without blocking shutdown',
    () async {
      final broken = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {},
        workerEntryPoint: crashWorker,
      );
      await expectLater(
        broken.tokenizeText('hello', 'en-us'),
        throwsStateError,
      );
      await broken.shutdown();
      final worker = KokoroTokenizationWorker(
        assets: assets,
        dictionaryEntries: const {},
      );
      await expectLater(worker.tokenizeText('', 'en-us'), throwsStateError);
      expect((await worker.tokenizeText('hello', 'en-us')).tokens, isNotEmpty);
      await worker.shutdown();
    },
  );
}

ChunkSpec _spec({
  String text = 'John said,',
  String representation = 'phoneme_string',
  String value = 'dʒˈɑn',
  List<String> diagnostics = const [],
}) => ChunkSpec(
  chunkId: 'c',
  segmentIds: ['s'],
  speakText: text,
  voiceId: 'af_bella',
  boundaryClass: BreakClass.sentence,
  startSegmentIndex: 0,
  endSegmentIndex: 0,
  estimatedWordCount: 2,
  cacheKey: 'c',
  startWordIndex: 0,
  endWordIndex: 2,
  ttsSegments: [
    TtsArtifactSegment(
      segmentId: 's',
      speakText: text,
      pronunciationArtifacts: [
        RealizedPronunciationArtifact(
          artifactId: 'john',
          segmentId: 's',
          startWord: 0,
          endWord: 1,
          resolutionClass: 'explicit',
          translationIntent: representation,
          diagnosticCodes: diagnostics,
          selectedRepresentation: PronunciationRepresentation(
            representationId: 'john-ipa',
            representationType: representation,
            representationValue: value,
            priority: 1,
          ),
        ),
      ],
    ),
  ],
);
