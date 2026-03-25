import '../models/voice_profile.dart';

class TtsProgressUpdate {
  const TtsProgressUpdate({
    required this.startOffset,
    required this.endOffset,
    required this.word,
  });

  final int startOffset;
  final int endOffset;
  final String word;
}

abstract interface class TtsEngine {
  Future<void> initialize();
  Future<List<VoiceProfile>> loadVoices();
  Future<void> selectVoice(VoiceProfile voice);
  Future<void> setSpeechRate(double multiplier);
  Future<void> setVolume(double volume);
  Future<void> speak(String text);
  Future<void> pause();
  Future<void> stop();
  void dispose();

  set onStart(void Function()? callback);
  set onProgress(void Function(TtsProgressUpdate update)? callback);
  set onComplete(void Function()? callback);
  set onError(void Function(String message)? callback);
}
