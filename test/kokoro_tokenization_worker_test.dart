import 'dart:async';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
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
  late Tokenizer tokenizer;
  setUpAll(() async {
    tokenizer = Tokenizer(
      config: const TokenizerConfig(lexiconPath: 'assets/lexicon.json'),
    );
    await tokenizer.ensureInitialized();
  });

  for (final explicitSuffix in [false, true]) {
    test(
      'preserves ${explicitSuffix ? 'explicit suffix' : 's-class allomorph'} phoneme and token sequence',
      () async {
        final worker = KokoroTokenizationWorker(
          tokenizer: tokenizer,
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
        tokenizer: tokenizer,
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
        tokenizer: tokenizer,
        dictionaryEntries: const {},
      );
      addTearDown(worker.shutdown);
      const text = 'Are you okay? The morning is quiet.';
      final expected = await tokenizer.phonemize(
        prepareEnglishSpeechTextForPhonemizer(text),
        lang: 'en-us',
      );
      final result = await worker.tokenizeText(
        text,
        'en-us',
        requestId: 'owner:r7',
        documentRevision: 7,
        bindingRevision: 3,
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
        tokenizer: tokenizer,
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
        tokenizer: tokenizer,
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
        tokenizer: tokenizer,
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
        tokenizer: tokenizer,
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
      tokenizer: tokenizer,
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
        tokenizer: tokenizer,
        dictionaryEntries: const {},
        workerEntryPoint: crashWorker,
      );
      await expectLater(
        broken.tokenizeText('hello', 'en-us'),
        throwsStateError,
      );
      await broken.shutdown();
      final worker = KokoroTokenizationWorker(
        tokenizer: tokenizer,
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
