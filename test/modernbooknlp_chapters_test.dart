import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/services/modernbooknlp_chapters.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a replaced source rejects a delayed successful provider reply',
    () async {
      final provider = _ControlledProvider()..deliverAfterCancellation = true;
      final analysis = ModernBookNlpAnalysis(() async => provider);
      final controller = await _controller(analysis: analysis);
      analysis.enable();

      final oldCall = provider.calls.stream.first;
      await controller.importPastedText('Chapter One\n\nAda waited.');
      final retired = await oldCall.timeout(const Duration(seconds: 8));
      final replacement = provider.calls.stream.first;
      await controller.importPastedText('Chapter One\n\nBruno arrived.');
      provider.finish(retired);

      final current = await replacement.timeout(const Duration(seconds: 8));
      expect(current.sourceRevision, isNot(retired.sourceRevision));
      expect(analysis.result, isNull);
      expect(analysis.completedWindows, 0);
      provider.finish(current);
      await _until(() => analysis.completedWindows == 1);
      expect(analysis.result?['requestId'], current.requestId);
    },
  );

  test(
    'keeps an intact chapter and source anchors across import fragments',
    () async {
      // Make the fragmenting importer split after a paragraph in Chapter One.
      final longParagraph = List.filled(
        116,
        'The gate stood open all afternoon.',
      ).join(' ');
      final text =
          'Chapter One\n\n$longParagraph\n\n$longParagraph\n\n'
          '“I saw you,” Ada said, “by the gate.”\n\n'
          'Chapter Two\n\nBruno started home.';
      final controller = await _controller();
      await controller.importPastedText(text);
      final cursor = ModernBookNlpChapters(controller.readPreparedRange);
      final first = (await cursor.next())!;
      expect(first.startsChapter, isTrue);
      expect(first.endsChapter, isTrue);
      expect(first.window.text, contains('Ada said'));
      expect(first.window.text, isNot(contains('Chapter Two')));
      expect(
        first.window.slices
            .map((s) => s.segment.segmentId.toString().split('_').first)
            .toSet()
            .length,
        greaterThan(1),
      );
      for (final slice in first.window.slices) {
        expect(
          first.window.text.substring(
            slice.offset,
            slice.offset + slice.end - slice.start,
          ),
          slice.segment.normalizedText.substring(slice.start, slice.end),
        );
      }
      final second = (await cursor.next())!;
      expect(second.window.text, 'Chapter Two\n\nBruno started home.');
      expect(await cursor.next(), isNull);
    },
  );

  test(
    'does not break a capacity-limited chapter inside a quotation',
    () async {
      final prose = List.filled(
        550,
        'Ada walked past the orchard.',
      ).join('\n\n');
      final chapter = DocumentImportService().importPastedText(
        'Chapter One\n\n$prose\n\n"A long answer comes to a close," Ada said.',
      );
      final cursor = ModernBookNlpChapters(
        (_) async => null,
        document: chapter,
      );
      final first = (await cursor.next())!;
      final last = (await cursor.next())!;
      expect(first.endsChapter, isFalse);
      expect(last.endsChapter, isTrue);
      expect(first.window.text.length, lessThanOrEqualTo(16384));
      expect(last.window.text.length, lessThanOrEqualTo(16384));
      expect(
        first.window.targetSegmentIds.intersection(
          last.window.targetSegmentIds,
        ),
        isEmpty,
      );
      expect({
        ...first.window.targetSegmentIds,
        ...last.window.targetSegmentIds,
      }, chapter.speechDocument.segments.map((s) => s.segmentId).toSet());
      expect(
        last.window.text,
        contains('"A long answer comes to a close," Ada said.'),
      );
      expect(await cursor.next(), isNull);
    },
  );

  test('an indivisible oversized quote gets an explicit outcome', () async {
    final text = '“${List.filled(4000, 'extraordinary').join(' ')}”';
    final doc = DocumentImportService().importPastedText(text);
    final cursor = ModernBookNlpChapters((_) async => null, document: doc);
    await expectLater(
      cursor.next(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('continued quotation'),
        ),
      ),
    );
  });

  test(
    'opening begins analysis, publishes chapters independently, and reuses their records',
    () async {
      final provider = _ControlledProvider();
      final analysis = ModernBookNlpAnalysis(() async => provider);
      final controller = await _controller(analysis: analysis);
      analysis.enable();
      const text =
          'Chapter One\n\nAda closed the door.\n\nChapter Two\n\nBruno stayed.';
      await controller.importPastedText(text);
      final first = await provider.calls.stream.first;
      expect(first.text, 'Chapter One\n\nAda closed the door.');
      final secondCall = provider.calls.stream.first;
      provider.finish(first);
      final second = await secondCall;
      expect(analysis.completedWindows, 1);
      expect(second.text, 'Chapter Two\n\nBruno stayed.');
      provider.finish(second);
      await _until(
        () => analysis.completedWindows == 2 || analysis.error != null,
      );
      expect(analysis.error, isNull);
      expect(provider.prepares, 1);

      await controller.importPastedText(text);
      await _until(
        () => analysis.completedWindows == 4 || analysis.error != null,
      );
      expect(analysis.error, isNull);
      expect(analysis.restoredFromBook, isTrue);
      expect(provider.requests, [first, second]);

      final editedCall = provider.calls.stream.first;
      await controller.importPastedText(
        text.replaceFirst('Bruno stayed.', 'Bruno left.'),
      );
      final edited = await editedCall;
      expect(edited.text, 'Chapter Two\n\nBruno left.');
      expect(analysis.result?['reusedEditedContext'], isTrue);
      provider.finish(edited);
      await _until(
        () => analysis.completedWindows == 6 || analysis.error != null,
      );
      expect(analysis.error, isNull);
      expect(provider.requests, [first, second, edited]);
    },
  );

  test(
    'token sentence identity protects the reporting clause attachment',
    () async {
      final document = DocumentImportService().importPastedText(
        '"Come in," Ada said, "before the storm."',
      );
      final cursor = ModernBookNlpChapters(
        (_) async => null,
        document: document,
      );
      final chapter = (await cursor.next())!;
      final result = {
        'linguisticArtifacts': {
          'files': {
            'tokens':
                'byte_onset\tsentence_ID\tparagraph_ID\n'
                '${chapter.window.slices.map((s) => '${s.offset}\t1\t0').join('\n')}',
          },
        },
      };
      final boundaries = await projectFishSceneBoundaries(chapter, result);
      expect(boundaries.values.first, FishSceneBoundary.chapter);
      expect(
        boundaries.values.skip(1),
        everyElement(FishSceneBoundary.continuation),
      );
      expect(boundaries.length, greaterThan(1));
    },
  );
}

