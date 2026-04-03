import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/speech_annotation.dart';
import 'speech_worker_pipeline.dart';
import 'synthesis_boundary_policy.dart';

const String speechRuntimeProtocolVersion = 'speech-runtime-v1';

enum SpeechRuntimeLifecycleState {
  uninitialized,
  initializing,
  idle,
  sessionActive,
  shuttingDown,
  disposed,
  failed,
}

enum SpeechRuntimeCommandType {
  initializeRuntime,
  activateSession,
  preparePriorityChunk,
  prepareChunkPlan,
  cancelSession,
  shutdownRuntime,
}

enum SpeechRuntimeEventType {
  runtimeInitialized,
  sessionActivated,
  chunkQueued,
  chunkCacheHit,
  chunkStageChanged,
  chunkReady,
  chunkFailed,
  sessionCancelled,
  runtimeFailed,
  runtimeShutdown,
}

enum SpeechRuntimeNativeQueuePolicy { serialBackgroundAdapter, unsupported }

class SpeechRuntimeCapabilities {
  const SpeechRuntimeCapabilities({
    required this.engineId,
    required this.supportsLongLivedWorkerExecution,
    required this.supportsBackgroundPluginRequests,
    required this.isEngineSupported,
    required this.nativeQueuePolicy,
  });

  factory SpeechRuntimeCapabilities.detectForCurrentPlatform({
    required String engineId,
  }) {
    final isNativePlatform = !kIsWeb;
    final isKokoroSupported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final isEngineSupported = switch (engineId) {
      'kokoro' => isKokoroSupported,
      _ => false,
    };

    return SpeechRuntimeCapabilities(
      engineId: engineId,
      supportsLongLivedWorkerExecution: isNativePlatform,
      supportsBackgroundPluginRequests: isNativePlatform,
      isEngineSupported: isEngineSupported,
      nativeQueuePolicy: isEngineSupported
          ? SpeechRuntimeNativeQueuePolicy.serialBackgroundAdapter
          : SpeechRuntimeNativeQueuePolicy.unsupported,
    );
  }

  final String engineId;
  final bool supportsLongLivedWorkerExecution;
  final bool supportsBackgroundPluginRequests;
  final bool isEngineSupported;
  final SpeechRuntimeNativeQueuePolicy nativeQueuePolicy;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'engineId': engineId,
      'supportsLongLivedWorkerExecution': supportsLongLivedWorkerExecution,
      'supportsBackgroundPluginRequests': supportsBackgroundPluginRequests,
      'isEngineSupported': isEngineSupported,
      'nativeQueuePolicy': nativeQueuePolicy.name,
    };
  }

  factory SpeechRuntimeCapabilities.fromMap(Map<String, Object?> map) {
    return SpeechRuntimeCapabilities(
      engineId: map['engineId']! as String,
      supportsLongLivedWorkerExecution:
          map['supportsLongLivedWorkerExecution']! as bool,
      supportsBackgroundPluginRequests:
          map['supportsBackgroundPluginRequests']! as bool,
      isEngineSupported: map['isEngineSupported']! as bool,
      nativeQueuePolicy: SpeechRuntimeNativeQueuePolicy.values.byName(
        map['nativeQueuePolicy']! as String,
      ),
    );
  }
}

class SpeechRuntimeSessionDescriptor {
  const SpeechRuntimeSessionDescriptor({
    required this.sessionId,
    required this.documentId,
    required this.engineId,
    required this.voiceId,
    required this.rate,
    required this.startSegmentId,
    required this.normalizationVersion,
    this.isReplay = false,
    this.isResumedPlayback = false,
    this.narrationState = const <String, Object?>{},
  });

  final String sessionId;
  final String documentId;
  final String engineId;
  final String voiceId;
  final double rate;
  final String startSegmentId;
  final String normalizationVersion;
  final bool isReplay;
  final bool isResumedPlayback;
  final Map<String, Object?> narrationState;

  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'sessionId': sessionId,
      'documentId': documentId,
      'engineId': engineId,
      'voiceId': voiceId,
      'rate': rate,
      'startSegmentId': startSegmentId,
      'normalizationVersion': normalizationVersion,
      'isReplay': isReplay,
      'isResumedPlayback': isResumedPlayback,
      'narrationState': narrationState,
    };
  }

  factory SpeechRuntimeSessionDescriptor.fromPayload(Map<String, Object?> map) {
    return SpeechRuntimeSessionDescriptor(
      sessionId: map['sessionId']! as String,
      documentId: map['documentId']! as String,
      engineId: map['engineId']! as String,
      voiceId: map['voiceId']! as String,
      rate: (map['rate']! as num).toDouble(),
      startSegmentId: map['startSegmentId']! as String,
      normalizationVersion: map['normalizationVersion']! as String,
      isReplay: map['isReplay'] as bool? ?? false,
      isResumedPlayback: map['isResumedPlayback'] as bool? ?? false,
      narrationState:
          (map['narrationState'] as Map<Object?, Object?>?)
              ?.map((key, value) => MapEntry(key.toString(), value))
              .cast<String, Object?>() ??
          const <String, Object?>{},
    );
  }
}

class SpeechRuntimeChunkPayload {
  const SpeechRuntimeChunkPayload({
    required this.chunkId,
    required this.segmentIds,
    required this.cacheKey,
    required this.boundaryClass,
    required this.documentId,
    required this.normalizationVersion,
    required this.speakText,
    required this.tokens,
    required this.languageTag,
    required this.voiceId,
    required this.rate,
    required this.isInitialChunk,
    required this.isResumedChunk,
    this.capabilityProfileId,
    this.pronunciationArtifacts = const <Map<String, Object?>>[],
    this.missingFallbackWordCount = 0,
  });

