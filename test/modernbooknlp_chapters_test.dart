import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/modernbooknlp_analysis.dart';
import 'package:read_aloud/src/services/modernbooknlp_chapters.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Play publishes an immediately cancellable wait for the requested chapter',
    () async {
      final provider = _ControlledProvider();
      final analysis = ModernBookNlpAnalysis(() async => provider);
      final engine = _ChapterPlaybackEngine();
      final controller = await _controller(analysis: analysis, engine: engine);
      await controller.initialize();
      analysis.enable();
      final prose = File(
        'test/fixtures/rc2_prose/text/rain.txt',
      ).readAsStringSync();
      final directory = await Directory.systemTemp.createTemp('chapter-play-');
      addTearDown(() => directory.delete(recursive: true));
      final input = await File('${directory.path}/rain.txt').writeAsString(
        'Chapter One\n\n${prose.trim()}\n\n'
        'Chapter Two\n\nBruno waited beside the door.',
      );
      final firstCall = provider.calls.stream.first;
      await controller.importFilePaths([input.path], surfaceErrors: true);
      final first = await firstCall.timeout(const Duration(seconds: 8));
      await _until(
        () =>
            controller.preparationProgress[PreparationStage.analysis]?.state ==
            PreparationWorkState.working,
      );
      await _until(() => controller.isPreparationComplete);
      // Retry on the same held chapter, with source preparation already idle.
      final initialPlay = controller.startPlayback();
      await _until(() => controller.hasPendingPlaybackIntent);
      await controller.togglePlayback();
      await initialPlay.timeout(const Duration(seconds: 8));

      var publishedPendingPlay = false;
      controller.addListener(() {
        if (controller.hasPendingPlaybackIntent) publishedPendingPlay = true;
      });

      final pendingPlay = controller.startPlayback();
      await Future<void>.delayed(Duration.zero);
      expect(controller.hasPendingPlaybackIntent, isTrue);
      expect(engine.requests, isEmpty);
      expect(
        publishedPendingPlay,
        isTrue,
        reason: 'the transport needs a notification to expose Cancel',
      );
      final firstProgress =
          controller.preparationProgress[PreparationStage.analysis]!;
      expect(firstProgress.completed, 0);
      expect(firstProgress.total, isNull);

      await controller.togglePlayback();
      await pendingPlay.timeout(const Duration(seconds: 8));
      expect(controller.hasPendingPlaybackIntent, isFalse);
      final secondCall = provider.calls.stream.first;
      provider.finish(first);
      final second = await secondCall.timeout(const Duration(seconds: 8));
      expect(
        engine.requests,
        isEmpty,
        reason: 'a late chapter cannot revive Cancel',
      );
      expect(
        controller.preparationProgress[PreparationStage.analysis]?.completed,
        1,
      );

      await controller.startPlayback().timeout(const Duration(seconds: 8));
      final opening = engine.requests.single;
      expect(opening.sourceWordOffset, 0);
      expect(opening.chunkPlan?.chunks.first.startWordIndex, 0);
      expect(opening.text, startsWith('Chapter One'));
      expect(provider.requests, [first, second]);

      final cancelled = Completer<void>();
      final laterRange = opening.continuation!.next(
        opening.rangeSequence,
        cancelled.future,
      );
      var laterAdmitted = false;
      unawaited(laterRange.then((_) => laterAdmitted = true));
      await Future<void>.delayed(Duration.zero);
      expect(laterAdmitted, isFalse);
      provider.finish(second);
      final later = await laterRange.timeout(const Duration(seconds: 8));
      expect(later?.text, startsWith('Chapter Two'));
      expect(later?.sourceWordOffset, opening.speechDocument?.totalWordCount);
    },
  );

  test(
    'replacement and seek reject the retired chapter and hold the new anchor',
    () async {
      final provider = _ControlledProvider()..deliverAfterCancellation = true;
      final analysis = ModernBookNlpAnalysis(() async => provider);
      final engine = _ChapterPlaybackEngine();
      final controller = await _controller(analysis: analysis, engine: engine);
      await controller.initialize();
      analysis.enable();

      final oldCall = provider.calls.stream.first;
      await controller.importPastedText('Chapter One\n\nAda waited.');
      final retired = await oldCall.timeout(const Duration(seconds: 8));
      final retiredPlay = controller.startPlayback();
      await _until(() => controller.hasPendingPlaybackIntent);
      final replacement = provider.calls.stream.first;
      await controller.importPastedText(
        'Chapter One\n\nBruno arrived.\n\n'
        'The front door stood open.\n\n'
        'A stranger waited at the foot of the stairs.',
      );
      await retiredPlay.timeout(const Duration(seconds: 8));
      provider.finish(retired);

      final current = await replacement.timeout(const Duration(seconds: 8));
      expect(current.sourceRevision, isNot(retired.sourceRevision));
      expect(analysis.result, isNull);
      expect(analysis.completedWindows, 0);
      expect(engine.requests, isEmpty);
      await controller.jumpBySeconds(4);
      final anchor = controller.currentWordIndex;
      expect(anchor, greaterThan(0));
      final currentPlay = controller.startPlayback();
      await _until(() => controller.hasPendingPlaybackIntent);
      expect(engine.requests, isEmpty);
      provider.finish(current);
      await currentPlay.timeout(const Duration(seconds: 8));
      expect(analysis.completedWindows, 1);
      final admitted = engine.requests.single;
      expect(admitted.isResumedPlayback, isTrue);
      expect(admitted.chunkPlan?.chunks.first.startWordIndex, anchor);
      expect(
        admitted.documentId,
        controller.document.displayDocument.documentId,
      );
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

      final published = await Directory.systemTemp.createTemp(
        'chapter-analysis-portable-',
      );
      addTearDown(() => published.delete(recursive: true));
      final file = await controller.exportDocumentToPath(
        '${published.path}/book.radoc',
      );
      expect(file, isNotNull, reason: controller.statusMessage);
      final restored = ModernBookNlpAnalysis(
        () async => throw StateError('Book analysis must restore offline'),
      );
      final offline = await _controller(analysis: restored);
      await offline.importFilePaths([file!.path]);
      restored.enable();
      await _until(
        () => restored.completedWindows == 2 || restored.error != null,
      );
      expect(restored.error, isNull);
      expect(restored.restoredFromBook, isTrue);
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

Future<ReaderController> _controller({
  ModernBookNlpAnalysis? analysis,
  TtsEngine? engine,
}) async {
  SharedPreferences.setMockInitialValues({});
  final directory = await Directory.systemTemp.createTemp('chapter-intake-');
  final controller = ReaderController(
    characterAnalysis: analysis,
    ttsEngine: engine,
    preferencesService: ReaderPreferencesService(
      workRepository: WorkCharacterRepository('${directory.path}/works'),
    ),
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

class _ChapterPlaybackEngine implements TtsEngine, TtsEngineIdentityCapable {
  final requests = <TtsSpeakRequest>[];

  @override
  String get engineId => 'fish_drama3_8bit';
  @override
  String get engineVersion => 'controlled';
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => [
    const VoiceProfile(
      id: 'narrator',
      label: 'Narrator',
      locale: 'en-US',
      rawValue: {},
    ),
  ];
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double multiplier) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async => requests.add(request);
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
  @override
  set onStart(void Function()? callback) {}
  @override
  set onStatus(void Function(String? message)? callback) {}
  @override
  set onProgress(void Function(TtsProgressUpdate update)? callback) {}
  @override
  set onComplete(void Function()? callback) {}
  @override
  set onError(void Function(String message)? callback) {}
  @override
  set onActivity(void Function(TtsPlaybackActivity activity)? callback) {}
  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) {}
}
