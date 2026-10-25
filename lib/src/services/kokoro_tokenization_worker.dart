import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'kokoro_asset_tokenizer.dart';
export 'kokoro_asset_tokenizer.dart' show KokoroTokenizerAssets;
import '../models/chunk_plan.dart';
import '../models/engine_capability.dart';
import '../models/tts_artifact.dart';
import 'english_pronunciation_dictionary_service.dart';
import 'english_speech_preprocessor.dart';
import 'english_suffix_allomorph_module.dart';
import 'kokoro_ipa_adapter.dart';
import 'kokoro_pronunciation_translation_service.dart';

class KokoroTokenizationCancelled implements Exception {
  const KokoroTokenizationCancelled(this.requestId);
  final String requestId;
  @override
  String toString() => 'Tokenization cancelled: $requestId';
}

class KokoroTokenizationResult {
  KokoroTokenizationResult({
    required this.requestId,
    required this.documentRevision,
    required this.bindingRevision,
    required this.workerName,
    required List<int> tokens,
    required List<String> phonemeTraceLines,
    required this.finalPhonemeString,
    this.translatedChunk,
  }) : tokens = List.unmodifiable(tokens),
       phonemeTraceLines = List.unmodifiable(phonemeTraceLines);
  final String requestId;
  final int documentRevision;
  final int bindingRevision;
  final String workerName;
  final KokoroTranslatedChunk? translatedChunk;
  final List<int> tokens;
  final List<String> phonemeTraceLines;
  final String finalPhonemeString;
}

/// Pure Dart resident worker: one active request plus one latest pending request.
/// Raw asset strings cross the bridge once; initialization runs in the worker.
/// Use separate instances for playback and export, which are independent owners.
class KokoroTokenizationWorker {
  KokoroTokenizationWorker({
    required KokoroTokenizerAssets assets,
    Map<String, String> dictionaryEntries = const {},
    String? rawDictionary,
    EngineCapabilityProfile? capabilityProfile,
    this.ownerId = 'kokoro-tokenization',
    this.timeout = const Duration(seconds: 30),
    this.workerEntryPoint = kokoroTokenizationWorkerEntry,
  }) : _assets = assets,
       _rawDictionary = rawDictionary,
       _dictionary = Map.unmodifiable(dictionaryEntries),
       _capabilityProfile =
           capabilityProfile ??
           const EngineCapabilityRegistry().lookup(engineId: 'kokoro') {
    if (rawDictionary != null && dictionaryEntries.isNotEmpty) {
      throw ArgumentError('Provide raw dictionary text or entries, not both.');
    }
  }
  final EngineCapabilityProfile _capabilityProfile;
  final KokoroTokenizerAssets _assets;
  final String? _rawDictionary;
  final Map<String, String> _dictionary;
  final String ownerId;
  final Duration timeout;
  final void Function(KokoroTokenizationWorkerInput) workerEntryPoint;
  _TokenJob? _active;
  _TokenJob? _pending;
  int _sequence = 0;
  bool _closed = false;
  Future<void>? _shutdown;
  Isolate? _isolate;
  ReceivePort? _port;
  StreamSubscription<dynamic>? _subscription;
  Completer<SendPort>? _ready;
  Completer<void>? _exited;
  Future<void>? _starting;
  Future<Isolate>? _spawning;
  Completer<Map<String, Object?>>? _response;
  int get activeCount => _active == null ? 0 : 1;
  int get pendingCount => _pending == null ? 0 : 1;

  Future<KokoroTokenizationResult> prepare(
    ChunkSpec spec,
    String languageTag, {
    String? requestId,
    int documentRevision = 0,
    int bindingRevision = 0,
  }) => _submit(
    {
      'chunkId': spec.chunkId,
      'segments': _freezeSegments(spec.ttsSegments),
      'languageTag': languageTag,
    },
    requestId,
    documentRevision,
    bindingRevision,
  );

