import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/screens/read_aloud_screen.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/widgets/voice_management_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = _UiFilePicker();
  });

  testWidgets(
    'Open Document imports actual radoc bytes without source analysis',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final picker = _UiFilePicker();
      FilePicker.platform = picker;

      final source = File(
        'test/fixtures/rc2_prose/text/orchard.txt',
      ).readAsStringSync();
      final cold = ReaderController(
        ttsEngine: _UiEngine(),
        enablePlatformIntakeChannels: false,
      );
      addTearDown(cold.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ReadAloudScreen(controller: cold)),
      );
      await _pumpUntil(tester, () => !cold.isInitializing);
      await _paste(tester, source);
      await _pumpUntil(
        tester,
        () => cold.isPreparationComplete && cold.preparedRanges.isNotEmpty,
      );
      final expectedText = cold.document.speakableText;
      final expectedCast = cold.document.characterCastRegistry.entries
          .map((entry) => entry.castId)
          .toSet();
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await _pumpUi(tester);
      final narratorCard = find.byKey(
        const Key('voice-assignment-card-Narrator'),
      );
      final narratorDropdown = find.descendant(
        of: narratorCard,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.ensureVisible(narratorDropdown);
      await _pumpUi(tester);
      final initialNarrator = cold.castVoiceAssignments!
          .forCastId('cast_narrator')!
          .effectiveVoiceId;
      final chosenNarrator = initialNarrator == 'af_bella'
          ? 'am_michael'
          : 'af_bella';
      await tester.tap(narratorDropdown);
      await _pumpUi(tester);
      await tester.tap(
        find
            .text(
              chosenNarrator == 'af_bella'
                  ? 'Bella (en-US)'
                  : 'Michael (en-US)',
            )
            .last,
      );
      await _pumpUi(tester);
      await tester.tap(find.byTooltip('Close voice management'));
      await _pumpUi(tester);
      final radoc = const ReaderDocumentSerializationService()
          .serializeToJsonString(cold.document);
      final radocBytes = Uint8List.fromList(utf8.encode(radoc));
      await _finish(tester, cold);

      final warm = ReaderController(
        preparationSupervisor: DocumentPreparationSupervisor(
          workerEntryPoint: _rejectUnexpectedSourcePreparation,
        ),
        ttsEngine: _UiEngine(),
        enablePlatformIntakeChannels: false,
      );
      addTearDown(warm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ReadAloudScreen(controller: warm)),
      );
      await _pumpUntil(tester, () => !warm.isInitializing);
      picker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'orchard.radoc',
          size: radocBytes.length,
          bytes: radocBytes,
        ),
      ]);
      await _openDocument(tester);
      await _pumpUntil(tester, () => warm.isPreparationComplete);
      expect(warm.document.speakableText, expectedText);
      expect(
        warm.document.characterCastRegistry.entries
            .map((entry) => entry.castId)
            .toSet(),
        expectedCast,
      );
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await _pumpUi(tester);
      final reopenedDropdown = find.descendant(
        of: find.byKey(const Key('voice-assignment-card-Narrator')),
        matching: find.byType(DropdownButton<String>),
      );
      await tester.ensureVisible(reopenedDropdown);
      await _pumpUi(tester);
      expect(
        tester.widget<DropdownButton<String>>(reopenedDropdown).value,
        chosenNarrator,
      );
      await tester.tap(find.byTooltip('Close voice management'));
      await _pumpUi(tester);
      expect(warm.isPreparingDocument, isFalse);
      expect(tester.takeException(), isNull);
      await _finish(tester, warm);
    },
  );

  testWidgets('Open Document reports malformed radoc and keeps current text', (
    tester,
  ) async {
    final picker = _UiFilePicker();
    FilePicker.platform = picker;
    final controller = ReaderController(
      ttsEngine: _UiEngine(),
      enablePlatformIntakeChannels: false,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ReadAloudScreen(controller: controller)),
    );
    await _pumpUntil(tester, () => !controller.isInitializing);
    await _paste(tester, 'Keep this text when an invalid file is opened.');
    await _pumpUntil(
      tester,
      () =>
          controller.preparedRanges.isNotEmpty &&
          !controller.isPreparingDocument,
    );
    final existingText = controller.document.speakableText;
    picker.nextResult = FilePickerResult([
      PlatformFile(
        name: 'broken.radoc',
        size: 4,
        bytes: Uint8List.fromList(utf8.encode('{bad')),
      ),
    ]);
    await _openDocument(tester);
    await _pumpUntil(tester, () => controller.statusMessage != null);
    expect(controller.document.speakableText, existingText);
    expect(controller.statusMessage, contains('malformed'));
    expect(tester.takeException(), isNull);
    await _finish(tester, controller);
  });

  testWidgets(
    'normal pasted source reopens its automatic radoc checkpoint and retained cast choices without analysis',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final directory = Directory.systemTemp.createTempSync(
        'reader-warm-source-ui-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final repository = ReaderDocumentRepository(directory.path);
      final text = File(
        'test/fixtures/rc2_prose/text/orchard.txt',
      ).readAsStringSync();
      final cold = ReaderController(
        documentRepository: repository,
        ttsEngine: _UiEngine(),
        enablePlatformIntakeChannels: false,
      );
      addTearDown(cold.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ReadAloudScreen(controller: cold)),
      );
      await _pumpUntil(tester, () => !cold.isInitializing);
      await _paste(tester, text);
      await _pumpUntil(
        tester,
        () => cold.isPreparationComplete && cold.preparedRanges.isNotEmpty,
      );
      final expectedDocumentId = cold.sessionDocumentId;
      final expectedCastIds = cold.document.characterCastRegistry.entries
          .map((entry) => entry.castId)
          .toSet();
      final expectedText = cold.document.speakableText;
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await _pumpUi(tester);
      final narrator = find.byKey(const Key('voice-assignment-card-Narrator'));
      final dropdown = find.descendant(
        of: narrator,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.ensureVisible(dropdown);
      await _pumpUi(tester);
      final original = cold.castVoiceAssignments!
          .forCastId('cast_narrator')!
          .effectiveVoiceId;
      final chosen = original == 'af_bella' ? 'am_michael' : 'af_bella';
      await tester.tap(dropdown);
      await _pumpUi(tester);
      await tester.tap(
        find
            .text(chosen == 'af_bella' ? 'Bella (en-US)' : 'Michael (en-US)')
            .last,
      );
      await _pumpUi(tester);
      expect(
        cold.castVoiceAssignments!.forCastId('cast_narrator')!.effectiveVoiceId,
        chosen,
      );
      await _finish(tester, cold);

      final manifest = directory
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('/manifest.json'));
      final before = manifest.readAsStringSync();
      final payload =
          jsonDecode((jsonDecode(before) as Map)['payload'] as String) as Map;
      expect(payload['complete'], isTrue);
      final rangeFiles = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => RegExp(r'/[0-9]+\.json$').hasMatch(file.path))
          .toList();
      expect(rangeFiles, isNotEmpty);
      final rangePayload =
          jsonDecode(
                (jsonDecode(rangeFiles.first.readAsStringSync())
                        as Map)['payload']
                    as String,
              )
              as Map;
      expect(
        (jsonDecode(rangePayload['document'] as String)
            as Map)['formatVersion'],
        'radoc-v2',
      );

      // This is source replay through the real repository, not .radoc file-picker
      // intake. Any fallback to source preparation is an explicit test failure.
      final warmEngine = _UiEngine();
      final warm = ReaderController(
        preparationSupervisor: DocumentPreparationSupervisor(
          repository: repository,
          workerEntryPoint: _rejectUnexpectedSourcePreparation,
        ),
        ttsEngine: warmEngine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(warm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ReadAloudScreen(controller: warm)),
      );
      await _pumpUntil(tester, () => !warm.isInitializing);
      await _paste(tester, text);
      await _pumpUntil(
        tester,
        () => warm.isPreparationComplete && warm.preparedRanges.isNotEmpty,
      );
      expect(warm.document.speakableText, expectedText);
      expect(warm.sessionDocumentId, expectedDocumentId);
      expect(
        warm.document.characterCastRegistry.entries
            .map((entry) => entry.castId)
            .toSet(),
        expectedCastIds,
      );
      expect(
        warm.castVoiceAssignments!.forCastId('cast_narrator')!.effectiveVoiceId,
        chosen,
      );
      expect(
        manifest.readAsStringSync(),
        before,
        reason: 'Warm replay reuses the immutable completed checkpoint',
      );
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await _pumpUi(tester);
      final warmDropdown = find.descendant(
        of: find.byKey(const Key('voice-assignment-card-Narrator')),
        matching: find.byType(DropdownButton<String>),
      );
      await tester.ensureVisible(warmDropdown);
      await _pumpUi(tester);
      expect(tester.widget<DropdownButton<String>>(warmDropdown).value, chosen);
      await tester.tap(find.byTooltip('Close voice management'));
      await _pumpUi(tester);
      await tester.tap(find.bySemanticsLabel('Play'));
      await _pumpUntil(tester, () => warmEngine.requests.isNotEmpty);
      expect(warmEngine.requests.single.text, expectedText);
      expect(tester.takeException(), isNull);
      await _finish(tester, warm);
    },
  );

  for (final name in [
    'tide',
    'lantern',
    'orchard',
    'platform',
    'bridge',
    'rain',
  ]) {
    testWidgets('normal paste and real voice dialog expose exact $name cast', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final engine = _UiEngine();
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        controller.dispose();
      });
      final source = File(
        'test/fixtures/rc2_prose/text/$name.txt',
      ).readAsStringSync();
      // The production path sees only prose. Oracles are used after intake.
      await tester.pumpWidget(
        MaterialApp(home: ReadAloudScreen(controller: controller)),
      );
      await _pumpUntil(tester, () => !controller.isInitializing);
      await _paste(tester, source);
      await _pumpUntil(
        tester,
        () =>
            controller.preparedRanges.isNotEmpty &&
            !controller.isPreparingDocument,
      );
      final oracle =
          jsonDecode(
                File(
                  'test/fixtures/rc2_prose/oracles/$name.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        controller.document.characterCastRegistry.characterEntries
            .map((entry) => entry.castId)
            .toSet(),
        (oracle['canonicalCastIds'] as List).cast<String>().toSet(),
      );
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await _pumpUi(tester);
      expect(find.text('Voice Management'), findsOneWidget);
      final registry = controller.document.characterCastRegistry;
      final characters = registry.characterEntries.toList()
        ..sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
      final entries = [registry.narratorEntry, ...characters];
      for (final entry in entries) {
        final card = find.byKey(
          Key('voice-assignment-card-${entry.displayLabel}'),
        );
        await tester.scrollUntilVisible(
          card,
          180,
          scrollable: find
              .descendant(
                of: find.byType(VoiceManagementDialog),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final dropdown = find.descendant(
          of: card,
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await tester.ensureVisible(dropdown);
        await tester.pump();
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.descendant(
                  of: dropdown,
                  matching: find.byType(DropdownButton<String>),
                ),
              )
              .items!
              .map((item) => item.value)
              .toSet(),
          {'af_bella', 'am_michael', 'af_heart'},
        );
        expect(
          tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged,
          isNotNull,
        );
      }
      // Edit the last visible real cast entry and prove the requested choice is
      // retained when the dialog closes and reopens during this document.
      final last = entries.last;
      final card = find.byKey(
        Key('voice-assignment-card-${last.displayLabel}'),
      );
      final dropdown = find.descendant(
        of: card,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      final current = controller.castVoiceAssignments!
          .forCastId(last.castId)!
          .effectiveVoiceId;
      final next = current == 'af_bella' ? 'am_michael' : 'af_bella';
      await tester.tap(dropdown);
      await _pumpUi(tester);
      await tester.tap(
        find
            .text(next == 'af_bella' ? 'Bella (en-US)' : 'Michael (en-US)')
            .last,
      );
      await _pumpUi(tester);
      expect(
        controller.castVoiceAssignments!
            .forCastId(last.castId)!
            .effectiveVoiceId,
        next,
      );
      await tester.tap(find.byTooltip('Close voice management'));
      await _pumpUi(tester);
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await _pumpUi(tester);
      expect(
        controller.castVoiceAssignments!
            .forCastId(last.castId)!
            .effectiveVoiceId,
        next,
      );
      await tester.scrollUntilVisible(
        card,
        180,
        scrollable: find
            .descendant(
              of: find.byType(VoiceManagementDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(dropdown);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: dropdown,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .value,
        next,
      );
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    });
  }

  testWidgets(
    'normal file intake publishes real ranges before delayed speech startup and pending Play cancels',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('reader-ui-');
      final source = File('${directory.path}/chapter.txt')
        ..writeAsStringSync(
          List.generate(
            600,
            (i) => 'Paragraph $i follows a quiet path through the valley.',
          ).join('\n\n'),
        );
      addTearDown(() => directory.deleteSync(recursive: true));
      final gate = Completer<void>();
      final engine = _UiEngine(startup: gate.future);
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReadAloudScreen(
            controller: controller,
            initialInputPaths: [source.path],
          ),
        ),
      );
      await _pumpUntil(tester, () => controller.preparedRanges.isNotEmpty);
      expect(controller.isInitializing, isTrue);
      expect(controller.hasCompleteDocumentSnapshot, isFalse);
      expect(controller.document.speakableText, contains('Paragraph 0'));
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(find.bySemanticsLabel('Cancel pending Play'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Cancel pending Play'));
      await tester.pump();
      gate.complete();
      await _pumpUntil(tester, () => !controller.isInitializing);
      expect(engine.requests, isEmpty);
      await tester.tap(find.bySemanticsLabel('Play'));
      await _pumpUntil(tester, () => engine.requests.isNotEmpty);
      expect(engine.requests.single.text, contains('Paragraph 0'));
      expect(controller.hasCompleteDocumentSnapshot, isFalse);
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    },
  );

  testWidgets(
    'cancel and retry preserve a published document and restore usable intake',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'reader-cancel-ui-',
      );
      final file = File('${directory.path}/book.txt')
        ..writeAsStringSync(
          List.generate(
            900,
            (i) => 'Paragraph $i follows the river through the valley.',
          ).join('\n\n'),
        );
      addTearDown(() => directory.deleteSync(recursive: true));
      final controller = ReaderController(
        ttsEngine: _UiEngine(),
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReadAloudScreen(
            controller: controller,
            initialInputPaths: [file.path],
          ),
        ),
      );
      await _pumpUntil(tester, () => controller.preparedRanges.isNotEmpty);
      final firstText = controller.document.speakableText;
      expect(find.byKey(const Key('cancel-preparation')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel-preparation')));
      await tester.pump();
      expect(controller.isPreparingDocument, isFalse);
      expect(controller.document.speakableText, firstText);
      expect(controller.canRetryDocumentPreparation, isTrue);
      expect(find.byKey(const Key('retry-preparation')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-preparation')));
      await _pumpUntil(
        tester,
        () =>
            controller.preparedRanges.isNotEmpty &&
            controller.isPreparingDocument,
      );
      expect(controller.document.speakableText, contains('Paragraph 0'));
      expect(controller.canRetryDocumentPreparation, isFalse);
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    },
  );

  testWidgets(
    'startup failure has a visible retry without blocking paste or cast inspection',
    (tester) async {
      final gate = Completer<void>();
      final engine = _UiEngine(startup: gate.future);
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(home: ReadAloudScreen(controller: controller)),
      );
      await tester.pump();
      gate.completeError(StateError('Missing required speech asset'));
      await _pumpUntil(tester, () => controller.startupError != null);
      expect(
        find.textContaining('Missing required speech asset'),
        findsOneWidget,
      );
      await _paste(
        tester,
        'John said, "The quiet river is beautiful today." Maria replied, "We can walk home together."',
      );
      await _pumpUntil(
        tester,
        () =>
            controller.preparedRanges.isNotEmpty &&
            !controller.isPreparingDocument,
      );
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await _pumpUi(tester);
      expect(find.text('Voice Management'), findsOneWidget);
      await tester.tap(find.byTooltip('Close voice management'));
      await _pumpUi(tester);
      await tester.tap(find.byKey(const Key('retry-startup')));
      await _pumpUntil(
        tester,
        () => !controller.isInitializing && controller.startupError == null,
      );
      expect(controller.voices, hasLength(3));
      expect(
        controller.document.characterCastRegistry.characterEntries
            .map((entry) => entry.displayLabel)
            .toSet(),
        {'John', 'Maria'},
      );
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    },
  );

  testWidgets('explicit paste wins over delayed startup restore', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'reader-restore-order-',
    );
    final previous = File('${directory.path}/previous.txt')
      ..writeAsStringSync(
        'The remembered document must not replace a new user request.',
      );
    addTearDown(() => directory.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({
      'reader.lastOpenedDocumentPath': previous.path,
    });
    final preferences = _DelayedPreferences();
    final controller = ReaderController(
      ttsEngine: _UiEngine(),
      preferencesService: preferences,
      enablePlatformIntakeChannels: false,
    );
    addTearDown(() async {
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: ReadAloudScreen(controller: controller)),
    );
    await _paste(
      tester,
      'This new document was explicitly chosen while preferences were loading.',
    );
    preferences.ready.complete();
    await _pumpUntil(
      tester,
      () =>
          controller.preparedRanges.isNotEmpty &&
          !controller.isPreparingDocument,
    );
    expect(controller.document.speakableText, contains('explicitly chosen'));
    expect(
      controller.document.speakableText,
      isNot(contains('remembered document')),
    );
    expect(tester.takeException(), isNull);
    await _finish(tester, controller);
  });
}

