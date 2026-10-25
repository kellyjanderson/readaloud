import 'dart:async';
import 'dart:isolate';

import '../models/chunk_plan.dart';
import '../models/voice_session_realization.dart';
import 'cast_aware_speech_route_service.dart';
import 'chunk_planner_service.dart';
import 'voice_session_realization_service.dart';

/// Data-only snapshot. Each worker receives an isolate-owned copy, never UI state.
class SpeechPlanningContext {
  const SpeechPlanningContext({
    required this.realization,
    required this.engineVersion,
    this.routes,
  });
  final VoiceSessionRealizationInput realization;
  final String engineVersion;
  final CastAwareSpeechRouteInput? routes;
}

class SpeechPlanningWindow {
  const SpeechPlanningWindow(this.realization, this.plan);
  final VoiceSessionRealization realization;
  final ChunkPlan plan;
}

/// Retains one isolate-owned immutable context. Callers reuse the same context
/// object for scalar refills and supply a new object when bindings change.
/// One active request and one latest pending request; cancellation/timeout kills
/// only pure Dart work and drains its exit before a replacement can start.
class SpeechPlanningSupervisor {
  SpeechPlanningSupervisor({
    this.timeout = const Duration(seconds: 30),
    this.workerEntryPoint = speechPlanningWorkerEntry,
  });
  final Duration timeout;
  final void Function(SpeechPlanningWorkerInput) workerEntryPoint;
  _PlanningJob? _active;
  _PlanningJob? _pending;
  SpeechPlanningContext? _context;
  int _epoch = 0;
  int _sequence = 0;
  int _workerStarts = 0;
  int get workerStarts => _workerStarts;
  int get activeCount => _active == null ? 0 : 1;
  int get pendingCount => _pending == null ? 0 : 1;
  bool _closed = false;
  Future<void>? _shutdown;
  Isolate? _isolate;
  Future<Isolate>? _spawning;
  ReceivePort? _port;
  StreamSubscription<dynamic>? _subscription;
  Completer<SendPort>? _ready;
  Completer<void>? _exited;
  Future<void>? _starting;
  Completer<Map<String, Object?>>? _response;

  Future<SpeechPlanningWindow> plan(
    SpeechPlanningContext context, {
    String? startSegmentId,
    int maxChunks = 3,
  }) {
    final replaced = !identical(context, _context);
    if (replaced) {
      _context = context;
      ++_epoch;
    }
    final job = _PlanningJob(
      context,
      startSegmentId,
      maxChunks,
      _epoch,
      ++_sequence,
    );
    if (_closed) {
      job.cancel();
    } else if (_active == null) {
      _launch(job);
    } else {
      _pending?.cancel();
      _pending = job;
      // Same-context refills may finish normally. A changed graph invalidates
      // both old success and old failure, and never shares its resident worker.
      if (replaced) _active!.cancel();
    }
    return job.result.future;
  }