  Future<KokoroTokenizationResult> tokenizeText(
    String text,
    String languageTag, {
    String? requestId,
    int documentRevision = 0,
    int bindingRevision = 0,
  }) => _submit(
    {'text': text, 'languageTag': languageTag},
    requestId,
    documentRevision,
    bindingRevision,
  );

  Future<KokoroTokenizationResult> _submit(
    Map<String, Object?> data,
    String? requestId,
    int documentRevision,
    int bindingRevision,
  ) {
    final sequence = ++_sequence;
    final job = _TokenJob({
      ...data,
      'sequence': sequence,
      'requestId': requestId ?? '$ownerId:$sequence',
      'documentRevision': documentRevision,
      'bindingRevision': bindingRevision,
    });
    if (_closed) {
      job.result.completeError(StateError('Tokenization worker is shut down.'));
    } else if (_active == null) {
      _launch(job);
    } else {
      _pending?.cancel();
      _pending = job;
    }
    return job.result.future;
  }

  void cancel() {
    _pending?.cancel();
    _pending = null;
    _active?.cancel();
  }

  Future<void> shutdown() => _shutdown ??= _close();
  Future<void> _close() async {
    _closed = true;
    cancel();
    await _active?.drained.future;
    await _stopWorker();
  }

  void _launch(_TokenJob job) {
    _active = job;
    unawaited(_execute(job));
  }

  Future<void> _execute(_TokenJob job) async {
    var stopWorker = false;
    try {
      final response = await Future.any([
        _run(job),
        job.cancelled.future.then<Map<String, Object?>>(
          (_) => throw KokoroTokenizationCancelled(
            job.data['requestId']! as String,
          ),
        ),
      ]).timeout(timeout);
      if (response['sequence'] != job.data['sequence'] ||
          response['requestId'] != job.data['requestId'] ||
          response['documentRevision'] != job.data['documentRevision'] ||
          response['bindingRevision'] != job.data['bindingRevision']) {
        throw StateError('Tokenization worker returned stale identity.');
      }
      if (response['error'] != null) {
        Error.throwWithStackTrace(
          StateError(response['error']! as String),
          StackTrace.fromString(response['stackTrace'] as String? ?? ''),
        );
      }
      final result = response['result']! as KokoroTokenizationResult;
      if (result.requestId != job.data['requestId'] ||
          result.documentRevision != job.data['documentRevision'] ||
          result.bindingRevision != job.data['bindingRevision']) {
        throw StateError(
          'Tokenization result identity does not match its envelope.',
        );
      }
      if (!job.result.isCompleted) job.result.complete(result);
    } catch (error, stack) {
      stopWorker = true;
      if (!job.result.isCompleted) job.result.completeError(error, stack);
    } finally {
      if (stopWorker || job.cancelled.isCompleted) await _stopWorker();
      _response = null;
      _active = null;
      job.drained.complete();
      final next = _pending;
      _pending = null;
      if (next != null && !_closed) _launch(next);
    }
  }

  Future<Map<String, Object?>> _run(_TokenJob job) async {
    await (_starting ??= _startWorker());
    if (job.cancelled.isCompleted) {
      throw KokoroTokenizationCancelled(job.data['requestId']! as String);
    }
    _response = Completer<Map<String, Object?>>();
    (await _ready!.future).send(job.data);
    return _response!.future;
  }

  Future<void> _startWorker() async {
    _port = ReceivePort();
    _ready = Completer<SendPort>();
    _exited = Completer<void>();
    _subscription = _port!.listen((message) {
      if (message is SendPort) {
        if (!_ready!.isCompleted) _ready!.complete(message);
      } else if (message == null || message is List) {
        final error = StateError('Tokenization worker exited: $message');
        final remoteStack = message is List && message.length > 1
            ? StackTrace.fromString('${message[1]}')
            : StackTrace.current;
        if (!_ready!.isCompleted) _ready!.completeError(error, remoteStack);
        if (_response != null && !_response!.isCompleted) {
          _response!.completeError(error, remoteStack);
        }
        if (message == null && !_exited!.isCompleted) _exited!.complete();
      } else if (_response != null && !_response!.isCompleted) {
        _response!.complete(Map<String, Object?>.from(message as Map));
      }
    });
    _spawning = Isolate.spawn(
      workerEntryPoint,
      KokoroTokenizationWorkerInput(
        _assets,
        _dictionary,
        _port!.sendPort,
        _capabilityProfile,
        _rawDictionary,
      ),
      onExit: _port!.sendPort,
      onError: _port!.sendPort,
      debugName: '$ownerId-worker',
    );
    _isolate = await _spawning;
    await _ready!.future;
  }

