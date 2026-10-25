import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Controller ownership tests only: the fake never renders or writes audio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final fail in [false, true]) {
    test(
      'replacement during export resource ${fail ? 'failure' : 'success'} rejects old dispatch',
      () async {
        final engine = _ExportEngine();
        final controller = ReaderController(
          ttsEngine: engine,
          enablePlatformIntakeChannels: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final original = DocumentImportService().importPastedText(
          'Original amber document.',
        );
        final replacement = DocumentImportService().importPastedText(
          'Replacement blue document.',
        );
        await controller.loadDocument(original);
        final barrier = _Barrier();
        engine.nextResource = barrier;
        engine.resourcesReady = false;
        final exporting = controller.exportAudioToPath('/tmp/original.wav');
        await barrier.started.future.timeout(const Duration(seconds: 2));
        await controller.loadDocument(replacement);
        controller.showStatusMessage('Replacement owns status');
        if (fail) {
          barrier.release.completeError(StateError('old resource failure'));
        } else {
          barrier.release.complete();
        }
        expect(await exporting, isNull);
        expect(engine.requests, isEmpty);
        expect(
          controller.document.displayDocument.documentId,
          replacement.displayDocument.documentId,
        );
        expect(controller.statusMessage, 'Replacement owns status');
        expect(controller.isExporting, isFalse);
        // A fresh export remains usable and all request components belong to B.
        expect(
          await controller.exportAudioToPath('/tmp/replacement.wav'),
          isNotNull,
        );
        final request = engine.requests.single;
        expect(request.documentId, replacement.displayDocument.documentId);
        expect(request.text, replacement.speakableText);
        expect(
          request.speechDocument?.documentId,
          replacement.speechDocument.documentId,
        );
        expect(
          request.chunkPlan!.chunks.expand((chunk) => chunk.segmentIds),
          everyElement(isIn(replacement.speechDocument.segmentIndexById.keys)),
        );
      },
    );
    test(
      'replacement suppresses stale export ${fail ? 'failure' : 'success'} terminal',
      () async {
        final engine = _ExportEngine();
        final controller = ReaderController(
          ttsEngine: engine,
          enablePlatformIntakeChannels: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final original = DocumentImportService().importPastedText(
          'Original amber document.',
        );
        final replacement = DocumentImportService().importPastedText(
          'Replacement blue document.',
        );
        await controller.loadDocument(original);
        final barrier = _Barrier();
        engine.nextExport = barrier;
        final exporting = controller.exportAudioToPath('/tmp/original.wav');
        await barrier.started.future.timeout(const Duration(seconds: 2));
        expect(
          engine.requests.single.documentId,
          original.displayDocument.documentId,
        );
        await controller.loadDocument(replacement);
        controller.showStatusMessage('Replacement owns status');
        if (fail) {
          barrier.release.completeError(StateError('old export failed'));
        } else {
          barrier.release.complete();
        }
        expect(await exporting, isNull);
        expect(controller.statusMessage, 'Replacement owns status');
        expect(
          controller.document.displayDocument.documentId,
          replacement.displayDocument.documentId,
        );
        expect(controller.isExporting, isFalse);
      },
    );
  }
}

class _Barrier {
  final started = Completer<void>();
  final release = Completer<void>();
  Future<void> wait() {
    started.complete();
    return release.future;
  }
}

class _ExportEngine
    implements TtsEngine, ResourcePreparationCapable, AudioExportCapable {
  static const voice = VoiceProfile(
    id: 'af_bella',
    label: 'Bella',
    locale: 'en-US',
    rawValue: {'name': 'Bella', 'locale': 'en-US'},
  );
  _Barrier? nextResource;
  _Barrier? nextExport;
  final requests = <TtsExportRequest>[];
  @override
  bool resourcesReady = true;
  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) async {
    final barrier = nextResource;
    nextResource = null;
    await barrier?.wait();
    resourcesReady = true;
    return [
      for (final id in voiceIds)
        PreparedVoiceBinding(
          voiceId: id,
          voiceDigest: 'voice',
          modelDigest: 'model',
          engineVersion: 'test',
          pronunciationProfileId: pronunciationProfileId,
          bindingRevision: revision,
          documentId: documentId,
        ),
    ];
  }

  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    requests.add(request);
    final barrier = nextExport;
    nextExport = null;
    await barrier?.wait();
    return TtsExportResult(
      outputPath: request.outputPath,
      sidecarPath: '${request.outputPath}.json',
      duration: const Duration(seconds: 1),
      chunkCount: request.chunkPlan?.chunks.length ?? 0,
      voiceId: voice.id,
      rate: 1,
      engineId: 'fake',
      engineVersion: 'test',
    );
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => [voice];
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double multiplier) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> releaseDocumentResources() async {
    resourcesReady = false;
  }

  @override
  Future<void> shutdownResources() async {
    resourcesReady = false;
  }

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
