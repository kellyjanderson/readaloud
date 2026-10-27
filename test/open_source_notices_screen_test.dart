import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/screens/open_source_notices_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled snapshot survives worker sectioning byte for byte', () async {
    final sections = await loadOpenSourceNoticeSections(rootBundle);
    expect(sections.length, greaterThan(200));
    expect(sections.every((section) => section.length <= 8000), isTrue);
    expect(
      sections.join(),
      await rootBundle.loadString(openSourceNoticesAsset),
    );
  });

  test('empty and oversized snapshots fail explicitly', () async {
    for (final bytes in [Uint8List(0), Uint8List(4 * 1024 * 1024 + 1)]) {
      await expectLater(
        loadOpenSourceNoticeSections(
          _Bundle(() async => ByteData.sublistView(bytes)),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'section boundaries preserve long Unicode lines and original newlines',
    () async {
      final text = '${'x' * 7999}🙂${'y' * 9000}\r\nFinal\n';
      final sections = await loadOpenSourceNoticeSections(
        _Bundle(() async => _data(text)),
      );
      expect(sections.join(), text);
      expect(
        sections.every(
          (section) => utf8.decode(utf8.encode(section)) == section,
        ),
        isTrue,
      );
    },
  );

  testWidgets('success after route disposal cannot publish stale content', (
    tester,
  ) async {
    final pending = Completer<ByteData>();
    await tester.pumpWidget(
      MaterialApp(
        home: OpenSourceNoticesScreen(bundle: _Bundle(() => pending.future)),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: Text('Reader')));
    pending.complete(_data('obsolete notice'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
    expect(find.text('obsolete notice'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loads complete selectable content and keyboard returns to reader',
    (tester) async {
      final bundle = _Bundle(
        () async =>
            _data('FIRST NOTICE\n${'Full notice text.\n' * 1200}LAST NOTICE'),
      );
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OpenSourceNoticesScreen(bundle: bundle),
                  ),
                ),
                child: const Text('Reader'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reader'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsWidgets);
      final list = tester.widget<ListView>(
        find.byKey(const Key('open-source-notices-list')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(list.controller!.offset, greaterThan(0));
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('LAST NOTICE'),
        600,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Reader'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(bundle.loads, 1);
    },
  );

  testWidgets(
    'slow load stays single, terminal failure permits retry, stale completion is harmless',
    (tester) async {
      final pending = Completer<ByteData>();
      final bundle = _Bundle(() => pending.future);
      await tester.pumpWidget(
        MaterialApp(home: OpenSourceNoticesScreen(bundle: bundle)),
      );
      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining('taking longer'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(bundle.loads, 1);
      pending.completeError(StateError('missing asset'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load the bundled notices.'), findsOneWidget);
      final retry = Completer<ByteData>();
      bundle.read = () => retry.future;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(bundle.loads, 2);
      await tester.pumpWidget(const MaterialApp(home: Text('Reader')));
      retry.completeError(StateError('obsolete failure'));
      await tester.pumpAndSettle();
      expect(find.text('Reader'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

ByteData _data(String text) =>
    ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));

class _Bundle extends CachingAssetBundle {
  _Bundle(this.read);
  Future<ByteData> Function() read;
  int loads = 0;
  @override
  Future<ByteData> load(String key) {
    expect(key, openSourceNoticesAsset);
    loads++;
    return read();
  }
}
