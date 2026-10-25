import 'dart:async';
import 'dart:collection';

import '../models/speech_annotation.dart';

enum SpeechWorkerCommandType {
  prepareChunk,
  preparePlan,
  cancelGeneration,
  shutdown,
}

class SpeechWorkerCommand {
  SpeechWorkerCommand._({
    required this.type,
    this.generationId,
    this.chunks = const <SpeechWorkerChunkRequest>[],
  });

  SpeechWorkerCommand.prepareChunk(SpeechWorkerChunkRequest chunk)
    : this._(
        type: SpeechWorkerCommandType.prepareChunk,
        generationId: chunk.generationId,
        chunks: <SpeechWorkerChunkRequest>[chunk],
      );

  SpeechWorkerCommand.preparePlan({
    required String generationId,
    required List<SpeechWorkerChunkRequest> chunks,
  }) : this._(
         type: SpeechWorkerCommandType.preparePlan,
         generationId: generationId,
         chunks: chunks,
       );

  SpeechWorkerCommand.cancelGeneration(String generationId)
    : this._(
        type: SpeechWorkerCommandType.cancelGeneration,
        generationId: generationId,
      );

  SpeechWorkerCommand.shutdown()
    : this._(type: SpeechWorkerCommandType.shutdown);

  final SpeechWorkerCommandType type;
  final String? generationId;
  final List<SpeechWorkerChunkRequest> chunks;
}

class SpeechWorkerChunkRequest {
  const SpeechWorkerChunkRequest({
    required this.sessionId,
    required this.generationId,
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
    this.capabilityProfileId,
    this.pronunciationArtifacts = const <Map<String, Object?>>[],
    this.missingFallbackWordCount = 0,
  });

  final String sessionId;
  final String generationId;
  final String chunkId;
  final List<String> segmentIds;
  final String cacheKey;
  final BreakClass boundaryClass;
  final String documentId;
  final String normalizationVersion;
  final String speakText;
  final List<int> tokens;
  final String languageTag;
  final String voiceId;
  final double rate;
  final String? capabilityProfileId;
  final List<Map<String, Object?>> pronunciationArtifacts;
  final int missingFallbackWordCount;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'generationId': generationId,
      'chunkId': chunkId,
      'segmentIds': segmentIds,
      'cacheKey': cacheKey,
      'boundaryClass': boundaryClass.name,
      'documentId': documentId,
      'normalizationVersion': normalizationVersion,
      'speakText': speakText,
      'tokens': tokens,
      'languageTag': languageTag,
      'voiceId': voiceId,
      'rate': rate,
      'capabilityProfileId': capabilityProfileId,
      'pronunciationArtifacts': pronunciationArtifacts,
      'missingFallbackWordCount': missingFallbackWordCount,
    };
  }

  factory SpeechWorkerChunkRequest.fromMap(Map<String, dynamic> map) {
    return SpeechWorkerChunkRequest(
      sessionId: map['sessionId'] as String,
      generationId: map['generationId'] as String,
      chunkId: map['chunkId'] as String,
      segmentIds: List<String>.from(map['segmentIds'] as List<dynamic>),
      cacheKey: map['cacheKey'] as String,
      boundaryClass: BreakClass.values.byName(map['boundaryClass'] as String),
      documentId: map['documentId'] as String,
      normalizationVersion: map['normalizationVersion'] as String,
      speakText: map['speakText'] as String,
      tokens: List<int>.from(map['tokens'] as List<dynamic>),
      languageTag: map['languageTag'] as String,
      voiceId: map['voiceId'] as String,
      rate: (map['rate'] as num).toDouble(),
      capabilityProfileId: map['capabilityProfileId'] as String?,
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

enum SpeechWorkerEventType {
  queued,
  cacheHit,
  phonemizing,
  inferencing,
  serializing,
  completed,
  failed,
  cancelled,
}

class SpeechWorkerEvent {
  const SpeechWorkerEvent({
    required this.type,
    required this.sessionId,
    required this.generationId,
    required this.chunkId,
    required this.emittedAt,
    required this.stage,
    this.audioPath,
    this.duration,
    this.message,
    this.elapsedMillis,
  });

  final SpeechWorkerEventType type;
  final String sessionId;
  final String generationId;
  final String chunkId;
  final DateTime emittedAt;
  final String stage;
  final String? audioPath;
  final Duration? duration;
  final String? message;
  final int? elapsedMillis;

  bool get isTerminal =>
      type == SpeechWorkerEventType.completed ||
      type == SpeechWorkerEventType.failed ||
      type == SpeechWorkerEventType.cancelled;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.name,
      'sessionId': sessionId,
      'generationId': generationId,
      'chunkId': chunkId,
      'emittedAtMillis': emittedAt.millisecondsSinceEpoch,
      'stage': stage,
      'audioPath': audioPath,
      'durationMillis': duration?.inMilliseconds,
      'message': message,
      'elapsedMillis': elapsedMillis,
    };
  }

  factory SpeechWorkerEvent.fromMap(Map<String, dynamic> map) {
    final durationMillis = map['durationMillis'];
    return SpeechWorkerEvent(
      type: SpeechWorkerEventType.values.byName(map['type'] as String),
      sessionId: map['sessionId'] as String,
      generationId: map['generationId'] as String,
      chunkId: map['chunkId'] as String,
      emittedAt: DateTime.fromMillisecondsSinceEpoch(
        map['emittedAtMillis'] as int,
      ),
      stage: map['stage'] as String,
      audioPath: map['audioPath'] as String?,
      duration: durationMillis == null
          ? null
          : Duration(milliseconds: durationMillis as int),
      message: map['message'] as String?,
      elapsedMillis: map['elapsedMillis'] as int?,
    );
  }
}