  final String chunkId;
  final List<String> segmentIds;
  final String cacheKey;
  final BreakClass boundaryClass;
  final String documentId;
  final String normalizationVersion;
  final String? capabilityProfileId;
  final String speakText;
  final List<int> tokens;
  final String languageTag;
  final String voiceId;
  final double rate;
  final bool isInitialChunk;
  final bool isResumedChunk;
  final List<Map<String, Object?>> pronunciationArtifacts;
  final int missingFallbackWordCount;

  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'chunkId': chunkId,
      'segmentIds': segmentIds,
      'cacheKey': cacheKey,
      'boundaryClass': boundaryClass.name,
      'documentId': documentId,
      'normalizationVersion': normalizationVersion,
      'capabilityProfileId': capabilityProfileId,
      'speakText': speakText,
      'tokens': tokens,
      'languageTag': languageTag,
      'voiceId': voiceId,
      'rate': rate,
      'isInitialChunk': isInitialChunk,
      'isResumedChunk': isResumedChunk,
      'pronunciationArtifacts': pronunciationArtifacts,
      'missingFallbackWordCount': missingFallbackWordCount,
    };
  }

  factory SpeechRuntimeChunkPayload.fromPayload(Map<String, Object?> map) {
    return SpeechRuntimeChunkPayload(
      chunkId: map['chunkId']! as String,
      segmentIds: List<String>.from(map['segmentIds']! as List<Object?>),
      cacheKey: map['cacheKey']! as String,
      boundaryClass: BreakClass.values.byName(map['boundaryClass']! as String),
      documentId: map['documentId']! as String,
      normalizationVersion: map['normalizationVersion']! as String,
      capabilityProfileId: map['capabilityProfileId'] as String?,
      speakText: map['speakText']! as String,
      tokens: List<int>.from(map['tokens']! as List<Object?>),
      languageTag: map['languageTag']! as String,
      voiceId: map['voiceId']! as String,
      rate: (map['rate']! as num).toDouble(),
      isInitialChunk: map['isInitialChunk']! as bool,
      isResumedChunk: map['isResumedChunk']! as bool,
      pronunciationArtifacts: List<Map<String, Object?>>.from(
        (map['pronunciationArtifacts'] as List<Object?>? ?? const <Object?>[])
            .map(
              (entry) =>
                  Map<String, Object?>.from(entry as Map<Object?, Object?>),
            ),
      ),
      missingFallbackWordCount:
          (map['missingFallbackWordCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SpeechRuntimeCommand {
  const SpeechRuntimeCommand._({
    required this.protocolVersion,
    required this.runtimeId,
    required this.messageId,
    required this.type,
    required this.issuedAt,
    required this.payload,
    this.engineId,
    this.preferredVoiceId,
    this.session,
    this.sessionId,
    this.generationId,
    this.chunk,
    this.chunks = const <SpeechRuntimeChunkPayload>[],
    this.reasonCode,
  });

  factory SpeechRuntimeCommand.initializeRuntime({
    required String runtimeId,
    required String messageId,
    required String engineId,
    String? preferredVoiceId,
  }) {
    final payload = <String, Object?>{'engineId': engineId};
    if (preferredVoiceId != null) {
      payload['preferredVoiceId'] = preferredVoiceId;
    }
    return SpeechRuntimeCommand._(
      protocolVersion: speechRuntimeProtocolVersion,
      runtimeId: runtimeId,
      messageId: messageId,
      type: SpeechRuntimeCommandType.initializeRuntime,
      issuedAt: DateTime.now().toUtc(),
      payload: payload,
      engineId: engineId,
      preferredVoiceId: preferredVoiceId,
    );
  }

  factory SpeechRuntimeCommand.activateSession({
    required String runtimeId,
    required String messageId,
    required SpeechRuntimeSessionDescriptor session,
  }) {
    return SpeechRuntimeCommand._(
      protocolVersion: speechRuntimeProtocolVersion,
      runtimeId: runtimeId,
      messageId: messageId,
      type: SpeechRuntimeCommandType.activateSession,
      issuedAt: DateTime.now().toUtc(),
      payload: session.toPayload(),
      session: session,
      sessionId: session.sessionId,
    );
  }

  factory SpeechRuntimeCommand.preparePriorityChunk({
    required String runtimeId,
    required String messageId,
    required String sessionId,
    required String generationId,
    required SpeechRuntimeChunkPayload chunk,
  }) {
    return SpeechRuntimeCommand._(
      protocolVersion: speechRuntimeProtocolVersion,
      runtimeId: runtimeId,
      messageId: messageId,
      type: SpeechRuntimeCommandType.preparePriorityChunk,
      issuedAt: DateTime.now().toUtc(),
      payload: <String, Object?>{
        'sessionId': sessionId,
        'generationId': generationId,
        'chunk': chunk.toPayload(),
      },
      sessionId: sessionId,
      generationId: generationId,
      chunk: chunk,
    );
  }

  factory SpeechRuntimeCommand.prepareChunkPlan({
    required String runtimeId,
    required String messageId,
    required String sessionId,
    required String generationId,
    required List<SpeechRuntimeChunkPayload> chunks,
  }) {
    return SpeechRuntimeCommand._(
      protocolVersion: speechRuntimeProtocolVersion,
      runtimeId: runtimeId,
      messageId: messageId,
      type: SpeechRuntimeCommandType.prepareChunkPlan,
      issuedAt: DateTime.now().toUtc(),
      payload: <String, Object?>{
        'sessionId': sessionId,
        'generationId': generationId,
        'chunks': chunks.map((chunk) => chunk.toPayload()).toList(),
      },
      sessionId: sessionId,
      generationId: generationId,
      chunks: chunks,
    );
  }

  factory SpeechRuntimeCommand.cancelSession({
    required String runtimeId,
    required String messageId,
    required String sessionId,
    String? reasonCode,
  }) {
    final payload = <String, Object?>{'sessionId': sessionId};
    if (reasonCode != null) {
      payload['reasonCode'] = reasonCode;
    }
    return SpeechRuntimeCommand._(
      protocolVersion: speechRuntimeProtocolVersion,
      runtimeId: runtimeId,
      messageId: messageId,
      type: SpeechRuntimeCommandType.cancelSession,
      issuedAt: DateTime.now().toUtc(),
      payload: payload,
      sessionId: sessionId,
      reasonCode: reasonCode,
    );
  }

  factory SpeechRuntimeCommand.shutdownRuntime({
    required String runtimeId,
    required String messageId,
  }) {
    return SpeechRuntimeCommand._(
      protocolVersion: speechRuntimeProtocolVersion,
      runtimeId: runtimeId,
      messageId: messageId,
      type: SpeechRuntimeCommandType.shutdownRuntime,
      issuedAt: DateTime.now().toUtc(),
      payload: const <String, Object?>{},
    );
  }

  factory SpeechRuntimeCommand.fromMap(Map<String, Object?> map) {
    final payload = Map<String, Object?>.from(
      map['payload']! as Map<Object?, Object?>,
    );
    final type = SpeechRuntimeCommandType.values.byName(map['type']! as String);
    return switch (type) {
      SpeechRuntimeCommandType.initializeRuntime =>
        SpeechRuntimeCommand.initializeRuntime(
          runtimeId: map['runtimeId']! as String,
          messageId: map['messageId']! as String,
          engineId: payload['engineId']! as String,
          preferredVoiceId: payload['preferredVoiceId'] as String?,
        ),
      SpeechRuntimeCommandType.activateSession =>
        SpeechRuntimeCommand.activateSession(
          runtimeId: map['runtimeId']! as String,
          messageId: map['messageId']! as String,
          session: SpeechRuntimeSessionDescriptor.fromPayload(payload),
        ),
      SpeechRuntimeCommandType.preparePriorityChunk =>
        SpeechRuntimeCommand.preparePriorityChunk(
          runtimeId: map['runtimeId']! as String,
          messageId: map['messageId']! as String,
          sessionId: payload['sessionId']! as String,
          generationId: payload['generationId']! as String,
          chunk: SpeechRuntimeChunkPayload.fromPayload(
            Map<String, Object?>.from(
              payload['chunk']! as Map<Object?, Object?>,
            ),
          ),
        ),
      SpeechRuntimeCommandType.prepareChunkPlan =>
        SpeechRuntimeCommand.prepareChunkPlan(
          runtimeId: map['runtimeId']! as String,
          messageId: map['messageId']! as String,
          sessionId: payload['sessionId']! as String,
          generationId: payload['generationId']! as String,
          chunks: (payload['chunks']! as List<Object?>)
              .map(
                (chunk) => SpeechRuntimeChunkPayload.fromPayload(
                  Map<String, Object?>.from(chunk! as Map<Object?, Object?>),
                ),
              )
              .toList(growable: false),
        ),
      SpeechRuntimeCommandType.cancelSession =>
        SpeechRuntimeCommand.cancelSession(
          runtimeId: map['runtimeId']! as String,
          messageId: map['messageId']! as String,
          sessionId: payload['sessionId']! as String,
          reasonCode: payload['reasonCode'] as String?,
        ),
      SpeechRuntimeCommandType.shutdownRuntime =>
        SpeechRuntimeCommand.shutdownRuntime(
          runtimeId: map['runtimeId']! as String,
          messageId: map['messageId']! as String,
        ),
    };
  }

  final String protocolVersion;
  final String runtimeId;
  final String messageId;
  final SpeechRuntimeCommandType type;
  final DateTime issuedAt;
  final Map<String, Object?> payload;
  final String? engineId;
  final String? preferredVoiceId;
  final SpeechRuntimeSessionDescriptor? session;
  final String? sessionId;
  final String? generationId;
  final SpeechRuntimeChunkPayload? chunk;
  final List<SpeechRuntimeChunkPayload> chunks;
  final String? reasonCode;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'runtimeId': runtimeId,
      'messageId': messageId,
      'type': type.name,
      'issuedAtMillis': issuedAt.millisecondsSinceEpoch,
      'payload': payload,
    };
  }
}

class SpeechRuntimeEvent {
  const SpeechRuntimeEvent({
    required this.protocolVersion,
    required this.runtimeId,
    required this.messageId,
    required this.type,
    required this.emittedAt,
    required this.payload,
    this.engineId,
    this.capabilities,
    this.sessionId,
    this.documentId,
    this.voiceId,
    this.rate,
    this.generationId,
    this.chunkId,
    this.audioPath,
    this.duration,
    this.stage,
    this.elapsedMillis,
    this.boundaryClass,
    this.leadingSilenceBefore,
    this.leadingSilence,
    this.trailingSilenceBefore,
    this.trailingSilence,
    this.joinSilenceBefore,
    this.joinSilenceAfter,
    this.cacheHit,
    this.boundaryCorrectionApplied,
    this.isInitialChunk,
    this.isResumedChunk,
    this.errorCode,
    this.message,
    this.fatalForSession,
    this.reasonCode,
  });

  factory SpeechRuntimeEvent.fromMap(Map<String, Object?> map) {
    final payload = Map<String, Object?>.from(
      map['payload']! as Map<Object?, Object?>,
    );
    final durationMillis = payload['durationMillis'] as int?;
    final boundaryClassName = payload['boundaryClass'] as String?;
    final leadingSilenceBeforeMs = payload['leadingSilenceBeforeMs'] as int?;
    final leadingSilenceMs = payload['leadingSilenceMs'] as int?;
    final trailingSilenceBeforeMs = payload['trailingSilenceBeforeMs'] as int?;
    final trailingSilenceMs = payload['trailingSilenceMs'] as int?;
    final joinSilenceBeforeMs = payload['joinSilenceBeforeMs'] as int?;
    final joinSilenceAfterMs = payload['joinSilenceAfterMs'] as int?;
    final capabilitiesMap = payload['capabilities'] as Map<Object?, Object?>?;

    return SpeechRuntimeEvent(
      protocolVersion: map['protocolVersion']! as String,
      runtimeId: map['runtimeId']! as String,
      messageId: map['messageId']! as String,
      type: SpeechRuntimeEventType.values.byName(map['type']! as String),
      emittedAt: DateTime.fromMillisecondsSinceEpoch(
        map['emittedAtMillis']! as int,
        isUtc: true,
      ),
      payload: payload,
      engineId: payload['engineId'] as String?,
      capabilities: capabilitiesMap == null
          ? null
          : SpeechRuntimeCapabilities.fromMap(
              capabilitiesMap.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
      sessionId: payload['sessionId'] as String?,
      documentId: payload['documentId'] as String?,
      voiceId: payload['voiceId'] as String?,
      rate: (payload['rate'] as num?)?.toDouble(),
      generationId: payload['generationId'] as String?,
      chunkId: payload['chunkId'] as String?,
      audioPath: payload['audioPath'] as String?,
      duration: durationMillis == null
          ? null
          : Duration(milliseconds: durationMillis),
      stage: payload['stage'] as String?,
      elapsedMillis: payload['elapsedMillis'] as int?,
      boundaryClass: boundaryClassName == null
          ? null
          : BreakClass.values.byName(boundaryClassName),
      leadingSilenceBefore: leadingSilenceBeforeMs == null
          ? null
          : Duration(milliseconds: leadingSilenceBeforeMs),
      leadingSilence: leadingSilenceMs == null
          ? null
          : Duration(milliseconds: leadingSilenceMs),
      trailingSilenceBefore: trailingSilenceBeforeMs == null
          ? null
          : Duration(milliseconds: trailingSilenceBeforeMs),
      trailingSilence: trailingSilenceMs == null
          ? null
          : Duration(milliseconds: trailingSilenceMs),
      joinSilenceBefore: joinSilenceBeforeMs == null
          ? null
          : Duration(milliseconds: joinSilenceBeforeMs),
      joinSilenceAfter: joinSilenceAfterMs == null
          ? null
          : Duration(milliseconds: joinSilenceAfterMs),
      cacheHit: payload['cacheHit'] as bool?,
      boundaryCorrectionApplied: payload['boundaryCorrectionApplied'] as bool?,
      isInitialChunk: payload['isInitialChunk'] as bool?,
      isResumedChunk: payload['isResumedChunk'] as bool?,
      errorCode: payload['errorCode'] as String?,
      message: payload['message'] as String?,
      fatalForSession: payload['fatalForSession'] as bool?,
      reasonCode: payload['reasonCode'] as String?,
    );
  }

  final String protocolVersion;
  final String runtimeId;
  final String messageId;
  final SpeechRuntimeEventType type;
  final DateTime emittedAt;
  final Map<String, Object?> payload;
  final String? engineId;
  final SpeechRuntimeCapabilities? capabilities;
  final String? sessionId;
  final String? documentId;
  final String? voiceId;
  final double? rate;
  final String? generationId;
  final String? chunkId;
  final String? audioPath;
  final Duration? duration;
  final String? stage;
  final int? elapsedMillis;
  final BreakClass? boundaryClass;
  final Duration? leadingSilenceBefore;
  final Duration? leadingSilence;
  final Duration? trailingSilenceBefore;
  final Duration? trailingSilence;
  final Duration? joinSilenceBefore;
  final Duration? joinSilenceAfter;
  final bool? cacheHit;
  final bool? boundaryCorrectionApplied;
  final bool? isInitialChunk;
  final bool? isResumedChunk;
  final String? errorCode;
  final String? message;
  final bool? fatalForSession;
  final String? reasonCode;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'runtimeId': runtimeId,
      'messageId': messageId,
      'type': type.name,
      'emittedAtMillis': emittedAt.millisecondsSinceEpoch,
      'payload': payload,
    };
  }
}

