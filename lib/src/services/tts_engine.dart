import '../models/chunk_plan.dart';
import '../models/speech_document.dart';
import '../models/tts_artifact.dart';
import '../models/voice_profile.dart';

class TtsProgressUpdate {
  const TtsProgressUpdate({
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
  });

  final String text;
  final String? documentId;
  final String? sessionId;
  final String? normalizationVersion;
  final ChunkPlan? chunkPlan;
  final bool isResumedPlayback;
  final SpeechDocument? speechDocument;
  final TtsArtifactSet? ttsArtifactSet;
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
