import '../models/native_speech_turn.dart';
import '../models/reader_operation.dart';
import 'speech_planning_supervisor.dart';
import '../models/chunk_plan.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';
import '../models/voice_profile.dart';
import '../models/prepared_voice_binding.dart';
import 'speech_audio_packet.dart';
import '../models/speech_annotation.dart';

/// Successful complete-scene publication, never an early packet acknowledgment.
class TtsRenderedSceneCompletion {
  const TtsRenderedSceneCompletion({
    required this.sceneId,
    required this.frameCount,
    required this.packetCount,
    required this.duration,
    required this.onsetTrimFrames,
  });
  final String sceneId;
  final int frameCount;
  final int packetCount;
  final Duration duration;
  final int onsetTrimFrames;
}

class TtsPlayableAudioPacket {
  TtsPlayableAudioPacket({
    required this.packet,
    required this.sceneId,
    required this.text,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.startOffset,
    required List<NativeSpeechTurn> sceneTurns,
    required this.sceneCompletion,
    this.boundaryClass = BreakClass.none,
    this.isInitialScene = true,
    this.previousTrailingSilence,
  }) : sceneTurns = List.unmodifiable(
         sceneTurns.map((turn) => NativeSpeechTurn.fromMap(turn.toMap())),
       );
  final SpeechAudioPacket packet;
  final String sceneId;
  final String text;
  final int startWordIndex;
  final int endWordIndex;
  final int startOffset;
  final List<NativeSpeechTurn> sceneTurns;
  final Future<TtsRenderedSceneCompletion> sceneCompletion;
  final BreakClass boundaryClass;
  final bool isInitialScene;
  final Duration? previousTrailingSilence;
}

class TtsPlaybackResumeAnchor {
  const TtsPlaybackResumeAnchor({
    required this.documentId,
    required this.chunkId,
    required this.startWordIndex,
  });
  final String documentId;
  final String chunkId;
  final int startWordIndex;
}

class TtsPlaybackAcknowledgment {
  const TtsPlaybackAcknowledgment({
    required this.documentId,
    required this.assignmentRevision,
    required this.generationId,
    required this.bindingFingerprints,
  });
  final String documentId;
  final int assignmentRevision;
  final String generationId;
  final Set<String> bindingFingerprints;
}

abstract interface class VoiceAssignmentPlaybackCapable {
  TtsPlaybackResumeAnchor? get currentPlaybackResumeAnchor;
}

/// Player-only admission of an already validated, local rendered scene. The
/// package owner validates hashes/format/dependencies and retains the file until
/// admission; the player pins admitted files until native playback releases them.
abstract interface class RenderedAudioPlaybackCapable {
  Future<void> playRendered(TtsRenderedAudioRequest request);
}

class RenderedAudioPlaybackAcknowledgment {
  const RenderedAudioPlaybackAcknowledgment({
    required this.documentId,
    required this.manifestIdentity,
    required this.intentRevision,
    required this.generationId,
  });
  final String documentId;
  final String manifestIdentity;
  final int intentRevision;
  final String generationId;
}

/// A single pull consumer; null means verified source EOF, never an audio gap.
class TtsRenderedAudioContinuation {
  const TtsRenderedAudioContinuation({required this.next});
  final Future<TtsRenderedAudioRequest?> Function(
    int previousSequence,
    Future<void> cancelled,
  )
  next;
}

