import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/screens/read_aloud_screen.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
        await controller.shutdownPreparation();
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
        () => controller.preparedRanges.isNotEmpty && !controller.isImporting,
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
      await tester.pumpAndSettle();
      expect(find.text('Voice Management'), findsOneWidget);
      final entries = controller.document.characterCastRegistry.entries;
      for (final entry in entries) {
        final card = find.byKey(
          Key('voice-assignment-card-${entry.displayLabel}'),
        );
        await tester.scrollUntilVisible(
          card,
          180,
          scrollable: find.byType(Scrollable).first,
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
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(next == 'af_bella' ? 'Bella (en-US)' : 'Michael (en-US)')
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        controller.castVoiceAssignments!
            .forCastId(last.castId)!
            .effectiveVoiceId,
        next,
      );
      await tester.tap(find.byTooltip('Close voice management'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await tester.pumpAndSettle();
      expect(
        controller.castVoiceAssignments!
            .forCastId(last.castId)!
            .effectiveVoiceId,
        next,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'normal file intake publishes real ranges before delayed speech startup and pending Play cancels',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('reader-ui-');
      final source = await File('${directory.path}/chapter.txt').writeAsString(
        List.generate(
          600,
          (i) => 'Paragraph $i follows a quiet path through the valley.',
        ).join('\n\n'),
      );
      addTearDown(() => directory.delete(recursive: true));
      final gate = Completer<void>();
      final engine = _UiEngine(startup: gate.future);
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await controller.shutdownPreparation();
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
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancel and retry preserve a published document and restore usable intake',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'reader-cancel-ui-',
      );
      final file = await File('${directory.path}/book.txt').writeAsString(
        List.generate(
          900,
          (i) => 'Paragraph $i follows the river through the valley.',
        ).join('\n\n'),
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = ReaderController(
        ttsEngine: _UiEngine(),
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        await controller.shutdownPreparation();
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
      expect(controller.isImporting, isFalse);
      expect(controller.document.speakableText, firstText);
      expect(controller.canRetryDocumentPreparation, isTrue);
      expect(find.byKey(const Key('retry-preparation')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-preparation')));
      await _pumpUntil(
        tester,
        () => controller.preparedRanges.isNotEmpty && controller.isImporting,
      );
      expect(controller.document.speakableText, contains('Paragraph 0'));
      expect(controller.canRetryDocumentPreparation, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
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
        await controller.shutdownPreparation();
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
        () => controller.preparedRanges.isNotEmpty && !controller.isImporting,
      );
      await tester.tap(find.byKey(const Key('character-voices-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Voice Management'), findsOneWidget);
      await tester.tap(find.byTooltip('Close voice management'));
      await tester.pumpAndSettle();
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
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _paste(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const Key('reader-overflow-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Paste Text'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Load'));
  await tester.pump(const Duration(milliseconds: 400));
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