typedef BoundaryCorrectionExecutor =
    Future<Map<String, Object?>> Function(Map<String, Object?> input);

class SpeechRuntime {
  SpeechRuntime({
    required this.engineId,
    required SpeechWorkerChunkProcessor processor,
    String? runtimeId,
    BoundaryCorrectionExecutor? boundaryCorrectionExecutor,
  }) : runtimeId = runtimeId ?? _nextRuntimeId(),
       capabilities = SpeechRuntimeCapabilities.detectForCurrentPlatform(
         engineId: engineId,
       ),
       _pipeline = SpeechWorkerPipeline(processor: processor),
       _boundaryCorrectionExecutor =
           boundaryCorrectionExecutor ?? _defaultBoundaryCorrectionExecutor {
    _workerEventSubscription = _pipeline.events.listen(_handleWorkerEvent);
  }

  final String engineId;
  final String runtimeId;
  final SpeechRuntimeCapabilities capabilities;
  final SpeechWorkerPipeline _pipeline;
  final BoundaryCorrectionExecutor _boundaryCorrectionExecutor;
  final StreamController<SpeechRuntimeEvent> _eventsController =
      StreamController<SpeechRuntimeEvent>.broadcast();
  final Map<String, _RuntimeChunkWorkItem> _pendingChunksById =
      <String, _RuntimeChunkWorkItem>{};
  final Set<String> _cacheHitChunkIds = <String>{};
  final Map<String, Duration> _lastTrailingSilenceByGenerationId =
      <String, Duration>{};

