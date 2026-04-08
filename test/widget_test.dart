import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/reader_appearance_mode.dart';
import 'package:read_aloud/src/models/reader_resume_state.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/screens/read_aloud_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/theme/read_aloud_theme.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const menuChannel = MethodChannel('flutter/menu');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      menuChannel,
      (_) async => null,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(menuChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('renders the reader shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ReadAloudApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Read Aloud'), findsWidgets);
    expect(find.text('Reader Controls'), findsNothing);
    expect(find.text('For Probe'), findsNothing);
    expect(
      tester
          .widgetList<Title>(find.byType(Title))
          .any((widget) => widget.title == 'Read Aloud - For Probe'),
      isTrue,
    );
    expect(
      find.textContaining('Rich document surface with room for images'),
      findsNothing,
    );
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byKey(const Key('reader-overflow-menu')), findsOneWidget);
    expect(find.byKey(const Key('transport-capsule')), findsOneWidget);
    expect(find.byKey(const Key('transport-back')), findsOneWidget);
    expect(find.byKey(const Key('transport-center')), findsOneWidget);
    expect(find.byKey(const Key('transport-forward')), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.byKey(const Key('character-voices-entry')), findsOneWidget);
    expect(find.text('Character Voices'), findsOneWidget);
    expect(find.textContaining('Narrator:'), findsNothing);
    expect(find.textContaining('words'), findsNothing);
    expect(find.byType(SelectionArea), findsWidgets);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme
          ?.textTheme
          .bodyMedium
          ?.fontFamily,
      kUiFontFamily,
    );
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
    expect(find.byKey(const Key('reader-overflow-menu')), findsOneWidget);
    expect(find.byKey(const Key('transport-capsule')), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('For Probe'), findsNothing);
    expect(find.byKey(const Key('character-voices-entry')), findsOneWidget);
    expect(find.textContaining('words'), findsNothing);
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

    await tester.pumpWidget(ReadAloudApp(controller: controller));
    await tester.pump();

    await tester.tap(find.byKey(const Key('character-voices-entry')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Voice Management'), findsOneWidget);
  });

  testWidgets(
    'defaults to system appearance and keeps appearance settings off the primary surface',
    (WidgetTester tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(
        () => tester.platformDispatcher.clearPlatformBrightnessTestValue(),
      );

      await tester.pumpWidget(const ReadAloudApp());
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
      expect(find.text('Appearance'), findsNothing);

      await tester.tap(find.byKey(const Key('reader-overflow-menu')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Live Feed'), findsOneWidget);
      expect(find.text('Reader Options'), findsOneWidget);
      expect(find.text('Studio'), findsNothing);
    },
  );

  testWidgets('reader options expose a multi-voice toggle', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ReadAloudApp(controller: controller));
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader Options'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('multi-voice-toggle')), findsOneWidget);
    expect(find.text('Multi-Voice Reading'), findsOneWidget);
    expect(find.text('Narrator Voice'), findsOneWidget);
    expect(find.text('Set Character Voices'), findsOneWidget);
  });

  testWidgets('mobile overflow menu groups commands by domain', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeExportCapableTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ReadAloudApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('reader-overflow-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Document'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Live Input'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Workspace'), findsNothing);
    expect(find.byType(PopupMenuDivider), findsAtLeastNWidgets(3));
  });

  testWidgets('reader options are grouped into named sections', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ReadAloudApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('reader-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader Options'));
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
          of: find.byKey(const Key('reader-options-sheet')),
          matching: find.byType(Scrollable),
        )
        .first;

    expect(find.text('Voices and Reading'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sleep and Timing'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('Sleep and Timing'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Diagnostics'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('Diagnostics'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Document Source'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('Document Source'), findsOneWidget);
  });

  testWidgets('status toast uses a floating themed feedback surface', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ReadAloudApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));
    final shellTopBefore = tester.getTopLeft(
      find.byKey(const Key('reader-surface-shell')),
    );

    controller.showStatusMessage('Temporary message');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('status-toast')), findsOneWidget);
    expect(find.text('Temporary message'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('reader-surface-shell'))),
      shellTopBefore,
    );
  });

  testWidgets('save-audio startup failures surface through the toast layer', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeExportCapableTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ReadAloudApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('reader-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Audio'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('status-toast')), findsOneWidget);
    expect(
      find.text(
        'Could not open Save Audio right now. Try choosing the destination again.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('status toast stays visible while the voice dialog is open', (
    WidgetTester tester,
  ) async {
    final controller = ReaderController(
      preferencesService: _MemoryReaderPreferencesService(),
      ttsEngine: _FakeTtsEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ReadAloudApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('character-voices-entry')));
    await tester.pumpAndSettle();

    controller.showStatusMessage('Temporary message');
    await tester.pump();

    expect(find.text('Voice Management'), findsOneWidget);
    expect(find.byKey(const Key('status-toast')), findsOneWidget);
    expect(find.text('Temporary message'), findsOneWidget);
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

    expect(decoration.color, ReadAloudThemeTokens.dark.readerSurface);
  });

  testWidgets('reader options no longer surface live input controls', (
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

    await tester.tap(find.byKey(const Key('reader-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader Options'));
    await tester.pumpAndSettle();

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

  testWidgets(
    'desktop shell hides the overflow menu and registers native menus',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

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

      expect(find.byKey(const Key('reader-overflow-menu')), findsNothing);
      expect(find.byType(PlatformMenuBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);

      final menuBar = tester.widget<PlatformMenuBar>(
        find.byType(PlatformMenuBar),
      );
      final labels = _collectMenuLabels(menuBar.menus).toList(growable: false);

      expect(labels, contains('Read Aloud'));
      expect(labels, contains('File'));
      expect(labels, contains('Open Document...'));
      expect(labels, contains('Paste Text...'));
      expect(labels, contains('Load Sample'));
      expect(labels, contains('Save Audio...'));
      expect(labels, contains('Reader Options...'));

      debugDefaultTargetPlatformOverride = null;
    },
  );
}

Iterable<String> _collectMenuLabels(Iterable<PlatformMenuItem> items) sync* {
  for (final item in items) {
    if (item is PlatformMenu) {
      if (item.label.isNotEmpty) {
        yield item.label;
      }
      yield* _collectMenuLabels(item.menus);
      continue;
    }
    if (item is PlatformMenuItemGroup) {
      yield* _collectMenuLabels(item.members);
      continue;
    }
    if (item.label.isNotEmpty) {
      yield item.label;
    }
  }
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
    storedDocumentCastVoiceAssignments: <String, Map<String, String>>{},
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
    required Map<String, Map<String, String>> storedDocumentCastVoiceAssignments,
    ReaderResumeState? resumeState,
    String? selectedVoiceId,
    String? lastOpenedDocumentPath,
    String? lastOpenedDocumentAccessToken,
    String? lastOpenedDirectoryPath,
    String? lastOpenedDirectoryAccessToken,
  }) async {
    _preferences = ReaderPreferences(
      selectedVoiceId: selectedVoiceId,
      voiceSpeeds: Map<String, double>.from(voiceSpeeds),
      fontFamily: fontFamily,
      fontScale: fontScale,
      appearanceMode: appearanceMode,
      multiVoiceEnabled: multiVoiceEnabled,
      storedDocumentCastVoiceAssignments: Map<String, Map<String, String>>.from(
        storedDocumentCastVoiceAssignments.map(
          (key, value) => MapEntry(key, Map<String, String>.from(value)),
        ),
      ),
      resumeState: resumeState,
      lastOpenedDocumentPath: lastOpenedDocumentPath,
      lastOpenedDocumentAccessToken: lastOpenedDocumentAccessToken,
      lastOpenedDirectoryPath: lastOpenedDirectoryPath,
      lastOpenedDirectoryAccessToken: lastOpenedDirectoryAccessToken,
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

class _FakeExportCapableTtsEngine extends _FakeTtsEngine
    implements AudioExportCapable {
  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    return TtsExportResult(
      outputPath: request.outputPath,
      sidecarPath: '${request.outputPath}.json',
      duration: const Duration(seconds: 1),
      chunkCount: 1,
      voiceId: 'af_bella',
      rate: 1.0,
      engineId: 'fake',
      engineVersion: 'test',
    );
  }
}
