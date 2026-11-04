import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

class _Reader extends ReaderController {
  _Reader(String root)
    : super(
        ttsEngine: _SilentEngine(),
        documentRepository: ReaderDocumentRepository(root),
        enablePlatformIntakeChannels: false,
      );
  Future<void>? _started;
  @override
  Future<void> initialize() => _started ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

class _SilentEngine implements TtsEngine {
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => const [
    VoiceProfile(id: 'af_bella', label: 'Probe', locale: 'en-US', rawValue: {}),
  ];
  @override
  Future<void> stop() async {}
  @override
  Future<void> selectVoice(VoiceProfile v) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets(
    'reader displays the last range of a novel and revisits the first',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      late Directory root;
      late _Reader reader;
      final text =
          '${List.generate(5000, (i) => 'Paragraph $i. The quiet river follows the road through the valley while the children wait beside the bridge.').join('\n\n')}\n\nTHE FINAL LANTERN WENT DARK.';
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('novel-display-');
        reader = _Reader(root.path);
        await reader.initialize();
        await reader.importPastedText(text);
      });
      addTearDown(() async {
        await reader.shutdownPreparation();
        reader.dispose();
        await root.delete(recursive: true);
      });
      await tester.pumpWidget(ReadAloudApp(controller: reader));
      final listFinder = find.byKey(const Key('whole-document-scroll'));
      for (var step = 0; step < 600; step++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        expect(reader.preparedRanges.length, lessThanOrEqualTo(8));
        expect(reader.pendingRangeReadCount, lessThanOrEqualTo(8));
        if (listFinder.evaluate().isNotEmpty) {
          final view = tester.widget<SuperListView>(listFinder);
          if (view.listController!.isAttached) {
            view.listController!.jumpToItem(
              index: view.childrenDelegate.estimatedChildCount! - 1,
              scrollController: view.controller!,
              alignment: 0.5,
            );
          }
        }
        if (reader.isPreparationComplete &&
            find.byKey(const Key('document-end')).evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(reader.isPreparationComplete, isTrue);
      expect(reader.preparedWordCount, greaterThan(90000));
      expect(reader.preparedRangeCount, greaterThan(8));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Html &&
              (w.data?.contains('THE FINAL LANTERN WENT DARK') ?? false),
        ),
        findsOneWidget,
      );
      final first = await tester.runAsync(() => reader.readPreparedRange(1));
      expect(first!.fragment.speakableText, startsWith('Paragraph 0.'));
      final view = tester.widget<SuperListView>(listFinder);
      view.listController!.jumpToItem(
        index: 0,
        scrollController: view.controller!,
        alignment: 0,
      );
      for (var step = 0; step < 30; step++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (find
            .byWidgetPredicate(
              (w) => w is Html && (w.data?.contains('Paragraph 0.') ?? false),
            )
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(
        find.byWidgetPredicate(
          (w) => w is Html && (w.data?.contains('Paragraph 0.') ?? false),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