  StreamSubscription<SpeechWorkerEvent>? _workerEventSubscription;
  Future<void> _commandQueue = Future<void>.value();
  SpeechRuntimeLifecycleState _state =
      SpeechRuntimeLifecycleState.uninitialized;
  String? _activeSessionId;
  String? _activeGenerationId;
  String? _activeDocumentId;
  String? _activeVoiceId;
  double? _activeRate;
  int _messageCounter = 0;

  Stream<SpeechRuntimeEvent> get events => _eventsController.stream;
  SpeechRuntimeLifecycleState get state => _state;

  Future<void> initializeRuntime({String? preferredVoiceId}) {
    return dispatch(
      SpeechRuntimeCommand.initializeRuntime(
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        engineId: engineId,
        preferredVoiceId: preferredVoiceId,
      ),
    );
  }

  Future<void> activateSession(SpeechRuntimeSessionDescriptor session) {
    return dispatch(
      SpeechRuntimeCommand.activateSession(
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        session: session,
      ),
    );
  }

  Future<void> preparePriorityChunk({
    required String sessionId,
    required String generationId,
    required SpeechRuntimeChunkPayload chunk,
  }) {
    return dispatch(
      SpeechRuntimeCommand.preparePriorityChunk(
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        sessionId: sessionId,
        generationId: generationId,
        chunk: chunk,
      ),
    );
  }