class TtsRenderedAudioFormat {
  const TtsRenderedAudioFormat({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
}

class TtsRenderedAudioRequest {
  TtsRenderedAudioRequest({
    required this.documentId,
    required this.manifestIdentity,
    required this.intentRevision,
    required this.sceneId,
    required this.text,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.sourceEndWordIndex,
    required this.startOffset,
    required List<NativeSpeechTurn> sceneTurns,
    required this.audioPath,
    required this.format,
    required this.duration,
    this.rangeSequence = 0,
    this.isCurrent,
    this.onPlaybackReady,
    this.onRangeActive,
    this.continuation,
    this.audioPacket,
    this.sceneCompletion,
    this.boundaryClass = BreakClass.none,
    this.isInitialScene = true,
    this.previousTrailingSilence,
  }) : sceneTurns = List.unmodifiable(
         sceneTurns.map((turn) => NativeSpeechTurn.fromMap(turn.toMap())),
       );
  final String documentId;
  final String manifestIdentity;
  final int intentRevision;
  final String sceneId;
  final String text;
  final int startWordIndex;
  final int endWordIndex;
  final int sourceEndWordIndex;
  final int startOffset;
  final List<NativeSpeechTurn> sceneTurns;
  final String audioPath;

  /// The package owner has validated a local PCM WAV with this format.
  final TtsRenderedAudioFormat format;
  final Duration duration;
  final int rangeSequence;
  final bool Function()? isCurrent;
  final void Function(RenderedAudioPlaybackAcknowledgment)? onPlaybackReady;
  final void Function()? onRangeActive;
  final TtsRenderedAudioContinuation? continuation;
  final SpeechAudioPacket? audioPacket;
  final Future<TtsRenderedSceneCompletion>? sceneCompletion;
  final BreakClass boundaryClass;
  final bool isInitialScene;
  final Duration? previousTrailingSilence;
}

/// Finalized synthesis output, with captured dependency evidence. Raw artifact
/// provenance is optional: a corrected derivative must never masquerade as raw.
class TtsFinalizedAudioScene {
  TtsFinalizedAudioScene({
    required this.documentId,
    required this.generationId,
    required this.sceneId,
    required this.text,
    required this.engineSpeakText,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.startOffset,
    required List<NativeSpeechTurn> sceneTurns,
    required List<PreparedVoiceBinding> preparedBindings,
    required this.audioPath,
    required this.duration,
    required this.engineId,
    required this.engineVersion,
    required this.normalizationVersion,
    required this.capabilityProfileId,
    required this.synthesisIdentity,
    required this.translationSignature,
    required this.synthesisRate,
    required this.assignmentRevision,
    required this.cancelled,
    required this.isCurrent,
    this.rawAudioPath,
    this.rawArtifactIdentity,
    this.predecessorRawArtifactIdentity,
    this.boundaryPolicyVersion,
    this.boundaryClass,
    this.trailingSilenceMicros,
  }) : sceneTurns = List.unmodifiable(
         sceneTurns.map((turn) => NativeSpeechTurn.fromMap(turn.toMap())),
       ),
       preparedBindings = List.unmodifiable(preparedBindings);
  final String documentId;
  final String generationId;
  final String sceneId;
  final String text;
  final String engineSpeakText;
  final int startWordIndex;
  final int endWordIndex;
  final int startOffset;
  final List<NativeSpeechTurn> sceneTurns;
  final List<PreparedVoiceBinding> preparedBindings;
  final String audioPath;
  final Duration duration;
  final String engineId;
  final String engineVersion;
  final String normalizationVersion;
  final String capabilityProfileId;
  final String synthesisIdentity;
  final String translationSignature;
  final double synthesisRate;
  final int assignmentRevision;
  final Future<void> cancelled;
  final bool Function() isCurrent;
  final String? rawAudioPath;
  final String? rawArtifactIdentity;
  final String? predecessorRawArtifactIdentity;
  final String? boundaryPolicyVersion;
  final String? boundaryClass;
  final int? trailingSilenceMicros;
}

abstract interface class ResourcePreparationCapable {
  bool get resourcesReady;
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  });
  Future<void> releaseDocumentResources();
  Future<void> shutdownResources();
}

/// Download/load the selected model independently of document resource bindings.
abstract interface class ModelPreparationCapable {
  Future<void> prepareSelectedModel();
}

class TtsResourceProgress {
  const TtsResourceProgress({
    required this.stage,
    required this.message,
    this.completed,
    this.total,
    this.unit = 'bytes',
    this.operationId,
    this.ownerEpoch = 0,
    this.state = OperationState.running,
    this.updatedAt,
    this.error,
    this.retryOf,
  });

  final String stage;
  final String message;
  final int? completed;
  final int? total;
  final String unit;
  final String? operationId;
  final int ownerEpoch;
  final OperationState state;
  final DateTime? updatedAt;
  final String? error;
  final String? retryOf;

  double? get fraction =>
      completed == null ||
          total == null ||
          total! <= 0 ||
          (completed ?? 0) < 0 ||
          (completed ?? 0) > total!
      ? null
      : (completed ?? 0) / total!;

  ReaderOperation toOperation({int? epoch}) => ReaderOperation(
    operationId: operationId ?? 'legacy-resource:${epoch ?? ownerEpoch}',
    ownerKind: OperationOwnerKind.model,
    ownerEpoch: epoch ?? ownerEpoch,
    attempt: ownerEpoch,
    // Loading stages are phases of one owned acquisition, not separate tasks.
    stage: 'resources',
    scope: 'model',
    state: state,
    completedUnits: completed ?? 0,
    completedKnown: completed != null,
    totalUnits: total,
    unit: unit,
    updatedAt: updatedAt ?? DateTime.now(),
    message: message,
    error: error,
    retryOf: retryOf,
    recoveryActions: state == OperationState.failed
        ? [OperationRecoveryAction.retry]
        : state.isTerminal
        ? const []
        : [OperationRecoveryAction.cancel],
  );
}