  void cancel() {
    ++_epoch;
    _context = null;
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

  void _launch(_PlanningJob job) {
    _active = job;
    unawaited(_execute(job));
  }

  Future<void> _execute(_PlanningJob job) async {
    var stop = false;
    try {
      final response = await Future.any([
        _run(job),
        job.cancelled.future.then<Map<String, Object?>>(
          (_) => throw const PlanningCancelled(),
        ),
      ]).timeout(timeout);
      if (job.epoch != _epoch || job.cancelled.isCompleted) {
        throw const PlanningCancelled();
      }
      if (response['epoch'] != job.epoch ||
          response['sequence'] != job.sequence) {
        throw StateError('Planning worker returned stale identity.');
      }
      if (response['error'] != null) throw StateError('${response['error']}');
      if (!job.result.isCompleted) {
        job.result.complete(response['result']! as SpeechPlanningWindow);
      }
    } catch (error, stack) {
      stop = true;
      if (!job.result.isCompleted) job.result.completeError(error, stack);
    } finally {
      if (stop || job.cancelled.isCompleted) await _stopWorker();
      _response = null;
      _active = null;
      job.drained.complete();
      final next = _pending;
      _pending = null;
      if (next != null && !_closed) _launch(next);
    }
  }

  int? _residentEpoch;
  Future<Map<String, Object?>> _run(_PlanningJob job) async {
    if (_residentEpoch != job.epoch) {
      await _stopWorker();
      if (job.cancelled.isCompleted) throw const PlanningCancelled();
      _residentEpoch = job.epoch;
    }
    await (_starting ??= _startWorker(job));
    if (job.cancelled.isCompleted) throw const PlanningCancelled();
    _response = Completer<Map<String, Object?>>();
    (await _ready!.future).send({
      'epoch': job.epoch,
      'sequence': job.sequence,
      'start': job.start,
      'maximum': job.maximum,
    });
    return _response!.future;
  }

  Future<void> _startWorker(_PlanningJob job) async {
    _port = ReceivePort();
    _ready = Completer<SendPort>();
    _exited = Completer<void>();
    _subscription = _port!.listen((message) {
      if (message is SendPort) {
        if (!_ready!.isCompleted) _ready!.complete(message);
      } else if (message == null || message is List) {
        final error = StateError('Planning worker exited: $message');
        if (!_ready!.isCompleted) _ready!.completeError(error);
        if (_response != null && !_response!.isCompleted) {
          _response!.completeError(error);
        }
        if (message == null && !_exited!.isCompleted) _exited!.complete();
      } else if (_response != null && !_response!.isCompleted) {
        _response!.complete(Map<String, Object?>.from(message as Map));
      }
    });
    ++_workerStarts;
    _spawning = Isolate.spawn(
      workerEntryPoint,
      SpeechPlanningWorkerInput(job.context, job.epoch, _port!.sendPort),
      onExit: _port!.sendPort,
      onError: _port!.sendPort,
      debugName: 'speech-planning-$_workerStarts',
    );
    _isolate = await _spawning;
    await _ready!.future;
  }

  Future<void> _stopWorker() async {
    try {
      _isolate ??= await _spawning;
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    if (_isolate != null) await _exited?.future;
    await _subscription?.cancel();
    _port?.close();
    _isolate = null;
    _spawning = null;
    _port = null;
    _subscription = null;
    _ready = null;
    _exited = null;
    _starting = null;
    _residentEpoch = null;
  }
}

class _PlanningJob {
  _PlanningJob(
    this.context,
    this.start,
    this.maximum,
    this.epoch,
    this.sequence,
  );
  final SpeechPlanningContext context;
  final String? start;
  final int maximum;
  final int epoch;
  final int sequence;
  final result = Completer<SpeechPlanningWindow>();
  final cancelled = Completer<void>();
  final drained = Completer<void>();
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    if (!result.isCompleted) result.completeError(const PlanningCancelled());
  }
}

class PlanningCancelled implements Exception {
  const PlanningCancelled();
}

class SpeechPlanningWorkerInput {
  const SpeechPlanningWorkerInput(this.context, this.epoch, this.reply);
  final SpeechPlanningContext context;
  final int epoch;
  final SendPort reply;
}

void speechPlanningWorkerEntry(SpeechPlanningWorkerInput input) async {
  final context = input.context;
  final routes = context.routes == null
      ? null
      : const CastAwareSpeechRouteService().build(context.routes!);
  final graph = ChunkPlannerGraph(context.realization.speechDocument, routes);
  final commands = ReceivePort();
  input.reply.send(commands.sendPort);
  await for (final raw in commands) {
    final command = Map<String, Object?>.from(raw as Map);
    final identity = {'epoch': input.epoch, 'sequence': command['sequence']};
    try {
      if (command['epoch'] != input.epoch) {
        throw StateError('Stale planning context.');
      }
      final maximum = command['maximum']! as int;
      if (maximum <= 0) throw ArgumentError.value(maximum, 'maxChunks');
      input.reply.send({
        ...identity,
        'result': _planWindow(
          context,
          command['start'] as String?,
          maximum,
          graph,
        ),
      });
    } catch (error) {
      input.reply.send({...identity, 'error': '$error'});
    }
  }
}

SpeechPlanningWindow _planWindow(
  SpeechPlanningContext context,
  String? start,
  int maximum,
  ChunkPlannerGraph graph,
) {
  final source = context.realization;
  final input = VoiceSessionRealizationInput(
    speechDocument: source.speechDocument,
    baseAnnotations: source.baseAnnotations,
    basePronunciationArtifacts: source.basePronunciationArtifacts,
    startSegmentId: start ?? source.startSegmentId,
    voiceId: source.voiceId,
    engineId: source.engineId,
    rate: source.rate,
    narrationState: source.narrationState,
    selectedProfile: source.selectedProfile,
    mergedPronunciationResources: source.mergedPronunciationResources,
    enabledActiveRuleModules: source.enabledActiveRuleModules,
  );
  var realization = const VoiceSessionRealizationService().realize(input);

  var plan = graph.plan(
    ChunkPlannerInput(
      speechDocument: input.speechDocument,
      baseAnnotations: input.baseAnnotations,
      ttsArtifactSet: realization.ttsArtifactSet,
      startSegmentId: input.startSegmentId,
      voiceId: input.voiceId,
      rate: input.rate,
      engineId: input.engineId,
      engineVersion: context.engineVersion,
      maxChunks: maximum,
    ),
  );
  if (plan.chunks.isNotEmpty) {
    final first =
        input.speechDocument.segmentIndexById[input.startSegmentId] ?? 0;
    realization = const VoiceSessionRealizationService().realize(
      VoiceSessionRealizationInput(
        speechDocument: input.speechDocument,
        baseAnnotations: input.baseAnnotations,
        basePronunciationArtifacts: input.basePronunciationArtifacts,
        startSegmentId: input.startSegmentId,
        voiceId: input.voiceId,
        engineId: input.engineId,
        rate: input.rate,
        narrationState: input.narrationState,
        selectedProfile: input.selectedProfile,
        mergedPronunciationResources: input.mergedPronunciationResources,
        enabledActiveRuleModules: input.enabledActiveRuleModules,
        segmentLimit: plan.chunks.last.endSegmentIndex - first + 1,
      ),
    );
    plan = graph.plan(
      ChunkPlannerInput(
        speechDocument: input.speechDocument,
        baseAnnotations: input.baseAnnotations,
        ttsArtifactSet: realization.ttsArtifactSet,
        startSegmentId: input.startSegmentId,
        voiceId: input.voiceId,
        rate: input.rate,
        engineId: input.engineId,
        engineVersion: context.engineVersion,
        maxChunks: maximum,
      ),
    );
  }
  return SpeechPlanningWindow(realization, plan);
}