  Future<void> prepareChunkPlan({
    required String sessionId,
    required String generationId,
    required List<SpeechRuntimeChunkPayload> chunks,
  }) {
    return dispatch(
      SpeechRuntimeCommand.prepareChunkPlan(
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        sessionId: sessionId,
        generationId: generationId,
        chunks: chunks,
      ),
    );
  }

  Future<void> cancelSession(String sessionId, {String? reasonCode}) {
    return dispatch(
      SpeechRuntimeCommand.cancelSession(
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        sessionId: sessionId,
        reasonCode: reasonCode,
      ),
    );
  }

  Future<void> shutdownRuntime() {
    return dispatch(
      SpeechRuntimeCommand.shutdownRuntime(
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
      ),
    );
  }

  Future<void> dispatch(SpeechRuntimeCommand command) {
    _commandQueue = _commandQueue.then((_) => _dispatchInternal(command));
    return _commandQueue;
  }

  Future<void> _dispatchInternal(SpeechRuntimeCommand command) async {
    if (_state == SpeechRuntimeLifecycleState.disposed &&
        command.type != SpeechRuntimeCommandType.shutdownRuntime) {
      throw StateError('Speech runtime has already been disposed.');
    }

    switch (command.type) {
      case SpeechRuntimeCommandType.initializeRuntime:
        await _handleInitializeRuntime(command);
      case SpeechRuntimeCommandType.activateSession:
        await _handleActivateSession(command.session!);
      case SpeechRuntimeCommandType.preparePriorityChunk:
        await _handlePreparePriorityChunk(
          sessionId: command.sessionId!,
          generationId: command.generationId!,
          chunk: command.chunk!,
        );
      case SpeechRuntimeCommandType.prepareChunkPlan:
        await _handlePrepareChunkPlan(
          sessionId: command.sessionId!,
          generationId: command.generationId!,
          chunks: command.chunks,
        );
      case SpeechRuntimeCommandType.cancelSession:
        await _handleCancelSession(
          command.sessionId!,
          reasonCode: command.reasonCode,
        );
      case SpeechRuntimeCommandType.shutdownRuntime:
        await _handleShutdownRuntime();
    }
  }

  Future<void> _handleInitializeRuntime(SpeechRuntimeCommand command) async {
    if (_state == SpeechRuntimeLifecycleState.idle ||
        _state == SpeechRuntimeLifecycleState.sessionActive) {
      return;
    }
    if (_state == SpeechRuntimeLifecycleState.shuttingDown ||
        _state == SpeechRuntimeLifecycleState.disposed) {
      throw StateError('Speech runtime cannot be initialized after shutdown.');
    }

    _state = SpeechRuntimeLifecycleState.initializing;
    if (!capabilities.isEngineSupported) {
      _state = SpeechRuntimeLifecycleState.failed;
      _emit(
        SpeechRuntimeEvent(
          protocolVersion: speechRuntimeProtocolVersion,
          runtimeId: runtimeId,
          messageId: _nextMessageId(),
          type: SpeechRuntimeEventType.runtimeFailed,
          emittedAt: DateTime.now().toUtc(),
          payload: <String, Object?>{
            'errorCode': 'engineUnsupported',
            'message':
                '$engineId is not supported on this Flutter platform path.',
          },
          errorCode: 'engineUnsupported',
          message: '$engineId is not supported on this Flutter platform path.',
        ),
      );
      return;
    }

    _state = SpeechRuntimeLifecycleState.idle;
    _emit(
      SpeechRuntimeEvent(
        protocolVersion: speechRuntimeProtocolVersion,
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        type: SpeechRuntimeEventType.runtimeInitialized,
        emittedAt: DateTime.now().toUtc(),
        payload: <String, Object?>{
          'engineId': command.engineId!,
          'capabilities': capabilities.toMap(),
          if (command.preferredVoiceId != null)
            'preferredVoiceId': command.preferredVoiceId,
        },
        engineId: command.engineId,
        capabilities: capabilities,
      ),
    );
  }

  Future<void> _handleActivateSession(
    SpeechRuntimeSessionDescriptor session,
  ) async {
    _ensureRuntimeReady();
    if (_activeSessionId != null && _activeSessionId != session.sessionId) {
      await _cancelActiveSession(reasonCode: 'replaced');
    }

    _activeSessionId = session.sessionId;
    _activeGenerationId = null;
    _activeDocumentId = session.documentId;
    _activeVoiceId = session.voiceId;
    _activeRate = session.rate;
    _state = SpeechRuntimeLifecycleState.sessionActive;

    _emit(
      SpeechRuntimeEvent(
        protocolVersion: speechRuntimeProtocolVersion,
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        type: SpeechRuntimeEventType.sessionActivated,
        emittedAt: DateTime.now().toUtc(),
        payload: <String, Object?>{
          'sessionId': session.sessionId,
          'documentId': session.documentId,
          'voiceId': session.voiceId,
          'rate': session.rate,
        },
        sessionId: session.sessionId,
        documentId: session.documentId,
        voiceId: session.voiceId,
        rate: session.rate,
      ),
    );
  }

