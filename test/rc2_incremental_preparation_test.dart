import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/models/document_import_exception.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final prose = List.generate(
    180,
    (i) => 'Paragraph $i follows the road ahead.',
  ).join('\n\n');

  test('RTF supports the documented 256-group nesting boundary', () async {
    const depth = DocumentImportService.maxRtfGroupNesting;
    final source =
        '${List.filled(depth, '{').join()}\\rtf1 Boundary text.'
        '${List.filled(depth, '}').join()}';
    final bytes = Uint8List.fromList(utf8.encode(source));
    final importer = DocumentImportService();
    final units = await importer
        .streamUnits(fileName: 'boundary.rtf', bytes: bytes)
        .toList();
    expect(units.single.text, 'Boundary text.');
    expect(
      (await importer.importBytes(
        fileName: 'boundary.rtf',
        bytes: bytes,
      )).speakableText,
      'Boundary text.',
    );
  });

  test(
    'RTF over-cap source refuses with typed failure before publication',
    () async {
      const depth = DocumentImportService.maxRtfGroupNesting + 1;
      final source =
          '${List.filled(depth, '{').join()}\\rtf1 Too deep.'
          '${List.filled(depth, '}').join()}';
      final importer = DocumentImportService();
      final refusal = isA<DocumentImportException>()
          .having((error) => error.code, 'code', 'rtf_nesting_limit')
          .having((error) => error.fileName, 'fileName', 'too-deep.rtf');
      await expectLater(
        importer
            .streamUnits(
              fileName: 'too-deep.rtf',
              bytes: Uint8List.fromList(utf8.encode(source)),
            )
            .toList(),
        throwsA(refusal),
      );
      await expectLater(
        importer.importBytes(
          fileName: 'too-deep.rtf',
          bytes: Uint8List.fromList(utf8.encode(source)),
        ),
        throwsA(refusal),
      );

      final directory = await Directory.systemTemp.createTemp('rc2-rtf-depth-');
      addTearDown(() => directory.delete(recursive: true));
      // Large unread remainder: the interactive producer must reject at the
      // nesting boundary rather than retain a book-sized parser stack or wait
      // for decoded output/EOF. The supervisor deadline distinguishes refusal
      // from its generic timeout result; no wall-clock latency claim is made.
      final file = await File('${directory.path}/deep.rtf').writeAsString(
        '${List.filled(1000000, '{').join()}\\rtf1 Unreached text.',
      );
      final supervisor = DocumentPreparationSupervisor(
        timeout: const Duration(seconds: 2),
      );
      addTearDown(supervisor.shutdown);
      var publications = 0;
      final result = await supervisor.prepareRanges(
        DocumentPreparationRequest(
          ownerId: 'rtf-depth',
          revision: 1,
          kind: DocumentPreparationKind.bytes,
          fileName: 'deep.rtf',
          sourcePath: file.path,
        ),
        onPublication: (_) async {
          publications++;
        },
      );
      expect(result.outcome, DocumentPreparationOutcome.failed);
      expect(result.request.ownerId, 'rtf-depth');
      expect(result.request.revision, 1);
      expect(result.request.kind, DocumentPreparationKind.bytes);
      expect(result.request.fileName, 'deep.rtf');
      expect(result.request.bytes, isNull);
      expect(result.request.text, isNull);
      expect(result.importFailure?.code, 'rtf_nesting_limit');
      expect(result.importFailure?.message, isNotEmpty);
      expect(result.importFailure?.fileName, 'deep.rtf');
      expect(publications, 0);
    },
  );

  test(
    'bounded importer halos resolve opening pronoun and following tag with stable source IDs',
    () {
      final importer = DocumentImportService();
      const before =
          'Beatrice stood with a tin against her chest. Ada had left a ladder.';
      importer.importTextFragment(
        text: before,
        title: 'Halo',
        sessionId: 'halo',
        sourceStart: 0,
      );
      final current = importer.importTextFragment(
        text: '“Wait,” she said.',
        title: 'Halo',
        sessionId: 'halo',
        sourceStart: before.length,
      );
      expect(
        current.characterCastRegistry.characterEntries.single.displayLabel,
        'Beatrice',
      );
      final separate = DocumentImportService();
      final quote = separate.importTextFragment(
        text: '“Wait.”',
        title: 'Tag',
        sessionId: 'tag',
        sourceStart: 0,
        followingUnit: const DocumentImportUnit(text: 'Mara said.'),
      );
      expect(
        quote
            .dialogueAttributions
            .outcomes
            .single
            .speakerReference!
            .displayLabel,
        'Mara',
      );
      final next = separate.importTextFragment(
        text: 'Mara said.',
        title: 'Tag',
        sessionId: 'tag',
        sourceStart: '“Wait.”'.length,
      );
      expect(
        next.speechDocument.segments.single.segmentId,
        quote.dialogueAttributions.outcomes.single.evidenceSpan!.segmentId,
      );
    },
  );

  test(
    'stage tickets reject stale success and failure; canonical identity migration is explicit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final engine = _StartupEngine()..barrier.complete();
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        await controller.shutdownPreparation();
        controller.dispose();
      });
      await controller.initialize();
      await controller.importPastedText('A complete small source.');
      final old = controller.beginReadingStage(
        PreparationStage.persistence,
        producerId: 'writer',
        scope: 'Checkpoint',
      );
      final current = controller.beginReadingStage(
        PreparationStage.persistence,
        producerId: 'writer',
        scope: 'Checkpoint',
      );
      controller.publishReadingStage(
        current,
        const PreparationProgress(
          stage: PreparationStage.persistence,
          state: PreparationWorkState.working,
          completed: 1,
          total: 3,
          unit: 'chunks',
        ),
      );
      for (final state in [
        PreparationWorkState.failed,
        PreparationWorkState.complete,
      ]) {
        controller.publishReadingStage(
          old,
          PreparationProgress(
            stage: PreparationStage.persistence,
            state: state,
            completed: 3,
            total: 3,
            unit: 'chunks',
          ),
        );
        expect(
          controller
              .preparationProgress[PreparationStage.persistence]!
              .completed,
          1,
        );
      }
      final previous = controller.sessionDocumentId;
      expect(
        await controller.reconcileDocumentIdentity(
          DocumentIdentityMigration(
            ownerId: controller.preparationOwnerId,
            documentRevision: controller.preparedDocumentRevision,
            sourceRevision:
                '${controller.preparationOwnerId}:${controller.preparedDocumentRevision}',
            watchSession: current.watchSession,
            provisionalDocumentId: previous,
            canonicalDocumentId: 'verified-manifest-document',
            integrityBasis:
                DocumentIdentityIntegrityBasis.committedAcquiredByteCoverage,
          ),
        ),
        isTrue,
      );
      expect(
        controller.documentIdentityRedirects[previous],
        'verified-manifest-document',
      );
      expect(controller.document.displayDocument.documentId, previous);
    },
  );

  test(
    'first range precedes EOF, credit pauses work, replacement rejects stale completion',
    () async {
      final supervisor = DocumentPreparationSupervisor(
        timeout: const Duration(seconds: 1),
      );
      addTearDown(supervisor.shutdown);
      final first = Completer<DocumentPreparationPublication>();
      final credit = Completer<void>();
      var publications = 0;
      final old = supervisor.prepareRanges(
        DocumentPreparationRequest(
          ownerId: 'proof',
          revision: 1,
          kind: DocumentPreparationKind.pastedText,
          text: prose,
        ),
        onPublication: (range) {
          publications++;
          if (!first.isCompleted) first.complete(range);
          return credit.future;
        },
      );
      final range = await first.future;
      expect(range.sequence, 1);
      expect(range.request.text, isNull);
      expect(range.request.bytes, isNull);
      expect(range.range.sourceStart, 0);
      expect(range.fragment.wordCount, greaterThan(0));
      expect(range.fragment.speakableText.length, lessThan(prose.length));
      expect(range.serializedFragment, isNull);
      expect(range.isPreparationReady, isTrue);
      expect(range.isSpeechPlanReady, isFalse);
      expect(range.isResourceReady, isFalse);
      expect(range.progress.every((p) => p.total == null), isTrue);
      expect(
        range.progress
            .where((p) => p.stage == PreparationStage.persistence)
            .single
            .state,
        PreparationWorkState.waiting,
      );
      expect(
        () => range.fragment.speechDocument.segments.clear(),
        throwsUnsupportedError,
      );
      // Waiting for user/consumer credit is not a worker timeout.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(publications, 1);
      final latest = supervisor.prepareRanges(
        DocumentPreparationRequest(
          ownerId: 'proof',
          revision: 2,
          kind: DocumentPreparationKind.pastedText,
          text: 'Latest input.',
        ),
        onPublication: (_) async {},
      );
      expect((await old).outcome, DocumentPreparationOutcome.cancelled);
      expect((await latest).document!.speakableText, 'Latest input.');
      credit.complete();
      await supervisor.shutdown();
      expect(publications, 1);
    },
  );

  test(
    'file intake uses streamed path without invoking whole-byte acquisition',
    () async {
      final directory = await Directory.systemTemp.createTemp('rc2-text-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/input.txt',
      ).writeAsString(prose);
      final supervisor = DocumentPreparationSupervisor();
      addTearDown(supervisor.shutdown);
      final ranges = <DocumentPreparationPublication>[];
      final result = await supervisor.prepareRanges(
        DocumentPreparationRequest(
          ownerId: 'path',
          revision: 1,
          kind: DocumentPreparationKind.bytes,
          fileName: 'input.txt',
          sourcePath: file.path,
        ),
        acquireBytes: () => throw StateError('Whole read must not run'),
        onPublication: (range) async {
          ranges.add(range);
        },
      );
      expect(
        result.outcome,
        DocumentPreparationOutcome.ready,
        reason: result.error,
      );
      expect(ranges.length, greaterThan(1));
      expect(
        ranges
            .map((r) => r.fragment.speakableText)
            .join(' ')
            .replaceAll(RegExp(r'\s+'), ' '),
        prose.replaceAll(RegExp(r'\s+'), ' '),
      );
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].range.wordStart, ranges[i - 1].range.wordEnd);
        expect(ranges[i].range.sourceStart, ranges[i - 1].range.sourceEnd);
      }
    },
  );

  test(
    'PDF publishes a page before EOF and drains stale native failure',
    () async {
      final bridge = _PageBarrier();
      final supervisor = DocumentPreparationSupervisor(
        pdfTextExtractor: bridge,
      );
      addTearDown(supervisor.shutdown);
      final first = Completer<DocumentPreparationPublication>();
      final credit = Completer<void>();
      final old = supervisor.prepareRanges(
        DocumentPreparationRequest(
          ownerId: 'pdf',
          revision: 1,
          kind: DocumentPreparationKind.bytes,
          fileName: 'fixture.pdf',
          bytes: Uint8List.fromList([1]),
        ),
        onPublication: (publication) {
          first.complete(publication);
          return credit.future;
        },
      );
      expect((await first.future).range.sourceLocator, 'page:0');
      expect(bridge.secondStarted.isCompleted, isFalse);
      credit.complete();
      await bridge.secondStarted.future;
      final latest = supervisor.prepareRanges(
        DocumentPreparationRequest(
          ownerId: 'pdf',
          revision: 2,
          kind: DocumentPreparationKind.pastedText,
          text: 'Current input.',
        ),
        onPublication: (_) async {},
      );
      expect((await old).outcome, DocumentPreparationOutcome.cancelled);
      expect(supervisor.pendingCount, 1);
      bridge.release.completeError(StateError('Old native page failed'));
      expect((await latest).document!.speakableText, 'Current input.');
      expect(bridge.drained, isTrue);
    },
  );

  for (final extension in ['html', 'rtf', 'docx', 'epub']) {
    test(
      '$extension advances by bounded units without missing or duplicating words',
      () async {
        final paragraphs = List.generate(
          150,
          (i) => 'Paragraph $i says hello to café.',
        );
        final html =
            '<html><head><title>Hidden</title></head><body>${paragraphs.map((p) => '<p>$p</p>').join()}</body></html>';
        Uint8List bytes;
        if (extension == 'html') {
          bytes = Uint8List.fromList(utf8.encode(html));
        } else if (extension == 'rtf') {
          bytes = Uint8List.fromList(
            utf8.encode('{\\rtf1 ${paragraphs.join(r'\par ')}}'),
          );
        } else {
          final archive = Archive();
          if (extension == 'docx') {
            archive.addFile(
              ArchiveFile.string(
                'word/document.xml',
                '<w:document xmlns:w="urn:w"><w:body>${paragraphs.map((p) => '<w:p><w:r><w:t>$p</w:t></w:r></w:p>').join()}</w:body></w:document>',
              ),
            );
          } else {
            archive.addFile(
              ArchiveFile.string(
                'META-INF/container.xml',
                '<container><rootfile full-path="book.opf"/></container>',
              ),
            );
            archive.addFile(
              ArchiveFile.string(
                'book.opf',
                '<package><manifest><item id="first" href="first.xhtml"/></manifest><spine><itemref idref="first"/></spine></package>',
              ),
            );
            archive.addFile(ArchiveFile.string('first.xhtml', html));
          }
          bytes = Uint8List.fromList(ZipEncoder().encode(archive));
        }
        final units = await DocumentImportService()
            .streamUnits(fileName: 'book.$extension', bytes: bytes)
            .toList();
        expect(units.length, greaterThan(1));
        final actual = units
            .map((u) => u.text)
            .join(' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final expected = paragraphs.join(' ');
        if (actual != expected) {
          var mismatch = 0;
          while (mismatch < actual.length &&
              mismatch < expected.length &&
              actual[mismatch] == expected[mismatch]) {
            mismatch++;
          }
          fail(
            '$extension mismatch at $mismatch; '
            'actual ${actual.substring(mismatch, (mismatch + 90).clamp(0, actual.length))}; '
            'expected ${expected.substring(mismatch, (mismatch + 90).clamp(0, expected.length))}',
          );
        }
        expect(units.every((u) => u.text.length <= 8192), isTrue);
      },
    );
  }

  test(
    'pending Play cancels during startup and startup failure retries without active playback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final engine = _StartupEngine();
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        await controller.shutdownPreparation();
        controller.dispose();
      });
      final starting = controller.initialize();
      await engine.started.future;
      await controller.startPlayback();
      engine.pauseHold = Completer<void>();
      final cancelling = controller.pausePlayback();
      expect(controller.hasPendingPlaybackIntent, isFalse);
      engine.pauseHold!.complete();
      await cancelling;
      engine.barrier.completeError(StateError('Missing model fixture'));
      await starting;
      expect(controller.startupError, contains('Missing model fixture'));
      expect(controller.isInitializing, isFalse);
      expect(engine.spoken, 0);
      await controller.retryInitialization();
      expect(controller.startupError, isNull);
      expect(engine.attempts, 2);
      expect(engine.spoken, 0);
    },
  );

  test(
    'controller accepts first range and keeps only bounded work ahead',
    () async {
      SharedPreferences.setMockInitialValues({});
      final engine = _ExportProbe()..barrier.complete();
      final controller = ReaderController(
        ttsEngine: engine,
        enablePlatformIntakeChannels: false,
      );
      addTearDown(() async {
        await controller.shutdownPreparation();
        controller.dispose();
      });
      await controller.initialize();
      final import = controller.importPastedText('$prose\n\n$prose\n\n$prose');
      await controller.startPlayback();
      await import;
      await engine.speech.future;
      expect(controller.isDocumentPrepared, isTrue);
      expect(controller.isPreparationComplete, isFalse);
      expect(controller.document.wordCount, lessThan(180 * 7 * 3));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.preparedRanges.length, lessThanOrEqualTo(3));
      expect(engine.spoken, 1);
      expect(controller.hasCompleteDocumentSnapshot, isFalse);
      expect(await controller.exportAudioToPath('/unused.wav'), isNull);
      expect(engine.exports, 0);
      expect(controller.statusMessage, contains('complete document snapshot'));
      await controller.pausePlayback();
    },
  );
}