  Future<void> _stopWorker() async {
    // A cancellation during spawn still owns the eventual isolate before kill.
    try {
      _isolate ??= await _spawning;
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    if (_isolate != null) await _exited?.future;
    await _subscription?.cancel();
    _port?.close();
    _isolate = null;
    _port = null;
    _subscription = null;
    _starting = null;
    _spawning = null;
    _ready = null;
    _exited = null;
  }
}

class _TokenJob {
  _TokenJob(this.data);
  final Map<String, Object?> data;
  final result = Completer<KokoroTokenizationResult>();
  final cancelled = Completer<void>();
  final drained = Completer<void>();
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    if (!result.isCompleted) {
      result.completeError(
        KokoroTokenizationCancelled(data['requestId']! as String),
      );
    }
  }
}

class KokoroTokenizationWorkerInput {
  const KokoroTokenizationWorkerInput(
    this.assets,
    this.dictionaryEntries,
    this.reply,
    this.capabilityProfile,
    this.rawDictionary,
  );
  final KokoroTokenizerAssets assets;
  final String? rawDictionary;
  final Map<String, String> dictionaryEntries;
  final SendPort reply;
  final EngineCapabilityProfile capabilityProfile;
}

void kokoroTokenizationWorkerEntry(KokoroTokenizationWorkerInput input) async {
  if (input.rawDictionary != null) {
    EnglishPronunciationDictionaryService.instance.restoreRawDictionary(
      input.rawDictionary!,
    );
  } else {
    EnglishPronunciationDictionaryService.instance.restoreSnapshot(
      input.dictionaryEntries,
    );
  }
  final tokenizer = KokoroAssetTokenizer(input.assets);
  await tokenizer.ensureInitialized();
  final commands = ReceivePort();
  input.reply.send(commands.sendPort);
  await for (final raw in commands) {
    final request = Map<String, Object?>.from(raw as Map);
    try {
      final translated = request['segments'] == null
          ? null
          : const KokoroPronunciationTranslationService().translate(
              chunkId: request['chunkId']! as String,
              capabilityProfile: input.capabilityProfile,
              segments: (request['segments']! as List)
                  .cast<TtsArtifactSegment>(),
            );
      final trace = translated == null
          ? await _tokenizeText(
              tokenizer,
              request['text']! as String,
              request['languageTag']! as String,
            )
          : await _tokenizeTranslatedChunk(
              tokenizer,
              translated,
              request['languageTag']! as String,
            );
      final result = KokoroTokenizationResult(
        requestId: request['requestId']! as String,
        documentRevision: request['documentRevision']! as int,
        bindingRevision: request['bindingRevision']! as int,
        workerName: Isolate.current.debugName ?? 'worker',
        translatedChunk: translated == null
            ? null
            : _freezeTranslated(translated),
        tokens: trace.tokens,
        phonemeTraceLines: trace.phonemeTraceLines,
        finalPhonemeString: trace.finalPhonemeString,
      );
      input.reply.send({...request, 'result': result});
    } catch (error, stack) {
      input.reply.send({...request, 'error': '$error', 'stackTrace': '$stack'});
    }
  }
}