abstract interface class SpeechWorkerChunkProcessor {
  Future<void> process(
    SpeechWorkerChunkRequest request,
    void Function(SpeechWorkerEvent event) emit,
  );

  Future<void> dispose();
}

class SpeechWorkerPipeline {
  SpeechWorkerPipeline({
    required SpeechWorkerChunkProcessor processor,
    this.maxPending = 8,
    this.onCompleted,
  }) : _processor = processor;
  final int maxPending;
  Future<void> Function(SpeechWorkerEvent)? onCompleted;
  int get pendingCount => _pending.length;
  Completer<void> _capacityChanged = Completer<void>();
  Future<void>? _pumpFuture;
  Future<void>? _shutdownFuture;
  void _signalCapacity() {
    final previous = _capacityChanged;
    _capacityChanged = Completer<void>();
    if (!previous.isCompleted) previous.complete();
  }

  Future<bool> _admit(
    SpeechWorkerChunkRequest chunk, {
    required bool priority,
  }) async {
    while (_pending.length >= maxPending &&
        !_isShutdown &&
        !_isCancelled(chunk.generationId)) {
      await _capacityChanged.future;
    }
    if (_isShutdown || _isCancelled(chunk.generationId)) {
      _emit(_cancelledEventFor(chunk));
      return false;
    }
    if (priority) {
      _pending.addFirst(chunk);
    } else {
      _pending.addLast(chunk);
    }
    _emit(_queuedEventFor(chunk));
    _ensurePump();
    return true;
  }

  final SpeechWorkerChunkProcessor _processor;
  final StreamController<SpeechWorkerEvent> _eventsController =
      StreamController<SpeechWorkerEvent>.broadcast();
  final ListQueue<SpeechWorkerChunkRequest> _pending =
      ListQueue<SpeechWorkerChunkRequest>();
  final Set<String> _cancelledGenerationIds = <String>{};

  bool _isPumping = false;
  bool _isShutdown = false;
  Stream<SpeechWorkerEvent> get events => _eventsController.stream;

  Future<void> dispatch(SpeechWorkerCommand command) async {
    if (_isShutdown) {
      throw StateError('Speech worker pipeline has been shut down.');
    }

    switch (command.type) {
      case SpeechWorkerCommandType.prepareChunk:
        final chunk = command.chunks.single;
        await _admit(chunk, priority: true);
      case SpeechWorkerCommandType.preparePlan:
        for (var index = 0; index < command.chunks.length; index++) {
          if (!await _admit(command.chunks[index], priority: false)) {
            for (final remainder in command.chunks.skip(index + 1)) {
              _emit(_cancelledEventFor(remainder));
            }
            break;
          }
        }
      case SpeechWorkerCommandType.cancelGeneration:
        await _cancelGeneration(command.generationId!);
      case SpeechWorkerCommandType.shutdown:
        await shutdown();
    }
  }