  Future<void> _handlePreparePriorityChunk({
    required String sessionId,
    required String generationId,
    required SpeechRuntimeChunkPayload chunk,
  }) async {
    _ensureActiveSession(sessionId);
    _activeGenerationId = generationId;
    _pendingChunksById[chunk.chunkId] = _RuntimeChunkWorkItem(
      sessionId: sessionId,
      generationId: generationId,
      chunk: chunk,
    );
    _cacheHitChunkIds.remove(chunk.chunkId);
    await _pipeline.prepareChunk(
      SpeechWorkerChunkRequest(
        sessionId: sessionId,
        generationId: generationId,
        chunkId: chunk.chunkId,
        segmentIds: chunk.segmentIds,
        cacheKey: chunk.cacheKey,
        boundaryClass: chunk.boundaryClass,
        documentId: chunk.documentId,
        normalizationVersion: chunk.normalizationVersion,
        speakText: chunk.speakText,
        tokens: chunk.tokens,
        languageTag: chunk.languageTag,
        voiceId: chunk.voiceId,
        rate: chunk.rate,
        capabilityProfileId: chunk.capabilityProfileId,
        pronunciationArtifacts: chunk.pronunciationArtifacts,
        missingFallbackWordCount: chunk.missingFallbackWordCount,
      ),
    );
  }