KokoroTranslatedChunk _freezeTranslated(KokoroTranslatedChunk chunk) =>
    KokoroTranslatedChunk(
      chunkId: chunk.chunkId,
      capabilityProfileId: chunk.capabilityProfileId,
      speakText: chunk.speakText,
      missingFallbackWordCount: chunk.missingFallbackWordCount,
      payloadUnits: List.unmodifiable([
        for (final unit in chunk.payloadUnits)
          KokoroEnginePayloadUnit(
            kind: unit.kind,
            value: unit.value,
            artifactIds: List.unmodifiable(unit.artifactIds),
          ),
      ]),
      pronunciationArtifacts: List.unmodifiable([
        for (final artifact in chunk.pronunciationArtifacts)
          KokoroTranslatedPronunciationArtifact(
            artifactId: artifact.artifactId,
            segmentId: artifact.segmentId,
            startWord: artifact.startWord,
            endWord: artifact.endWord,
            resolutionClass: artifact.resolutionClass,
            translationIntent: artifact.translationIntent,
            translationOutcome: artifact.translationOutcome,
            representationType: artifact.representationType,
            representationValue: artifact.representationValue,
            diagnosticCodes: List.unmodifiable(artifact.diagnosticCodes),
          ),
      ]),
    );

List<TtsArtifactSegment> _freezeSegments(List<TtsArtifactSegment> segments) =>
    List.unmodifiable([
      for (final segment in segments)
        TtsArtifactSegment(
          segmentId: segment.segmentId,
          speakText: segment.speakText,
          pronunciationArtifacts: List.unmodifiable([
            for (final artifact in segment.pronunciationArtifacts)
              RealizedPronunciationArtifact(
                artifactId: artifact.artifactId,
                segmentId: artifact.segmentId,
                startWord: artifact.startWord,
                endWord: artifact.endWord,
                resolutionClass: artifact.resolutionClass,
                translationIntent: artifact.translationIntent,
                selectedRepresentation: artifact.selectedRepresentation,
                diagnosticCodes: List.unmodifiable(artifact.diagnosticCodes),
              ),
          ]),
        ),
    ]);

Future<_TokenizationTrace> _tokenizeText(
  KokoroAssetTokenizer tokenizer,
  String text,
  String languageTag,
) async {
  final prepared = prepareEnglishSpeechTextForPhonemizer(text);
  final phonemes = await tokenizer.phonemize(prepared, lang: languageTag);
  final tokens = tokenizer.tokenize(phonemes);
  if (tokens.isEmpty) {
    throw StateError('Kokoro could not derive speech tokens for this chunk.');
  }
  return _TokenizationTrace(
    tokens: tokens,
    phonemeTraceLines: const [],
    finalPhonemeString: phonemes,
  );
}

