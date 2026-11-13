import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/app_launch_options.dart';
import 'package:read_aloud/src/services/headless_reader_session.dart';

class _Controller extends ReaderController {
  _Controller({this.fail = false}) : super(enablePlatformIntakeChannels: false);
  final bool fail;
  final calls = <String>[];
  @override
  List<VoiceProfile> get voices => const [
    VoiceProfile(id: 'test', label: 'Test', locale: 'en', rawValue: {}),
  ];
  @override
  Future<void> initialize() async {
    calls.add('initialize');
    if (fail) throw StateError('initialization failed');
  }

  @override
  Future<void> selectVoiceById(String? id) async => calls.add('voice:$id');
  @override
  Future<void> setVoiceSpeed(double speed) async => calls.add('speed:$speed');
  @override
  void dispose() {
    calls.add('dispose');
    super.dispose();
  }
}

void main() {
  test(
    'explicit voice and bounded rate precede workload; cleanup is idempotent',
    () async {
      final controller = _Controller();
      final session = HeadlessReaderSession(controller: controller);
      try {
        expect(
          await session.initialize(
            const AppLaunchOptions(voiceId: 'test', speed: 2),
          ),
          isTrue,
        );
        expect(controller.calls, ['initialize', 'voice:test', 'speed:1.4']);
      } finally {
        session.close();
      }
      session.close();
      expect(controller.calls.where((call) => call == 'dispose').length, 1);
      await expectLater(
        session.initialize(const AppLaunchOptions()),
        throwsStateError,
      );
    },
  );
  test(
    'missing voice fails without fallback or rate change and still closes',
    () async {
      final controller = _Controller();
      final session = HeadlessReaderSession(controller: controller);
      try {
        expect(
          await session.initialize(
            const AppLaunchOptions(voiceId: 'missing', speed: 1.2),
          ),
          isFalse,
        );
      } finally {
        session.close();
      }
      expect(controller.calls, ['initialize', 'dispose']);
    },
  );
  test('initialization failure keeps cleanup ownership', () async {
    final controller = _Controller(fail: true);
    final session = HeadlessReaderSession(controller: controller);
    try {
      await expectLater(
        session.initialize(const AppLaunchOptions()),
        throwsStateError,
      );
    } finally {
      session.close();
    }
    expect(controller.calls, ['initialize', 'dispose']);
  });
}
