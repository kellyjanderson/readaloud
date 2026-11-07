import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/radoc_audio_manifest.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/radoc_audio_package.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:read_aloud/src/services/rendered_scene_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _OfflineEngine engine;
  late ReaderController controller;
  late RenderedSceneRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('reader-book-');
    engine = _OfflineEngine();
    repository = RenderedSceneRepository(Directory('${temp.path}/durable'));
    controller = ReaderController(
      ttsEngine: engine,
      deferInitialSynthesis: true,
      enablePlatformIntakeChannels: false,
      renderedSceneRepository: repository,
    );
    await controller.initialize();
  });
  tearDown(() async {
    await controller.shutdownPreparation();
    controller.dispose();
    await temp.delete(recursive: true);
  });
  Future<File> fixture({
    bool secondAudio = true,
    bool staleDirections = false,
  }) async {
    final service = RadocAudioPackage();
    final members = <String, File>{};
    final ranges = <RadocPreparedRange>[];
    final scenes = <RadocAudioScene>[];
    const texts = ['Stay close.', 'Wait here.'];
    for (var i = 0; i < 2; i++) {
      final doc = DocumentImportService().importPastedText(texts[i]);
      final name = 'prepared/$i.json';
      members[name] = await const ReaderDocumentSerializationService()
          .writeToFile(document: doc, outputPath: '${temp.path}/$i.json');
      ranges.add(
        RadocPreparedRange(member: name, startWord: i * 2, endWord: i * 2 + 2),
      );
      if (i == 1 && !secondAudio) continue;
      final audio = 'audio/$i.wav';
      members[audio] = await File('${temp.path}/$i.wav').writeAsBytes(_wav());
      final dependencies = <String, dynamic>{
        'text': texts[i],
        'rate': 1.0,
        if (staleDirections && i == 0)
          'raw': {
            'canonicalDirections': [
              {'delivery': 'whispered'},
            ],
          },
      };
      scenes.add(
        RadocAudioScene(
          sceneId: 'scene-$i',
          startWord: i * 2,
          endWord: i * 2 + 2,
          audioMember: audio,
          dependencyDigest: artifactIdentity(dependencies),
          dependencies: dependencies,
          provenance: {'text': texts[i], 'startOffset': 0},
          sampleRate: 24000,
          channels: 1,
          frameCount: 240,
        ),
      );
    }
    final file = File('${temp.path}/book.radoc');
    await service.export(
      destination: file,
      manifest: RadocAudioManifest(
        documentId: 'book',
        sourceId: 'source',
        preparationComplete: true,
        totalWords: 4,
        preparedRanges: ranges,
        analysisMembers: [],
        scenes: scenes,
        intent: {
          'defaultVoiceId': 'published',
          'multiVoice': true,
          'rate': 1.0,
          'voices': [
            {'id': 'published', 'label': 'Published voice', 'locale': 'en-US'},
            {'id': 'other', 'label': 'Other voice', 'locale': 'en-US'},
          ],
        },
      ),
      members: members,
    );
    await service.dispose();
    return file;
  }

  test(
    'copied complete book opens, advances and republishes without models',
    () async {
      final original = await fixture();
      final copied = await original.copy('${temp.path}/copied.radoc');
      await original.delete();
      await controller.importFilePaths([copied.path]);
      expect(
        controller.hasPublishedAudio,
        true,
        reason: controller.statusMessage,
      );
      expect(controller.document.speakableText, 'Stay close.');
      await controller.completeInitialIntake();
      await controller.startPlayback();
      expect(engine.modelCalls, 0);
      expect(engine.requests, hasLength(1), reason: controller.statusMessage);
      final first = engine.requests.single;
      expect(await File(first.audioPath).exists(), true);
      expect(controller.isPlaying, true);
      final canceled = Completer<void>();
      final next = await first.continuation!.next(
        first.rangeSequence,
        canceled.future,
      );
      expect(next!.startWordIndex, 2);
      next.onRangeActive!();
      expect(controller.document.speakableText, 'Wait here.');
      expect(
        await next.continuation!.next(next.rangeSequence, canceled.future),
        isNull,
      );
      final output = await controller.exportDocumentToPath(
        '${temp.path}/published.radoc',
      );
      expect(output, isNotNull, reason: controller.statusMessage);
      final check = RadocAudioPackage();
      final book = await check.open(output!);
      expect(book.manifest.renderingComplete, true);
      expect(book.manifest.preparedRanges, hasLength(2));
      expect(book.manifest.scenes, hasLength(2));
      await check.dispose();
      await controller.importFilePaths([output.path]);
      expect(
        controller.hasPublishedAudio,
        true,
        reason: controller.statusMessage,
      );
      await controller.startPlayback();
      expect(engine.requests, hasLength(2), reason: controller.statusMessage);
      expect(engine.modelCalls, 0);
    },
  );
  test(
    'partial book gap cannot be reported as EOF and demands model on resume',
    () async {
      await controller.importFilePaths([
        (await fixture(secondAudio: false)).path,
      ]);
      await controller.startPlayback();
      final request = engine.requests.single;
      await expectLater(
        request.continuation!.next(0, Completer<void>().future),
        throwsStateError,
      );
      expect(engine.modelCalls, 0);
      await controller.startPlayback();
      expect(engine.modelCalls, 1);
      expect(controller.statusMessage, contains('needs rendering'));
      expect(engine.requests, hasLength(1));
    },
  );
  test('replacement rejects an old scene continuation', () async {
    final file = await fixture();
    await controller.importFilePaths([file.path]);
    await controller.startPlayback();
    final request = engine.requests.single;
    await controller.importFilePaths([file.path]);
    expect(request.isCurrent!(), false);
    await expectLater(
      request.continuation!.next(0, Completer<void>().future),
      throwsA(anything),
    );
    expect(engine.requests, hasLength(1));
  });
  test(
    'newly saved missing passage reopens without its source files or model',
    () async {
      final file = await fixture(secondAudio: false);
      final audio = await File('${temp.path}/new.wav').writeAsBytes(_wav());
      final saved = await repository.publish(
        TtsFinalizedAudioScene(
          documentId: 'ephemeral',
          generationId: 'ephemeral',
          sceneId: 'ephemeral',
          text: 'Wait here.',
          engineSpeakText: 'Wait here.',
          startWordIndex: 2,
          endWordIndex: 4,
          startOffset: 0,
          sceneTurns: [],
          preparedBindings: [],
          audioPath: audio.path,
          duration: const Duration(milliseconds: 10),
          engineId: 'fixture',
          engineVersion: 'fixture-v1',
          normalizationVersion: 'fixture-v1',
          capabilityProfileId: 'fixture-v1',
          synthesisIdentity: 'fixture',
          translationSignature: 'fixture',
          synthesisRate: 1,
          assignmentRevision: 1,
          cancelled: Completer<void>().future,
          isCurrent: () => true,
        ),
        sourceId: 'source',
        intent: {
          'defaultVoiceId': 'published',
          'multiVoice': true,
          'rate': 1.0,
        },
      );
      await audio.delete();
      await controller.importFilePaths([file.path]);
      await controller.startPlayback();
      final first = engine.requests.single;
      final next = await first.continuation!.next(0, Completer<void>().future);
      expect(next!.audioPath, saved.audioPath);
      expect(next.startWordIndex, 2);
      expect(
        await next.continuation!.next(1, Completer<void>().future),
        isNull,
      );
      expect(engine.modelCalls, 0);
    },
  );
  test(
    'changed canonical direction invalidates saved audio before admission',
    () async {
      await controller.importFilePaths([
        (await fixture(staleDirections: true)).path,
      ]);
      await controller.startPlayback();
      expect(engine.modelCalls, 1);
      expect(engine.requests, isEmpty);
      expect(controller.statusMessage, contains('needs rendering'));
    },
  );
  test('changed default voice does not play the old saved identity', () async {
    await controller.importFilePaths([(await fixture()).path]);
    await controller.selectVoiceById('other');
    expect(engine.modelCalls, 0);
    await controller.startPlayback();
    expect(engine.modelCalls, 1);
    expect(engine.requests, isEmpty);
  });
}