Future<ReaderController> _controller({ModernBookNlpAnalysis? analysis}) async {
  SharedPreferences.setMockInitialValues({});
  final directory = await Directory.systemTemp.createTemp('chapter-intake-');
  final controller = ReaderController(
    characterAnalysis: analysis,
    documentRepository: ReaderDocumentRepository(directory.path),
    enablePlatformIntakeChannels: false,
  );
  addTearDown(() async {
    await controller.shutdownPreparation();
    controller.dispose();
    await directory.delete(recursive: true);
  });
  return controller;
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

class _ControlledProvider extends ModernBookNlpProvider {
  _ControlledProvider()
    : super(pythonPath: 'unused', helperPath: 'unused', runtimePath: 'unused');

  final calls = StreamController<ModernBookNlpRequest>.broadcast();
  final requests = <ModernBookNlpRequest>[];
  Completer<Map<String, dynamic>>? pending;
  int prepares = 0;
  bool deliverAfterCancellation = false;

  @override
  Future<void> prepare({
    bool offline = false,
    void Function(Map<String, dynamic>)? onProgress,
  }) async {
    prepares++;
  }

  @override
  Future<Map<String, dynamic>> analyze(
    ModernBookNlpRequest request, {
    void Function(Map<String, dynamic>)? onProgress,
  }) {
    requests.add(request);
    final response = pending = Completer<Map<String, dynamic>>();
    calls.add(request);
    return response.future;
  }

  void finish(ModernBookNlpRequest request) {
    pending!.complete({
      ...request.toJson(),
      'ok': true,
      'providerId': 'modernbooknlp-joint',
      'providerVersion': modernBookNlpRevision,
      'modelIdentity': modernBookNlpModelIdentity,
      'adapterVersion': modernBookNlpAdapterVersion,
      'tokenCount': 0,
      'entities': [],
      'quotes': [],
      'linguisticArtifacts': {
        'schema': 1,
        'pipeline': 'entity,quote,coref',
        'coordinateSystem': 'python-codepoint',
        'files': {
          'tokens': 'token_ID_within_document\tword\tbyte_onset\tbyte_offset\n',
          'entities': 'COREF\tstart_token\tend_token\tprop\tcat\ttext\n',
          'quotes': 'quote_start\tquote_end\tchar_id\n',
          'book': '{"characters":[]}',
        },
      },
    });
  }

  @override
  Future<void> cancel() async {
    if (deliverAfterCancellation) return;
    final active = pending;
    if (active != null && !active.isCompleted) {
      active.completeError(const ModernBookNlpCancelled());
    }
  }

  @override
  Future<void> close() async {
    await cancel();
    await calls.close();
  }
}