  Future<void> prepareChunk(SpeechWorkerChunkRequest chunk) {
    return dispatch(SpeechWorkerCommand.prepareChunk(chunk));
  }

  Future<void> preparePlan(
    String generationId,
    List<SpeechWorkerChunkRequest> chunks,
  ) {
    return dispatch(
      SpeechWorkerCommand.preparePlan(
        generationId: generationId,
        chunks: chunks,
      ),
    );
  }

  Future<void> cancelGeneration(String generationId) {
    return dispatch(SpeechWorkerCommand.cancelGeneration(generationId));
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();
  Future<void> _shutdown() async {
    if (_isShutdown) {
      return;
    }

    _isShutdown = true;
    _signalCapacity();
    final pending = _pending.toList(growable: false);
    _pending.clear();
    for (final chunk in pending) {
      _emit(_cancelledEventFor(chunk));
    }

    await _pumpFuture;
    await _processor.dispose();
    await _eventsController.close();
  }

  Future<void> _cancelGeneration(String generationId) async {
    _cancelledGenerationIds.add(generationId);
    final cancelled = <SpeechWorkerChunkRequest>[];

    for (final chunk in _pending) {
      if (chunk.generationId == generationId) {
        cancelled.add(chunk);
      }
    }
    _pending.removeWhere((chunk) => chunk.generationId == generationId);
    _signalCapacity();

    for (final chunk in cancelled) {
      _emit(_cancelledEventFor(chunk));
    }
  }

  void _ensurePump() {
    if (_isPumping || _isShutdown) {
      return;
    }
    _pumpFuture = _pump();
  }

  Future<void> _pump() async {
    if (_isPumping || _isShutdown) {
      return;
    }

    _isPumping = true;
    try {
      while (!_isShutdown && _pending.isNotEmpty) {
        final chunk = _pending.removeFirst();
        _signalCapacity();
        if (_isCancelled(chunk.generationId)) {
          _emit(_cancelledEventFor(chunk));
          continue;
        }

        Future<void>? completion;
        try {
          await _processor.process(chunk, (event) {
            if (_isShutdown || _isCancelled(event.generationId)) {
              return;
            }
            if (event.type == SpeechWorkerEventType.completed && onCompleted != null) {
              completion = Future.sync(() => onCompleted!(event));
            } else {
              _emit(event);
            }
          });
          await completion;
          if (_isCancelled(chunk.generationId)) {
            _emit(_cancelledEventFor(chunk));
          }
        } catch (error) {
          if (_isCancelled(chunk.generationId)) {
            _emit(_cancelledEventFor(chunk));
          } else {
            _emit(
              SpeechWorkerEvent(
                type: SpeechWorkerEventType.failed,
                sessionId: chunk.sessionId,
                generationId: chunk.generationId,
                chunkId: chunk.chunkId,
                emittedAt: DateTime.now().toUtc(),
                stage: 'failed',
                message: '$error',
              ),
            );
          }
        }
      }
    } finally {
      _isPumping = false;
      if (!_isShutdown && _pending.isNotEmpty) {
        _ensurePump();
      }
    }
  }

  bool _isCancelled(String generationId) {
    return _cancelledGenerationIds.contains(generationId);
  }

  SpeechWorkerEvent _queuedEventFor(SpeechWorkerChunkRequest chunk) {
    return SpeechWorkerEvent(
      type: SpeechWorkerEventType.queued,
      sessionId: chunk.sessionId,
      generationId: chunk.generationId,
      chunkId: chunk.chunkId,
      emittedAt: DateTime.now().toUtc(),
      stage: 'queued',
    );
  }

  SpeechWorkerEvent _cancelledEventFor(SpeechWorkerChunkRequest chunk) {
    return SpeechWorkerEvent(
      type: SpeechWorkerEventType.cancelled,
      sessionId: chunk.sessionId,
      generationId: chunk.generationId,
      chunkId: chunk.chunkId,
      emittedAt: DateTime.now().toUtc(),
      stage: 'cancelled',
    );
  }

  void _emit(SpeechWorkerEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }
}