Future<void> _finish(WidgetTester tester, ReaderController controller) async {
  var complete = false;
  final drained = controller.shutdownPreparation().then((_) => complete = true);
  await _pumpUntil(tester, () => complete);
  await drained;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _paste(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const Key('reader-overflow-menu')));
  await _pumpUi(tester);
  await tester.tap(find.text('Paste Text'));
  await _pumpUi(tester);
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Load'));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reader-overflow-menu')));
  await _pumpUi(tester);
  await tester.tap(find.text('Open Document'));
  await _pumpUi(tester);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for real intake/publication');
}

class _UiEngine implements TtsEngine, VoiceLibraryCapable {
  _UiEngine({this.startup});
  final Future<void>? startup;
  var attempts = 0;
  final requests = <TtsSpeakRequest>[];
  static const voices = [
    VoiceProfile(id: 'af_bella', label: 'Bella', locale: 'en-US', rawValue: {}),
    VoiceProfile(
      id: 'am_michael',
      label: 'Michael',
      locale: 'en-US',
      rawValue: {},
    ),
    VoiceProfile(id: 'af_heart', label: 'Heart', locale: 'en-US', rawValue: {}),
  ];
  @override
  Future<void> initialize() async {
    if (++attempts == 1) await startup;
  }

  @override
  Future<List<VoiceProfile>> loadVoices() async => voices;
  @override
  List<VoiceLibraryEntry> get voiceLibrary => voices
      .map(
        (voice) =>
            VoiceLibraryEntry(voice: voice, isBundled: true, isInstalled: true),
      )
      .toList();
  @override
  Future<void> installVoice(String voiceId) async {}
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double multiplier) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    requests.add(request);
  }

  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DelayedPreferences extends ReaderPreferencesService {
  final ready = Completer<void>();
  @override
  Future<ReaderPreferences> load() async {
    await ready.future;
    return super.load();
  }
}

class _UiFilePicker extends FilePicker {
  FilePickerResult? nextResult;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => nextResult;
}

void _rejectUnexpectedSourcePreparation(DocumentPreparationWorkerInput input) {
  input.reply.send(
    DocumentPreparationResult(
      request: input.request,
      outcome: DocumentPreparationOutcome.failed,
      error: 'Unexpected source analysis during warm replay',
    ),
  );
}
