import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/reader_appearance_mode.dart';
import 'package:read_aloud/src/models/reader_resume_state.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/screens/read_aloud_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders the reader shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Read Aloud'), findsWidgets);
    expect(find.text('Reader Controls'), findsNothing);
    expect(find.text('For Probe'), findsNothing);
    expect(
      tester.widgetList<Title>(find.byType(Title)).any(
        (widget) => widget.title == 'Read Aloud - For Probe',
      ),
      isTrue,
    );
    expect(
      find.textContaining('Rich document surface with room for images'),
      findsNothing,
    );
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.byKey(const Key('character-voices-entry')), findsOneWidget);
    expect(find.text('Character Voices'), findsOneWidget);
    expect(find.byType(SelectionArea), findsWidgets);
  });

  testWidgets('does not overflow on short desktop-sized windows', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('For Probe'), findsNothing);
    expect(find.byKey(const Key('character-voices-entry')), findsOneWidget);
  });

  testWidgets('opens voice management from the integrated voice affordance', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ReadAloudScreen(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('character-voices-entry')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Voice Management'), findsOneWidget);
  });

  testWidgets('defaults to system appearance and keeps appearance settings off the primary surface', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => tester.platformDispatcher.clearPlatformBrightnessTestValue());

    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.dark);
    expect(find.text('Appearance'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Live Feed'), findsOneWidget);
    expect(find.text('Reader Options'), findsOneWidget);
  });

  testWidgets('reader options expose a multi-voice toggle', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ReadAloudScreen(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader Options'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('multi-voice-toggle')), findsOneWidget);
    expect(find.text('Multi-Voice Reading'), findsOneWidget);
    expect(find.text('Narrator Voice'), findsOneWidget);
    expect(find.text('Set Character Voices'), findsOneWidget);
  });

  testWidgets('status banner uses a readable themed feedback surface', (
    WidgetTester tester,
  ) async {
    final engine = _FakeTtsEngine();
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: engine,
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ReadAloudScreen(controller: controller)),
    );
    await tester.pump();

    engine.emitError('Temporary message');
    await tester.pump();

    final banner = tester.widget<Material>(find.byKey(const Key('status-banner')));
    expect(banner.color, Theme.of(tester.element(find.byType(Scaffold))).colorScheme.secondaryContainer);
  });

  testWidgets('dark appearance uses a dark reader surface shell', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(
      () => tester.platformDispatcher.clearPlatformBrightnessTestValue(),
    );

    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    final shell = tester.widget<DecoratedBox>(
      find.byKey(const Key('reader-surface-shell')),
    );
    final decoration = shell.decoration as BoxDecoration;

    expect(decoration.color, const Color(0xFF171B22));
  });

  testWidgets('reader options no longer surface live input controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Reader Options').last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Live Read'), findsNothing);
    expect(find.text('Choose Live File'), findsNothing);
    expect(find.text('Stop Live Mode'), findsNothing);
  });

  testWidgets('explicit appearance overrides change the shell theme', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_TestAppearanceShell(controller: controller));
    await tester.pump();

    await controller.setAppearanceMode(ReaderAppearanceMode.light);
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    await controller.setAppearanceMode(ReaderAppearanceMode.dark);
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

}

class _TestAppearanceShell extends StatelessWidget {
  const _TestAppearanceShell({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: controller.appearanceMode.themeMode,
          home: const Scaffold(body: Text('Appearance Shell')),
        );
      },
    );
  }
}

class _MemoryReaderPreferencesService extends ReaderPreferencesService {
  ReaderPreferences _preferences = const ReaderPreferences(
    fontFamily: ReaderPreferences.defaultFontFamily,
    fontScale: ReaderPreferences.defaultFontScale,
    appearanceMode: ReaderAppearanceMode.system,
    multiVoiceEnabled: ReaderPreferences.defaultMultiVoiceEnabled,
    voiceSpeeds: <String, double>{},
  );

  @override
  Future<ReaderPreferences> load() async => _preferences;

  @override
  Future<void> save({
    required String fontFamily,
    required double fontScale,
    required ReaderAppearanceMode appearanceMode,
    required bool multiVoiceEnabled,
    required Map<String, double> voiceSpeeds,
    ReaderResumeState? resumeState,
    String? selectedVoiceId,
    String? lastOpenedDocumentPath,
    String? lastOpenedDirectoryPath,
  }) async {
    _preferences = ReaderPreferences(
      selectedVoiceId: selectedVoiceId,
      voiceSpeeds: Map<String, double>.from(voiceSpeeds),
      fontFamily: fontFamily,
      fontScale: fontScale,
      appearanceMode: appearanceMode,
      multiVoiceEnabled: multiVoiceEnabled,
      resumeState: resumeState,
      lastOpenedDocumentPath: lastOpenedDocumentPath,
      lastOpenedDirectoryPath: lastOpenedDirectoryPath,
    );
  }
}

class _FakeTtsEngine implements TtsEngine {
  void Function(String message)? _onError;

  @override
  set onActivity(void Function(TtsPlaybackActivity activity)? callback) {}

  @override
  set onComplete(void Function()? callback) {}

  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) {}

  @override
  set onError(void Function(String message)? callback) => _onError = callback;

  @override
  set onProgress(void Function(TtsProgressUpdate update)? callback) {}

  @override
  set onStart(void Function()? callback) {}

  @override
  set onStatus(void Function(String? message)? callback) {}

  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceProfile>> loadVoices() async {
    return const <VoiceProfile>[
      VoiceProfile(
        id: 'af_bella',
        label: 'Bella',
        locale: 'en-US',
        rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
      ),
    ];
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> selectVoice(VoiceProfile voice) async {}

  @override
  Future<void> setSpeechRate(double multiplier) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> speak(TtsSpeakRequest request) async {}

  @override
  Future<void> stop() async {}

  void emitError(String message) {
    _onError?.call(message);
  }
}