Future<_TokenizationTrace> _tokenizeTranslatedChunk(
  KokoroAssetTokenizer tokenizer,
  KokoroTranslatedChunk translatedChunk,
  String languageTag,
) async {
  final tokens = <int>[];
  final traceLines = <String>[];
  final combinedPhonemes = <String>[];
  final plainTextBuffer = StringBuffer();

  Future<void> flushPlainTextBuffer() async {
    if (plainTextBuffer.isEmpty) {
      return;
    }
    final bufferedText = plainTextBuffer.toString();
    plainTextBuffer.clear();

    if (bufferedText.trim().isEmpty) {
      return;
    }

    final preparedSpeakText = prepareEnglishSpeechTextForPhonemizer(
      bufferedText,
    );
    final phonemes = await tokenizer.phonemize(
      preparedSpeakText,
      lang: languageTag,
    );
    tokens.addAll(tokenizer.tokenize(phonemes));
    combinedPhonemes.add(phonemes);
    traceLines.add(
      'plainText text=${jsonEncode(bufferedText)} prepared=${jsonEncode(preparedSpeakText)} phonemes=${jsonEncode(phonemes)}',
    );
  }

  for (final unit in translatedChunk.payloadUnits) {
    switch (unit.kind) {
      case KokoroEnginePayloadUnitKind.plainText:
        plainTextBuffer.write(unit.value);
      case KokoroEnginePayloadUnitKind.phonemeString:
        await flushPlainTextBuffer();
        if (unit.value.trim().isEmpty) {
          continue;
        }
        final enginePhonemes = adaptStandardIpaToKokoroPhonemes(unit.value);
        tokens.addAll(tokenizer.tokenize(enginePhonemes));
        combinedPhonemes.add(enginePhonemes);
        traceLines.add(
          enginePhonemes == unit.value
              ? 'directPhoneme phonemes=${jsonEncode(unit.value)} artifactIds=${jsonEncode(unit.artifactIds)}'
              : 'directPhoneme internalPhonemes=${jsonEncode(unit.value)} enginePhonemes=${jsonEncode(enginePhonemes)} artifactIds=${jsonEncode(unit.artifactIds)}',
        );
      case KokoroEnginePayloadUnitKind.englishSClassAllomorph:
        await flushPlainTextBuffer();
        final realization = englishSClassRealizationForToken(unit.value);
        if (realization == null) {
          plainTextBuffer.write(unit.value);
          continue;
        }
        final basePhonemes = await tokenizer.phonemize(
          prepareEnglishSpeechTextForPhonemizer(realization.baseSurfaceText),
          lang: languageTag,
        );
        final phonemeString =
            '$basePhonemes${englishSClassSuffixPhoneme(realization.allomorph)}';
        tokens.addAll(tokenizer.tokenize(phonemeString));
        combinedPhonemes.add(phonemeString);
        traceLines.add(
          'englishSClass token=${jsonEncode(unit.value)} base=${jsonEncode(realization.baseSurfaceText)} basePhonemes=${jsonEncode(basePhonemes)} suffix=${jsonEncode(englishSClassSuffixPhoneme(realization.allomorph))} combined=${jsonEncode(phonemeString)}',
        );
      case KokoroEnginePayloadUnitKind.explicitSuffixPhoneme:
        await flushPlainTextBuffer();
        final explicitSuffixPayload = _decodeExplicitSuffixPayload(unit.value);
        if (explicitSuffixPayload == null) {
          plainTextBuffer.write(unit.value);
          continue;
        }
        final basePhonemes = await tokenizer.phonemize(
          prepareEnglishSpeechTextForPhonemizer(
            explicitSuffixPayload.baseSurfaceText,
          ),
          lang: languageTag,
        );
        final phonemeString =
            '$basePhonemes${explicitSuffixPayload.suffixPhoneme}';
        tokens.addAll(tokenizer.tokenize(phonemeString));
        combinedPhonemes.add(phonemeString);
        traceLines.add(
          'explicitSuffix base=${jsonEncode(explicitSuffixPayload.baseSurfaceText)} basePhonemes=${jsonEncode(basePhonemes)} suffix=${jsonEncode(explicitSuffixPayload.suffixPhoneme)} combined=${jsonEncode(phonemeString)}',
        );
    }
  }

  await flushPlainTextBuffer();

  if (tokens.isEmpty) {
    throw StateError('Kokoro could not derive speech tokens for this chunk.');
  }
  return _TokenizationTrace(
    tokens: tokens,
    phonemeTraceLines: traceLines,
    finalPhonemeString: combinedPhonemes.join(' '),
  );
}

class _TokenizationTrace {
  const _TokenizationTrace({
    required this.tokens,
    required this.phonemeTraceLines,
    required this.finalPhonemeString,
  });

  final List<int> tokens;
  final List<String> phonemeTraceLines;
  final String finalPhonemeString;
}

class _ExplicitSuffixPayload {
  const _ExplicitSuffixPayload({
    required this.baseSurfaceText,
    required this.suffixPhoneme,
  });

  final String baseSurfaceText;
  final String suffixPhoneme;
}

_ExplicitSuffixPayload? _decodeExplicitSuffixPayload(String rawValue) {
  try {
    final decoded = jsonDecode(rawValue);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final baseSurfaceText = decoded['baseSurfaceText'] as String?;
    final suffixPhoneme = decoded['suffixPhoneme'] as String?;
    if (baseSurfaceText == null ||
        baseSurfaceText.trim().isEmpty ||
        suffixPhoneme == null ||
        suffixPhoneme.trim().isEmpty) {
      return null;
    }
    return _ExplicitSuffixPayload(
      baseSurfaceText: baseSurfaceText,
      suffixPhoneme: suffixPhoneme,
    );
  } catch (_) {
    return null;
  }
}