class _OfflineEngine implements TtsEngine, RenderedAudioPlaybackCapable {
  int modelCalls = 0;
  final requests = <TtsRenderedAudioRequest>[];
  @override
  void Function()? onStart;
  @override
  void Function(String?)? onStatus;
  @override
  void Function(TtsProgressUpdate)? onProgress;
  @override
  void Function()? onComplete;
  @override
  void Function(String)? onError;
  @override
  void Function(TtsPlaybackActivity)? onActivity;
  @override
  void Function(TtsDebugTraceSnapshot)? onDebugTrace;
  @override
  Future<void> initialize() async {
    modelCalls++;
    throw StateError('No installed model');
  }

  @override
  Future<void> playRendered(TtsRenderedAudioRequest request) async {
    requests.add(request);
    request.onPlaybackReady?.call(
      RenderedAudioPlaybackAcknowledgment(
        documentId: request.documentId,
        manifestIdentity: request.manifestIdentity,
        intentRevision: request.intentRevision,
        generationId: 'test',
      ),
    );
    request.onRangeActive?.call();
    onStart?.call();
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    modelCalls++;
    throw StateError('Unexpected synthesis call ${invocation.memberName}');
  }
}

Uint8List _wav() {
  final b = ByteData(44 + 480);
  void tag(int i, String s) {
    for (var k = 0; k < s.length; k++) {
      b.setUint8(i + k, s.codeUnitAt(k));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, b.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 24000, Endian.little);
  b.setUint32(28, 48000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, 480, Endian.little);
  return b.buffer.asUint8List();
}
