import 'share_intake_service_stub.dart'
    if (dart.library.io) 'share_intake_service_io.dart';

class SharedIntake {
  const SharedIntake({
    this.text,
    this.filePaths = const <String>[],
    this.mimeType,
  });

  final String? text;
  final List<String> filePaths;
  final String? mimeType;

  bool get hasContent =>
      (text != null && text!.trim().isNotEmpty) || filePaths.isNotEmpty;
}

abstract interface class ShareIntakeService {
  Future<SharedIntake?> getInitialShare();
  Stream<SharedIntake> getMediaStream();
  Future<void> clearSharedData();
}

ShareIntakeService createShareIntakeService() => createShareIntakeServiceImpl();
