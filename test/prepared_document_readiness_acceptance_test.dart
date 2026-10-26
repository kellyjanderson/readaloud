import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/document_voice_attribution.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #48 R1 / #54: deterministic controller + real preparation-worker evidence.
// Byte intake and resource completion are controlled; no fake semantic graph is
// returned. This does not exercise native resources, emitted audio or app UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'whole-document semantics precede resource and speech eligibility',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preparation = _ObservedPreparationSupervisor();
      final engine = _ResourceBarrierEngine();
      final file = _ByteBarrierFile();
      final controller = ReaderController(
        preparationSupervisor: preparation,
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        if (!file.bytes.isCompleted) file.bytes.complete(Uint8List(0));
        engine.release();
        await controller.shutdownPreparation();
        controller.dispose();
      });
      await controller.initialize();
      final previousDocument = controller.document;
      final importing = controller.importDroppedFiles([file]);
      await file.started.future;

      // The previous reading surface stays available while the replacement is
      // admitted. Its display flag cannot authorize speech for either revision.
      expect(controller.isDisplayReady, isTrue);
      expect(controller.document, same(previousDocument));
      expect(controller.isDocumentPrepared, isFalse);
      await controller.startPlayback();
      expect(engine.speakCalls, 0);
      expect(preparation.result, isNull);
      expect(preparation.activeCount, 1);
      expect(preparation.pendingCount, 0);

      const source =
          '"WHO IS THERE?"\n\n'
          'The road was empty.\n\n'
          'Rain covered the fields.\n\n'
          'A door opened nearby.\n\n'
          'John said, "Come with me."\n\n'
          "John's API stayed visible.";
      file.bytes.complete(Uint8List.fromList(utf8.encode(source)));
      await engine.started.future;

      final result = preparation.result!;
      expect(
        result.outcome,
        DocumentPreparationOutcome.ready,
        reason: result.error,
      );
      expect(result.workerName, startsWith('document-preparation-'));
      expect(result.request.ownerId, controller.preparationOwnerId);
      final document = controller.document;
      expect(document, same(result.document));
      expect(document.speakableText, source);
      expect(document.displayHtml, contains('WHO IS THERE?'));
      expect(document.positionMap.entries, isNotEmpty);

      // Inspect the complete accepted graph while resource preparation is still
      // held: every word has exactly one ordered ownership range, including the
      // final paragraph and an explicit unresolved-speaker narrator fallback.
      final ranges = document.documentVoiceAttribution.ranges;
      expect(ranges.map((range) => range.kind).toSet(), {
        DocumentVoiceAttributionKind.narration,
        DocumentVoiceAttributionKind.attributedDialogue,
        DocumentVoiceAttributionKind.unattributedDialogue,
      });
      var nextWord = 0;
      for (final range in ranges) {
        expect(range.startWordIndex, nextWord);
        expect(range.endWordIndex, greaterThan(range.startWordIndex));
        expect(range.segmentIds, isNotEmpty);
        expect(
          document.characterCastRegistry.entries.map((entry) => entry.castId),
          contains(range.castId),
        );
        if (range.kind == DocumentVoiceAttributionKind.attributedDialogue) {
          expect(
            range.castId,
            isNot(document.characterCastRegistry.narratorEntry.castId),
          );
        }
        if (range.kind == DocumentVoiceAttributionKind.unattributedDialogue) {
          expect(
            range.castId,
            document.characterCastRegistry.narratorEntry.castId,
          );
          expect(range.dialogueSpanId, isNotEmpty);
        }
        nextWord = range.endWordIndex;
      }
      expect(nextWord, document.wordCount);
      final annotations = document.baseSpeechAnnotations;
      expect(annotations.documentId, document.speechDocument.documentId);
      expect(
        annotations.annotations.map((value) => value.kind),
        contains(SpeechAnnotationKind.emphasisCandidate),
      );
      for (final segment in document.speechDocument.segments) {
        expect(annotations.forSegment(segment.segmentId), isNotEmpty);
      }
      final pronunciation = document.basePronunciationArtifacts;
      expect(pronunciation.documentId, document.speechDocument.documentId);
      expect(pronunciation.artifactVersion, isNotEmpty);
      expect(pronunciation.pronunciationProfileId, isNotEmpty);
      final finalSegment = document.speechDocument.segments.last;
      expect(pronunciation.forSegment(finalSegment.segmentId), isNotEmpty);
      expect(
        pronunciation.artifacts.expand((artifact) => artifact.diagnosticCodes),
        contains('pronunciation.resolved.possessive_allomorph'),
      );
      expect(() => pronunciation.artifacts.clear(), throwsUnsupportedError);

      // The new document is viewable, but complete semantics alone still cannot
      // start speech until its binding resources finish preparing.
      expect(controller.isDisplayReady, isTrue);
      expect(controller.isDocumentPrepared, isFalse);
      expect(controller.isResourcesReady, isFalse);
      expect(controller.isAudioReady, isFalse);
      await controller.startPlayback();
      expect(engine.speakCalls, 0);

      engine.release();
      await importing;
      expect(controller.isDocumentPrepared, isTrue);
      expect(controller.isResourcesReady, isTrue);
      expect(controller.preparedDocumentRevision, result.request.revision);
      expect(controller.resolvedResourceBindings, isNotEmpty);
      expect(
        controller.resourceBindings.map((binding) => binding.documentId),
        everyElement(document.speechDocument.documentId),
      );
      expect(engine.speakCalls, 0);
      await controller.startPlayback();
      expect(engine.speakCalls, 1);
    },
  );
}

class _ByteBarrierFile extends XFile {
  _ByteBarrierFile() : super('', name: 'readiness.txt');
  @override
  String get name => 'readiness.txt';
  final started = Completer<void>();
  final bytes = Completer<Uint8List>();

  @override
  Future<Uint8List> readAsBytes() {
    started.complete();
    return bytes.future;
  }
}

class _ObservedPreparationSupervisor extends DocumentPreparationSupervisor {
  DocumentPreparationResult? result;

  @override
  Future<DocumentPreparationResult> prepare(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
  }) async {
    return result = await super.prepare(request, acquireBytes: acquireBytes);
  }
}

class _ResourceBarrierEngine implements TtsEngine, ResourcePreparationCapable {
  final started = Completer<void>();
  final _completion = Completer<void>();
  var speakCalls = 0;
  var _ready = false;
  void release() {
    if (!_completion.isCompleted) _completion.complete();
  }

  @override
  bool get resourcesReady => _ready;
  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) async {
    if (!started.isCompleted) started.complete();
    await _completion.future;
    _ready = true;
    return [
      for (final id in voiceIds)
        PreparedVoiceBinding(
          voiceId: id,
          voiceDigest: 'fixture-voice',
          modelDigest: 'fixture-model',
          engineVersion: 'fixture',
          pronunciationProfileId: pronunciationProfileId,
          bindingRevision: revision,
          documentId: documentId,
        ),
    ];
  }

  @override
  Future<void> releaseDocumentResources() async {
    _ready = false;
  }

  @override
  Future<void> shutdownResources() => releaseDocumentResources();
  @override
  Future<void> initialize() async {}
  @override
  Future<List<VoiceProfile>> loadVoices() async => const [
    VoiceProfile(id: 'af_bella', label: 'Bella', locale: 'en-US', rawValue: {}),
  ];
  @override
  Future<void> selectVoice(VoiceProfile voice) async {}
  @override
  Future<void> setSpeechRate(double multiplier) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    speakCalls++;
  }

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