class _StartupEngine implements TtsEngine {
  final started = Completer<void>();
  final barrier = Completer<void>();
  final speech = Completer<void>();
  var attempts = 0;
  var spoken = 0;
  Completer<void>? pauseHold;
  @override
  Future<void> initialize() async {
    if (++attempts == 1) {
      started.complete();
      await barrier.future;
    }
  }

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
  Future<void> pause() async {
    await pauseHold?.future;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    spoken++;
    if (!speech.isCompleted) speech.complete();
  }

  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ExportProbe extends _StartupEngine implements AudioExportCapable {
  var exports = 0;
  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    exports++;
    throw StateError('A partial source must not reach the exporter.');
  }
}

class _PageBarrier extends PdfrxPdfTextExtractor {
  final secondStarted = Completer<void>();
  final release = Completer<void>();
  var drained = false;
  @override
  Stream<PdfTextExtractionPage> streamPages({
    required String fileName,
    String? sourcePath,
    Uint8List? bytes,
  }) async* {
    try {
      yield const PdfTextExtractionPage(pageIndex: 0, fullText: 'First page.');
      secondStarted.complete();
      await release.future;
      yield const PdfTextExtractionPage(pageIndex: 1, fullText: 'Second page.');
    } finally {
      drained = true;
    }
  }
}