abstract interface class TtsResourceProgressCapable {
  set onResourceProgress(void Function(TtsResourceProgress?)? callback);
}

class TtsProgressUpdate {
  const TtsProgressUpdate({
    this.sceneTurns = const <NativeSpeechTurn>[],
    required this.startOffset,
    required this.endOffset,
    required this.word,
    this.documentId,
    this.chunkId,
    this.segmentId,
    this.wordStartIndex,
    this.wordEndIndex,
    this.elapsedInChunk,
    this.chunkAudioDuration,
    this.voiceId,
    this.rate,
    this.routeId,
    this.castId,
    this.dialogueSpanId,
  });

  final List<NativeSpeechTurn> sceneTurns;
  final int startOffset;
  final int endOffset;
  final String word;
  final String? documentId;
  final String? chunkId;
  final String? segmentId;
  final int? wordStartIndex;
  final int? wordEndIndex;
  final Duration? elapsedInChunk;
  final Duration? chunkAudioDuration;
  final String? voiceId;
  final double? rate;
  final String? routeId;
  final String? castId;
  final String? dialogueSpanId;
}

enum TtsPlaybackPhase { idle, buffering, playing }

enum TtsBufferPressure { none, healthy, lowWater, critical }

class TtsPlaybackActivity {
  const TtsPlaybackActivity({
    required this.phase,
    this.bufferedChunkCount = 0,
    this.totalChunkCount = 0,
    this.bufferPressure = TtsBufferPressure.none,
    this.bufferedLeadTime = Duration.zero,
    this.message,
  });

  const TtsPlaybackActivity.idle()
    : phase = TtsPlaybackPhase.idle,
      bufferedChunkCount = 0,
      totalChunkCount = 0,
      bufferPressure = TtsBufferPressure.none,
      bufferedLeadTime = Duration.zero,
      message = null;

  final TtsPlaybackPhase phase;
  final int bufferedChunkCount;
  final int totalChunkCount;
  final TtsBufferPressure bufferPressure;
  final Duration bufferedLeadTime;
  final String? message;

  bool get isBuffering => phase == TtsPlaybackPhase.buffering;
  bool get isPlaying => phase == TtsPlaybackPhase.playing;
  bool get isAudioUnderPressure =>
      bufferPressure == TtsBufferPressure.lowWater ||
      bufferPressure == TtsBufferPressure.critical;
  bool get isAudioInCriticalPressure =>
      bufferPressure == TtsBufferPressure.critical;
}

class TtsDebugTraceSnapshot {
  const TtsDebugTraceSnapshot({
    required this.logPath,
    required this.startedAt,
    required this.voiceId,
    required this.recentLines,
    this.sessionId,
  });

  final String logPath;
  final DateTime startedAt;
  final String voiceId;
  final List<String> recentLines;
  final String? sessionId;
}

class VoiceLibraryEntry {
  const VoiceLibraryEntry({
    required this.voice,
    required this.isBundled,
    required this.isInstalled,
    this.isDownloading = false,
    this.progress,
    this.statusMessage,
  });

  final VoiceProfile voice;
  final bool isBundled;
  final bool isInstalled;
  final bool isDownloading;
  final double? progress;
  final String? statusMessage;
}

/// Pull-only continuation of one source session. The consumer owns cancellation;
/// the producer returns null only at verified EOF. A single consumer calls this
/// once per sequence, after admitting the previous range's plan.
class TtsRangeContinuation {
  const TtsRangeContinuation({required this.next});
  final Future<TtsSpeakRequest?> Function(
    int previousSequence,
    Future<void> cancelled,
  )
  next;
}

class TtsSpeakRequest {
  const TtsSpeakRequest({
    required this.text,
    this.documentId,
    this.sessionId,
    this.normalizationVersion,
    this.chunkPlan,
    this.isResumedPlayback = false,
    this.speechDocument,
    this.ttsArtifactSet,
    this.preparedResources,
    this.planningContext,
    this.assignmentRevision = 0,
    this.isCurrent,
    this.onPlaybackReady,
    this.rangeSequence = 0,
    this.sourceWordOffset = 0,
    this.continuation,
    this.onRangeActive,
    this.onRenderedScene,
  });

