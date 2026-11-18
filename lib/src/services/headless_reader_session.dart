import '../controllers/reader_controller.dart';
import 'app_launch_options.dart';
import 'document_import_service.dart';

/// One controller/importer lifetime per headless command. The caller must use
/// try/finally and close this session, including initialization/option failures.
/// Production controller workers retain their admission, revisions and shutdown.
class HeadlessReaderSession {
  HeadlessReaderSession({ReaderController? controller}) {
    this.controller =
        controller ??
        ReaderController(
          importer: importer,
          enablePlatformIntakeChannels: false,
        );
  }

  final importer = DocumentImportService();
  late final ReaderController controller;
  bool _closed = false;

  /// False means the requested voice is unavailable; no replacement is chosen.
  Future<bool> initialize(AppLaunchOptions options) async {
    if (_closed) throw StateError('Headless session is closed');
    await controller.initialize();
    final voiceId = options.voiceId;
    if (voiceId != null) {
      if (!controller.voices.any((voice) => voice.id == voiceId)) return false;
      await controller.selectVoiceById(voiceId);
    }
    if (options.speed != null) {
      await controller.setVoiceSpeed(options.speed!.clamp(0.7, 1.4).toDouble());
    }
    return true;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    controller.dispose();
  }
}
