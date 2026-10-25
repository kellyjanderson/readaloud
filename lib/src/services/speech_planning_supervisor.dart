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

/// One pure-Dart planning worker per owner. Replacement kills and drains the
/// previous isolate before spawning; pending callers are latest-wins.
class SpeechPlanningSupervisor {
  SpeechPlanningSupervisor({this.timeout = const Duration(seconds: 30)});
  final Duration timeout;
  int _revision = 0;
  bool _closed = false;
  Isolate? _isolate;
  Completer<void>? _exit;
  Future<void>? _active;
  _PlanningJob? _pending;

  Future<SpeechPlanningWindow> plan(
    SpeechPlanningContext context, {
    String? startSegmentId,
    int maxChunks = 3,
  }) {
    final job = _PlanningJob(context, startSegmentId, maxChunks, ++_revision);
    if (_closed) {
      job.result.completeError(const PlanningCancelled());
    } else if (_active == null) {
      _launch(job);
    } else {
      _pending?.result.completeError(const PlanningCancelled());
      _pending = job;
      _isolate?.kill(priority: Isolate.immediate);
    }
    return job.result.future;
  }

  void _launch(_PlanningJob job) {
    _active = _execute(job)
        .then(
          (window) => job.result.complete(window),
          onError: (Object error, StackTrace stack) =>
              job.result.completeError(error, stack),
        )
        .whenComplete(() {
          _active = null;
          final next = _pending;
          _pending = null;
          if (next != null) _launch(next);
        });
  }

  Future<SpeechPlanningWindow> _execute(_PlanningJob job) async {
    final revision = job.revision;
    if (_closed || revision != _revision) throw const PlanningCancelled();
    final port = ReceivePort();
    final result = Completer<SpeechPlanningWindow>();
    final exited = Completer<void>();
    _exit = exited;
    final messages = port.listen((value) {
      if (value == null) {
        if (!exited.isCompleted) exited.complete();
        if (!result.isCompleted)
          result.completeError(const PlanningCancelled());
      } else if (value is SpeechPlanningWindow) {
        if (!result.isCompleted) result.complete(value);
      } else if (!result.isCompleted) {
        result.completeError(StateError('Planning worker: $value'));
      }
    });
    try {
      _isolate = await Isolate.spawn(
        _planWindow,
        (job.context, job.start, job.maximum, port.sendPort),
        onExit: port.sendPort,
        onError: port.sendPort,
      );
      if (_closed || revision != _revision) {
        _isolate!.kill(priority: Isolate.immediate);
      }
      final window = await result.future.timeout(timeout);
      if (_closed || revision != _revision) throw const PlanningCancelled();
      return window;
    } finally {
      _isolate?.kill(priority: Isolate.immediate);
      if (_isolate != null) await exited.future;
      _isolate = null;
      _exit = null;
      await messages.cancel();
      port.close();
    }
  }

  void cancel() {
    ++_revision;
    _pending?.result.completeError(const PlanningCancelled());
    _pending = null;
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<void> shutdown() async {
    _closed = true;
    cancel();
    await _exit?.future;
    await _active;
  }
}

class _PlanningJob {
  _PlanningJob(this.context, this.start, this.maximum, this.revision);
  final SpeechPlanningContext context;
  final String? start;
  final int maximum;
  final int revision;
  final result = Completer<SpeechPlanningWindow>();
}

class PlanningCancelled implements Exception {
  const PlanningCancelled();
}

void _planWindow((SpeechPlanningContext, String?, int, SendPort) request) {
  final (context, start, maximum, reply) = request;
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
  final routes = context.routes == null
      ? null
      : const CastAwareSpeechRouteService().build(context.routes!);
  var plan = const ChunkPlannerService().plan(
    ChunkPlannerInput(
      speechDocument: input.speechDocument,
      baseAnnotations: input.baseAnnotations,
      ttsArtifactSet: realization.ttsArtifactSet,
      startSegmentId: input.startSegmentId,
      voiceId: input.voiceId,
      rate: input.rate,
      engineId: input.engineId,
      engineVersion: context.engineVersion,
      castAwareSpeechRoutes: routes,
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
    plan = const ChunkPlannerService().plan(
      ChunkPlannerInput(
        speechDocument: input.speechDocument,
        baseAnnotations: input.baseAnnotations,
        ttsArtifactSet: realization.ttsArtifactSet,
        startSegmentId: input.startSegmentId,
        voiceId: input.voiceId,
        rate: input.rate,
        engineId: input.engineId,
        engineVersion: context.engineVersion,
        castAwareSpeechRoutes: routes,
        maxChunks: maximum,
      ),
    );
  }
  Isolate.exit(reply, SpeechPlanningWindow(realization, plan));
}
