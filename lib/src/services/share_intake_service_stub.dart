import 'share_intake_service.dart';

class _StubShareIntakeService implements ShareIntakeService {
  @override
  Future<SharedIntake?> getInitialShare() async => null;

  @override
  Stream<SharedIntake> getMediaStream() => const Stream<SharedIntake>.empty();

  @override
  Future<void> clearSharedData() async {}
}

ShareIntakeService createShareIntakeServiceImpl() => _StubShareIntakeService();