  Future<void> _handlePrepareChunkPlan({
    required String sessionId,
    required String generationId,
    required List<SpeechRuntimeChunkPayload> chunks,
  }) async {
    _ensureActiveSession(sessionId);
    _activeGenerationId = generationId;
    for (final chunk in chunks) {
      _pendingChunksById[chunk.chunkId] = _RuntimeChunkWorkItem(
        sessionId: sessionId,
        generationId: generationId,
        chunk: chunk,
      );
      _cacheHitChunkIds.remove(chunk.chunkId);
    }
    await _pipeline.preparePlan(
      generationId,
      chunks
          .map(
            (chunk) => SpeechWorkerChunkRequest(
              sessionId: sessionId,
              generationId: generationId,
              chunkId: chunk.chunkId,
              segmentIds: chunk.segmentIds,
              cacheKey: chunk.cacheKey,
              boundaryClass: chunk.boundaryClass,
              documentId: chunk.documentId,
              normalizationVersion: chunk.normalizationVersion,
              speakText: chunk.speakText,
              tokens: chunk.tokens,
              languageTag: chunk.languageTag,
              voiceId: chunk.voiceId,
              rate: chunk.rate,
              capabilityProfileId: chunk.capabilityProfileId,
              pronunciationArtifacts: chunk.pronunciationArtifacts,
              missingFallbackWordCount: chunk.missingFallbackWordCount,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _handleCancelSession(
    String sessionId, {
    String? reasonCode,
  }) async {
    if (_activeSessionId != sessionId) {
      return;
    }
    await _cancelActiveSession(reasonCode: reasonCode ?? 'cancelled');
  }

  Future<void> _handleShutdownRuntime() async {
    if (_state == SpeechRuntimeLifecycleState.disposed ||
        _state == SpeechRuntimeLifecycleState.shuttingDown) {
      return;
    }

    _state = SpeechRuntimeLifecycleState.shuttingDown;
    await _cancelActiveSession(reasonCode: 'shutdown');
    await _pipeline.shutdown();
    await _workerEventSubscription?.cancel();
    _state = SpeechRuntimeLifecycleState.disposed;

    _emit(
      SpeechRuntimeEvent(
        protocolVersion: speechRuntimeProtocolVersion,
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        type: SpeechRuntimeEventType.runtimeShutdown,
        emittedAt: DateTime.now().toUtc(),
        payload: const <String, Object?>{},
      ),
    );
    await _eventsController.close();
  }

  Future<void> _cancelActiveSession({required String reasonCode}) async {
    final sessionId = _activeSessionId;
    final generationId = _activeGenerationId;
    if (sessionId == null) {
      return;
    }

    if (generationId != null) {
      await _pipeline.cancelGeneration(generationId);
      _lastTrailingSilenceByGenerationId.remove(generationId);
    }

    _pendingChunksById.removeWhere((_, item) => item.sessionId == sessionId);
    _cacheHitChunkIds.clear();
    _activeSessionId = null;
    _activeGenerationId = null;
    _activeDocumentId = null;
    _activeVoiceId = null;
    _activeRate = null;
    _state = SpeechRuntimeLifecycleState.idle;

    _emit(
      SpeechRuntimeEvent(
        protocolVersion: speechRuntimeProtocolVersion,
        runtimeId: runtimeId,
        messageId: _nextMessageId(),
        type: SpeechRuntimeEventType.sessionCancelled,
        emittedAt: DateTime.now().toUtc(),
        payload: <String, Object?>{
          'sessionId': sessionId,
          'reasonCode': reasonCode,
        },
        sessionId: sessionId,
        reasonCode: reasonCode,
      ),
    );
  }

  void _handleWorkerEvent(SpeechWorkerEvent event) {
    final activeSessionId = _activeSessionId;
    final activeGenerationId = _activeGenerationId;
    if (activeSessionId == null ||
        event.sessionId != activeSessionId ||
        event.generationId != activeGenerationId) {
      return;
    }

    switch (event.type) {
      case SpeechWorkerEventType.queued:
        _emit(
          _runtimeEvent(
            type: SpeechRuntimeEventType.chunkQueued,
            sessionId: event.sessionId,
            generationId: event.generationId,
            chunkId: event.chunkId,
          ),
        );
      case SpeechWorkerEventType.cacheHit:
        _cacheHitChunkIds.add(event.chunkId);
        _emit(
          _runtimeEvent(
            type: SpeechRuntimeEventType.chunkCacheHit,
            sessionId: event.sessionId,
            generationId: event.generationId,
            chunkId: event.chunkId,
            audioPath: event.audioPath,
            duration: event.duration,
          ),
        );
      case SpeechWorkerEventType.phonemizing:
      case SpeechWorkerEventType.inferencing:
      case SpeechWorkerEventType.serializing:
        _emit(
          _runtimeEvent(
            type: SpeechRuntimeEventType.chunkStageChanged,
            sessionId: event.sessionId,
            generationId: event.generationId,
            chunkId: event.chunkId,
            stage: event.stage,
            elapsedMillis: event.elapsedMillis,
          ),
        );
      case SpeechWorkerEventType.completed:
        unawaited(_handleWorkerCompleted(event));
      case SpeechWorkerEventType.failed:
        _pendingChunksById.remove(event.chunkId);
        _emit(
          _runtimeEvent(
            type: SpeechRuntimeEventType.chunkFailed,
            sessionId: event.sessionId,
            generationId: event.generationId,
            chunkId: event.chunkId,
            errorCode: 'workerFailure',
            message: event.message,
          ),
        );
      case SpeechWorkerEventType.cancelled:
        _pendingChunksById.remove(event.chunkId);
    }
  }

  Future<void> _handleWorkerCompleted(SpeechWorkerEvent event) async {
    final workItem = _pendingChunksById[event.chunkId];
    if (workItem == null || event.audioPath == null || event.duration == null) {
      return;
    }

    _emit(
      _runtimeEvent(
        type: SpeechRuntimeEventType.chunkStageChanged,
        sessionId: workItem.sessionId,
        generationId: workItem.generationId,
        chunkId: workItem.chunk.chunkId,
        stage: 'boundaryCorrecting',
      ),
    );

    try {
      final correction = await _boundaryCorrectionExecutor(<String, Object?>{
        'chunkId': workItem.chunk.chunkId,
        'wavFilePath': event.audioPath!,
        'boundaryClass': workItem.chunk.boundaryClass.name,
        'isInitialChunk': workItem.chunk.isInitialChunk,
        'isResumedChunk': workItem.chunk.isResumedChunk,
        'previousTrailingSilenceMs':
            workItem.chunk.isInitialChunk || workItem.chunk.isResumedChunk
            ? null
            : _lastTrailingSilenceByGenerationId[workItem.generationId]
                  ?.inMilliseconds,
      });

      if (_activeSessionId != workItem.sessionId ||
          _activeGenerationId != workItem.generationId) {
        return;
      }

      _pendingChunksById.remove(event.chunkId);
      final trailingSilence = Duration(
        milliseconds: correction['trailingSilenceAfterMs']! as int,
      );
      _lastTrailingSilenceByGenerationId[workItem.generationId] =
          trailingSilence;

      _emit(
        _runtimeEvent(
          type: SpeechRuntimeEventType.chunkReady,
          sessionId: workItem.sessionId,
          generationId: workItem.generationId,
          chunkId: workItem.chunk.chunkId,
          audioPath: event.audioPath,
          duration: event.duration,
          boundaryClass: workItem.chunk.boundaryClass,
          leadingSilenceBefore: Duration(
            milliseconds: correction['leadingSilenceBeforeMs']! as int,
          ),
          leadingSilence: Duration(
            milliseconds: correction['leadingSilenceAfterMs']! as int,
          ),
          trailingSilenceBefore: Duration(
            milliseconds: correction['trailingSilenceBeforeMs']! as int,
          ),
          trailingSilence: trailingSilence,
          joinSilenceBefore: Duration(
            milliseconds: correction['joinSilenceBeforeMs']! as int,
          ),
          joinSilenceAfter: Duration(
            milliseconds: correction['joinSilenceAfterMs']! as int,
          ),
          cacheHit: _cacheHitChunkIds.contains(event.chunkId),
          boundaryCorrectionApplied: correction['applied']! as bool,
          isInitialChunk: workItem.chunk.isInitialChunk,
          isResumedChunk: workItem.chunk.isResumedChunk,
        ),
      );
    } catch (error) {
      _pendingChunksById.remove(event.chunkId);
      _emit(
        _runtimeEvent(
          type: SpeechRuntimeEventType.chunkFailed,
          sessionId: workItem.sessionId,
          generationId: workItem.generationId,
          chunkId: workItem.chunk.chunkId,
          errorCode: 'boundaryCorrectionFailed',
          message: '$error',
          fatalForSession: false,
        ),
      );
    }
  }

  SpeechRuntimeEvent _runtimeEvent({
    required SpeechRuntimeEventType type,
    required String sessionId,
    String? generationId,
    String? chunkId,
    String? audioPath,
    Duration? duration,
    String? stage,
    int? elapsedMillis,
    BreakClass? boundaryClass,
    Duration? leadingSilenceBefore,
    Duration? leadingSilence,
    Duration? trailingSilenceBefore,
    Duration? trailingSilence,
    Duration? joinSilenceBefore,
    Duration? joinSilenceAfter,
    bool? cacheHit,
    bool? boundaryCorrectionApplied,
    bool? isInitialChunk,
    bool? isResumedChunk,
    String? errorCode,
    String? message,
    bool? fatalForSession,
    String? reasonCode,
  }) {
    final payload = <String, Object?>{'sessionId': sessionId};
    if (_activeDocumentId != null) {
      payload['documentId'] = _activeDocumentId;
    }
    if (_activeVoiceId != null) {
      payload['voiceId'] = _activeVoiceId;
    }
    if (_activeRate != null) {
      payload['rate'] = _activeRate;
    }
    if (generationId != null) {
      payload['generationId'] = generationId;
    }
    if (chunkId != null) {
      payload['chunkId'] = chunkId;
    }
    if (audioPath != null) {
      payload['audioPath'] = audioPath;
    }
    if (duration != null) {
      payload['durationMillis'] = duration.inMilliseconds;
    }
    if (stage != null) {
      payload['stage'] = stage;
    }
    if (elapsedMillis != null) {
      payload['elapsedMillis'] = elapsedMillis;
    }
    if (boundaryClass != null) {
      payload['boundaryClass'] = boundaryClass.name;
    }
    if (leadingSilenceBefore != null) {
      payload['leadingSilenceBeforeMs'] = leadingSilenceBefore.inMilliseconds;
    }
    if (leadingSilence != null) {
      payload['leadingSilenceMs'] = leadingSilence.inMilliseconds;
    }
    if (trailingSilenceBefore != null) {
      payload['trailingSilenceBeforeMs'] = trailingSilenceBefore.inMilliseconds;
    }
    if (trailingSilence != null) {
      payload['trailingSilenceMs'] = trailingSilence.inMilliseconds;
    }
    if (joinSilenceBefore != null) {
      payload['joinSilenceBeforeMs'] = joinSilenceBefore.inMilliseconds;
    }
    if (joinSilenceAfter != null) {
      payload['joinSilenceAfterMs'] = joinSilenceAfter.inMilliseconds;
    }
    if (cacheHit != null) {
      payload['cacheHit'] = cacheHit;
    }
    if (boundaryCorrectionApplied != null) {
      payload['boundaryCorrectionApplied'] = boundaryCorrectionApplied;
    }
    if (isInitialChunk != null) {
      payload['isInitialChunk'] = isInitialChunk;
    }
    if (isResumedChunk != null) {
      payload['isResumedChunk'] = isResumedChunk;
    }
    if (errorCode != null) {
      payload['errorCode'] = errorCode;
    }
    if (message != null) {
      payload['message'] = message;
    }
    if (fatalForSession != null) {
      payload['fatalForSession'] = fatalForSession;
    }
    if (reasonCode != null) {
      payload['reasonCode'] = reasonCode;
    }

    return SpeechRuntimeEvent(
      protocolVersion: speechRuntimeProtocolVersion,
      runtimeId: runtimeId,
      messageId: _nextMessageId(),
      type: type,
      emittedAt: DateTime.now().toUtc(),
      payload: payload,
      sessionId: sessionId,
      documentId: _activeDocumentId,
      voiceId: _activeVoiceId,
      rate: _activeRate,
      generationId: generationId,
      chunkId: chunkId,
      audioPath: audioPath,
      duration: duration,
      stage: stage,
      elapsedMillis: elapsedMillis,
      boundaryClass: boundaryClass,
      leadingSilenceBefore: leadingSilenceBefore,
      leadingSilence: leadingSilence,
      trailingSilenceBefore: trailingSilenceBefore,
      trailingSilence: trailingSilence,
      joinSilenceBefore: joinSilenceBefore,
      joinSilenceAfter: joinSilenceAfter,
      cacheHit: cacheHit,
      boundaryCorrectionApplied: boundaryCorrectionApplied,
      isInitialChunk: isInitialChunk,
      isResumedChunk: isResumedChunk,
      errorCode: errorCode,
      message: message,
      fatalForSession: fatalForSession,
      reasonCode: reasonCode,
    );
  }

  void _emit(SpeechRuntimeEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  void _ensureRuntimeReady() {
    if (_state == SpeechRuntimeLifecycleState.uninitialized ||
        _state == SpeechRuntimeLifecycleState.initializing) {
      throw StateError('Speech runtime must be initialized before use.');
    }
    if (_state == SpeechRuntimeLifecycleState.failed) {
      throw StateError('Speech runtime is in a failed state.');
    }
  }

  void _ensureActiveSession(String sessionId) {
    _ensureRuntimeReady();
    if (_activeSessionId != sessionId) {
      throw StateError(
        'Speech runtime session mismatch. '
        'Expected $_activeSessionId but received $sessionId.',
      );
    }
  }

  String _nextMessageId() {
    _messageCounter += 1;
    return 'message_${_messageCounter.toString().padLeft(4, '0')}';
  }
}

Future<Map<String, Object?>> _defaultBoundaryCorrectionExecutor(
  Map<String, Object?> input,
) {
  return compute(runSpeechRuntimeBoundaryCorrection, input);
}

Map<String, Object?> runSpeechRuntimeBoundaryCorrection(
  Map<String, Object?> input,
) {
  final previousTrailingSilenceMs = input['previousTrailingSilenceMs'] as int?;
  final outcome = const SynthesisBoundaryPolicy().correctWavFileSync(
    chunkId: input['chunkId']! as String,
    wavFilePath: input['wavFilePath']! as String,
    boundaryClass: BreakClass.values.byName(input['boundaryClass']! as String),
    isInitialChunk: input['isInitialChunk']! as bool,
    isResumedChunk: input['isResumedChunk']! as bool,
    previousTrailingSilence: previousTrailingSilenceMs == null
        ? null
        : Duration(milliseconds: previousTrailingSilenceMs),
  );
  return <String, Object?>{
    'applied': outcome.applied,
    'boundaryClass': outcome.candidate.boundaryClass.name,
    'leadingSilenceBeforeMs': outcome.leadingSilenceBefore.inMilliseconds,
    'leadingSilenceAfterMs': outcome.leadingSilenceAfter.inMilliseconds,
    'trailingSilenceBeforeMs': outcome.trailingSilenceBefore.inMilliseconds,
    'trailingSilenceAfterMs': outcome.trailingSilenceAfter.inMilliseconds,
    'joinSilenceBeforeMs': outcome.joinSilenceBefore.inMilliseconds,
    'joinSilenceAfterMs': outcome.joinSilenceAfter.inMilliseconds,
  };
}

String _nextRuntimeId() {
  return 'runtime_${DateTime.now().microsecondsSinceEpoch}';
}

class _RuntimeChunkWorkItem {
  const _RuntimeChunkWorkItem({
    required this.sessionId,
    required this.generationId,
    required this.chunk,
  });

  final String sessionId;
  final String generationId;
  final SpeechRuntimeChunkPayload chunk;
}
