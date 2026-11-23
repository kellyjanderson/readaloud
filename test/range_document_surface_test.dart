import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
    'dragging across mounted ranges copies the paragraph break and Unicode',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      const before = 'BEGIN "Café", naïve—e\u0301cho 🐈 END.';
      const after = 'NEXT «cœur», piñata—東京 🧭 STOP.';
      late Directory root;
      late _Reader reader;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('range-selection-');
        reader = _Reader('${root.path}/prepared');
        final source = await File('${root.path}/seam.html').writeAsString(
          '<html><body><p>$before</p><p>$after</p></body></html>',
        );
        await reader.initialize();
        await reader.importFilePaths([source.path]);
      });
      addTearDown(() async {
        await reader.shutdownPreparation();
        reader.dispose();
        await root.delete(recursive: true);
      });

      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(ReadAloudApp(controller: reader));
      Finder paragraphInRange(int sequence, String text) => find.descendant(
        of: find.byKey(ValueKey('display-range-$sequence')),
        matching: find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == text,
        ),
      );
      final first = paragraphInRange(1, before);
      final second = paragraphInRange(2, after);
      for (var step = 0; step < 100; step++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (first.evaluate().isNotEmpty && second.evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(reader.preparedRangeCount, 2);
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);

      Offset edge(Finder finder, String text, {required bool start}) {
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        final box = start ? boxes.first : boxes.last;
        return paragraph.localToGlobal(
          Offset(start ? box.left + 3 : box.right - 3, box.toRect().center.dy),
        );
      }

      await tester.pumpAndSettle();
      Future<void> dragAndCopy(Offset start, Offset end) async {
        final gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        for (final step in [0.08, 0.16, 0.8, 1.0]) {
          await gesture.moveTo(Offset.lerp(start, end, step)!);
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
        copied = null;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }

      final start = edge(first, before, start: true);
      final end = edge(second, after, start: false);
      await dragAndCopy(start, end);
      expect(copied, '$before\n$after');

      await dragAndCopy(edge(second, after, start: true), end);
      expect(copied, after);
      await tester.pumpWidget(const SizedBox());
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

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