  final String text;
  final String? documentId;
  final String? sessionId;
  final String? normalizationVersion;
  final ChunkPlan? chunkPlan;
  final bool isResumedPlayback;
  final SpeechDocument? speechDocument;
  final TtsArtifactSet? ttsArtifactSet;
  final List<PreparedVoiceBinding>? preparedResources;
  final SpeechPlanningContext? planningContext;
  final int assignmentRevision;
  final bool Function()? isCurrent;
  final void Function(TtsPlaybackAcknowledgment)? onPlaybackReady;
  final int rangeSequence;
  final int sourceWordOffset;
  final TtsRangeContinuation? continuation;

  /// Invoked on actual player progress, never on lookahead preparation.
  final void Function()? onRangeActive;

  /// Bounded durable publication, awaited while its own artifact pin is held.
  /// The callback must honor request cancellation/current ownership itself.
  final Future<void> Function(TtsFinalizedAudioScene)? onRenderedScene;
}

class TtsExportRequest {
  const TtsExportRequest({
    required this.text,
    required this.outputPath,
    this.documentId,
    this.documentTitle,
    this.sourceDescription,
    this.sessionId,
    this.normalizationVersion,
    this.chunkPlan,
    this.speechDocument,
    this.ttsArtifactSet,
    this.planningContext,
    this.preparedResources,
    this.onRenderedScene,
    this.isCurrent,
    this.cancelled,
    this.sourceWordOffset = 0,
    this.assignmentRevision = 0,
    this.onPlayablePacket,
    this.predecessorRawArtifactIdentity,
    this.predecessorTrailingSilence,
  });

  final String text;
  final String outputPath;
  final String? documentId;
  final String? documentTitle;
  final String? sourceDescription;
  final String? sessionId;
  final String? normalizationVersion;
  final ChunkPlan? chunkPlan;
  final SpeechDocument? speechDocument;
  final TtsArtifactSet? ttsArtifactSet;
  final SpeechPlanningContext? planningContext;
  final List<PreparedVoiceBinding>? preparedResources;

  /// Awaited while raw and finalized artifact pins remain held. Publication
  /// must honor the supplied scene cancellation and current-owner predicate.
  final Future<void> Function(TtsFinalizedAudioScene)? onRenderedScene;
  final bool Function()? isCurrent;
  final Future<void>? cancelled;
  final int sourceWordOffset;
  final int assignmentRevision;

  /// Ordered handoff only; must not wait for native playback credit.
  final Future<void> Function(TtsPlayableAudioPacket)? onPlayablePacket;
  final String? predecessorRawArtifactIdentity;
  final Duration? predecessorTrailingSilence;
}

class TtsExportResult {
  const TtsExportResult({
    required this.outputPath,
    required this.sidecarPath,
    required this.duration,
    required this.chunkCount,
    required this.voiceId,
    required this.rate,
    required this.engineId,
    required this.engineVersion,
  });

  final String outputPath;
  final String sidecarPath;
  final Duration duration;
  final int chunkCount;
  final String voiceId;
  final double rate;
  final String engineId;
  final String engineVersion;
}

abstract interface class VoiceLibraryCapable {
  List<VoiceLibraryEntry> get voiceLibrary;
  Future<void> installVoice(String voiceId);

  set onVoiceLibraryChanged(void Function()? callback);
}

abstract interface class AudioExportCapable {
  Future<TtsExportResult> exportAudio(TtsExportRequest request);
}

/// Engines with a narrower supported range normalize intent before planning.
/// The resulting effective rate must identify both cache content and inference.
abstract interface class SpeechRateNormalizationCapable {
  double normalizeSpeechRate(double requested);
}

abstract interface class TtsEngineIdentityCapable {
  String get engineId;
  String get engineVersion;
}

abstract interface class TtsEngine {
  Future<void> initialize();
  Future<List<VoiceProfile>> loadVoices();
  Future<void> selectVoice(VoiceProfile voice);
  Future<void> setSpeechRate(double multiplier);
  Future<void> setVolume(double volume);
  Future<void> speak(TtsSpeakRequest request);
  Future<void> pause();
  Future<void> stop();
  void dispose();

  set onStart(void Function()? callback);
  set onStatus(void Function(String? message)? callback);
  set onProgress(void Function(TtsProgressUpdate update)? callback);
  set onComplete(void Function()? callback);
  set onError(void Function(String message)? callback);
  set onActivity(void Function(TtsPlaybackActivity activity)? callback);
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback);
}
