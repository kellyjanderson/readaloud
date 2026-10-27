import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/reading_focus_state.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/reader_resume_state.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import 'package:read_aloud/src/models/spoken_selection.dart';
import 'package:read_aloud/src/models/voice_preview_state.dart';
import 'package:read_aloud/src/models/voice_profile.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/document_preparation.dart';
import 'package:read_aloud/src/services/document_access_service.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_preparation_supervisor.dart';
import 'package:read_aloud/src/services/playback_instrumentation_service.dart';
import 'package:read_aloud/src/services/reader_preferences_service.dart';
import 'package:read_aloud/src/services/reader_document_repository.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'dart:io';
import 'package:read_aloud/src/services/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PlaybackInstrumentationService.instance.clear();
  });

  group('ReaderController playback', () {
    test('opens .radoc directly without source importer analysis', () async {
      final importer = _ControlledPreparationImporter();
      final controller = ReaderController(importer: importer);
      addTearDown(controller.dispose);
      await controller.initialize();

      final source = DocumentImportService().importPastedText(
        'Mara said, “We should leave now.”',
      );
      final serialized = const ReaderDocumentSerializationService()
          .serializeToJsonString(source);
      final picker = _ControlledPicker();
      FilePicker.platform = picker;
      final importing = controller.importDocument();
      picker.result.complete(
        FilePickerResult([
          PlatformFile(
            name: 'prepared.radoc',
            size: utf8.encode(serialized).length,
            bytes: Uint8List.fromList(utf8.encode(serialized)),
          ),
        ]),
      );
      await importing;

      expect(importer.results, isEmpty);
      expect(
        controller.document.displayDocument.documentId,
        source.displayDocument.documentId,
      );
      expect(
        controller.document.baseSpeechAnnotations.toJson(),
        source.baseSpeechAnnotations.toJson(),
      );
      expect(
        const ReaderDocumentSerializationService().serializeToJsonString(
          controller.document,
        ),
        serialized,
      );
      expect(controller.isPreparationComplete, isTrue);
      expect(controller.hasCompleteDocumentSnapshot, isTrue);
    });

    test('cancels .radoc replacement while engine stop is pending', () async {
      final engine = _BarrierStopTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.importPastedText('Keep the current document.');

      final replacement = DocumentImportService().importPastedText(
        'This prepared replacement must not commit.',
      );
      final serialized = const ReaderDocumentSerializationService()
          .serializeToJsonString(replacement);
      final bytes = Uint8List.fromList(utf8.encode(serialized));
      final picker = _ControlledPicker();
      FilePicker.platform = picker;
      engine.holdNext = true;
      final importing = controller.importDocument();
      picker.result.complete(
        FilePickerResult([
          PlatformFile(
            name: 'replacement.radoc',
            size: bytes.length,
            bytes: bytes,
          ),
        ]),
      );
      await engine.stopped.future;

      await controller.cancelDocumentPreparation();
      expect(controller.document.speakableText, 'Keep the current document.');

      engine.release.complete();
      await importing;
      expect(controller.document.speakableText, 'Keep the current document.');
      expect(
        controller.document.displayDocument.documentId,
        isNot(replacement.displayDocument.documentId),
      );
    });

    test('opens legacy radoc v1 without source importer analysis', () async {
      final importer = _ControlledPreparationImporter();
      final controller = ReaderController(importer: importer);
      addTearDown(controller.dispose);
      await controller.initialize();

      final source = DocumentImportService().importPastedText(
        'Legacy prepared document with preserved direction.',
      );
      final envelope =
          jsonDecode(
                const ReaderDocumentSerializationService()
                    .serializeToJsonString(source),
              )
              as Map<String, dynamic>;
      envelope['formatVersion'] = 'radoc-v1';
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
      final picker = _ControlledPicker();
      FilePicker.platform = picker;
      final importing = controller.importDocument();
      picker.result.complete(
        FilePickerResult([
          PlatformFile(name: 'legacy.radoc', size: bytes.length, bytes: bytes),
        ]),
      );
      await importing;

      expect(importer.results, isEmpty);
      expect(
        controller.document.displayDocument.documentId,
        source.displayDocument.documentId,
      );
      expect(controller.document.speakableText, source.speakableText);
    });

    test('refuses malformed .radoc with an actionable status', () async {
      final importer = _ControlledPreparationImporter();
      final controller = ReaderController(importer: importer);
      addTearDown(controller.dispose);
      await controller.initialize();

      final picker = _ControlledPicker();
      FilePicker.platform = picker;
      final importing = controller.importDocument();
      picker.result.complete(
        FilePickerResult([
          PlatformFile(
            name: 'broken.radoc',
            size: 2,
            bytes: Uint8List.fromList([0xff, 0x00]),
          ),
        ]),
      );
      await importing;

      expect(importer.results, isEmpty);
      expect(controller.statusMessage, contains('malformed'));
      expect(controller.statusMessage, contains('Re-export'));
    });

    test(
      'radoc voice choices restore into fresh preferences and malformed choices mutate nothing',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'radoc-voice-restore-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final document = DocumentImportService().importPastedText(
          'John said, "Hello." He smiled.',
        );
        const codec = ReaderDocumentSerializationService();
        final output = await codec.writeToFile(
          document: document,
          outputPath: '${directory.path}/book.radoc',
          userVoiceAssignments: {'cast_narrator': 'am_michael'},
        );
        SharedPreferences.setMockInitialValues({});
        final engine = _FakeTtsEngine(voices: _multiVoiceTestVoices);
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.importFilePaths([output.path]);
        expect(
          controller.document.displayDocument.documentId,
          document.displayDocument.documentId,
        );
        expect(
          controller.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'am_michael',
        );
        final stored = await ReaderPreferencesService().load();
        expect(
          stored.storedDocumentCastVoiceAssignments[controller
              .sessionDocumentId]?['cast_narrator'],
          'am_michael',
        );
        await controller.assignVoiceToCast('cast_narrator', 'af_bella');
        await controller.importFilePaths([output.path]);
        expect(
          controller.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'af_bella',
        );
        final before = await ReaderPreferencesService().load();
        final malformed =
            jsonDecode(await output.readAsString()) as Map<String, dynamic>;
        malformed['userVoiceAssignments'] = {'cast_narrator': 42};
        final invalid = await File(
          '${directory.path}/invalid.radoc',
        ).writeAsString(jsonEncode(malformed));
        await controller.importFilePaths([invalid.path]);
        expect(controller.statusMessage, contains('malformed'));
        expect(
          controller.document.displayDocument.documentId,
          document.displayDocument.documentId,
        );
        expect(
          controller.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'af_bella',
        );
        expect(
          (await ReaderPreferencesService().load())
              .storedDocumentCastVoiceAssignments,
          before.storedDocumentCastVoiceAssignments,
        );
        await controller.shutdownPreparation();
      },
    );

    test(
      'callback byte intake is admitted before acquisition and skips cache identity',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-byte-cache-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final engine = _FakeTtsEngine();
        final repository = ReaderDocumentRepository(directory.path);
        final supervisor = _ObservedRepositoryPreparationSupervisor(repository);
        final controller = ReaderController(
          preparationSupervisor: supervisor,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final text = _cacheProse();
        final file = _ByteBarrierXFile('captured.txt');
        final importing = controller.importDroppedFiles([file]);
        await file.started.future;
        expect(supervisor.activeCount, 1);
        expect(supervisor.lastRequest?.sourceRevision, isNull);
        expect(supervisor.lastRequest?.sourcePath, isNull);
        file.bytes.complete(Uint8List.fromList(utf8.encode(text)));
        await importing;
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        final repeatedFile = _ByteBarrierXFile('captured.txt');
        final repeatedImport = controller.importDroppedFiles([repeatedFile]);
        await repeatedFile.started.future;
        expect(supervisor.activeCount, 1);
        repeatedFile.bytes.complete(Uint8List.fromList(utf8.encode(text)));
        await repeatedImport;
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(
          await directory
              .list(recursive: true)
              .where((entry) => entry.path.endsWith('/manifest.json'))
              .toList(),
          isEmpty,
        );
        await controller.shutdownPreparation();
      },
    );

    test('direct immutable text intake remains cacheable', () async {
      final directory = await Directory.systemTemp.createTemp(
        'controller-text-cache-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final engine = _FakeTtsEngine();
      final controller = ReaderController(
        documentRepository: ReaderDocumentRepository(directory.path),
        ttsEngine: engine,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final text = _cacheProse();
      await controller.importPastedText(text);
      expect(_words(await _consumeRanges(controller, engine)), _words(text));
      final manifests = await directory
          .list(recursive: true)
          .where((entry) => entry.path.endsWith('/manifest.json'))
          .toList();
      expect(manifests, hasLength(1));
      final envelope =
          jsonDecode(await File(manifests.single.path).readAsString()) as Map;
      final manifest = jsonDecode(envelope['payload'] as String) as Map;
      expect(manifest['complete'], isTrue);
      expect(manifest['sourceRevision'], contains(':pastedText:null:'));
      await controller.importPastedText(text);
      expect(_words(await _consumeRanges(controller, engine)), _words(text));
      await controller.shutdownPreparation();
    });

    test(
      'picker captured bytes create and warm-replay the repository cache',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-picker-byte-cache-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = _CountingReaderDocumentRepository(directory.path);
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          documentRepository: repository,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final text = _cacheProse();
        final bytes = Uint8List.fromList(utf8.encode(text));

        final firstPicker = _ControlledPicker();
        FilePicker.platform = firstPicker;
        final firstImport = controller.importDocument();
        firstPicker.result.complete(
          FilePickerResult([
            PlatformFile(
              name: 'captured.txt',
              size: bytes.length,
              bytes: bytes,
            ),
          ]),
        );
        await firstImport;
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(repository.beginCalls, 1);

        final manifests = await directory
            .list(recursive: true)
            .where((entry) => entry.path.endsWith('/manifest.json'))
            .toList();
        expect(manifests, hasLength(1));
        final envelope =
            jsonDecode(await File(manifests.single.path).readAsString()) as Map;
        final manifest = jsonDecode(envelope['payload'] as String) as Map;
        expect(manifest['complete'], isTrue);
        expect(manifest['sourceRevision'], contains(':bytes:"captured.txt":'));

        final secondPicker = _ControlledPicker();
        FilePicker.platform = secondPicker;
        final secondImport = controller.importDocument();
        secondPicker.result.complete(
          FilePickerResult([
            PlatformFile(
              name: 'captured.txt',
              size: bytes.length,
              bytes: bytes,
            ),
          ]),
        );
        await secondImport;
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(repository.beginCalls, 1);
        await controller.shutdownPreparation();
      },
    );

    test(
      'cancel and replacement during manifest lookup reject its stale success',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-held-cache-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = _HeldOpenRepository(directory.path);
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          documentRepository: repository,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final importing = controller.importPastedText(_cacheProse());
        await repository.started.future;
        await controller.cancelDocumentPreparation();
        await controller.importPastedText('Current replacement.');
        final currentId = controller.sessionDocumentId;
        repository.release.complete();
        await importing;
        expect(controller.document.speakableText, 'Current replacement.');
        expect(controller.sessionDocumentId, currentId);
        expect(controller.documentIdentityRedirects, isEmpty);
        expect(controller.canRetryDocumentPreparation, isFalse);
        expect(
          await _consumeRanges(controller, engine),
          'Current replacement.',
        );
        await controller.shutdownPreparation();
      },
    );
    test(
      'repository cold checkpoint and warm replay preserve exact ranges and canonical choices',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-radoc-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = ReaderDocumentRepository(directory.path);
        final text = _cacheProse();
        final canonical = 'doc_acquired_${sha256.convert(utf8.encode(text))}';
        SharedPreferences.setMockInitialValues({
          'reader.storedDocumentCastVoiceAssignments': jsonEncode({
            canonical: {'cast_narrator': 'am_michael'},
          }),
        });
        final cold = _RecordingPreparationSupervisor(repository);
        final engine = _FakeTtsEngine(voices: _multiVoiceTestVoices);
        final controller = ReaderController(
          preparationSupervisor: cold,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.importPastedText(text);
        expect(controller.isPreparationComplete, isFalse);
        expect(controller.hasCompleteDocumentSnapshot, isFalse);
        final provisional = controller.sessionDocumentId;
        await controller.assignVoiceToCast('cast_narrator', 'af_bella');
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(controller.sessionDocumentId, canonical);
        expect(
          controller.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'af_bella',
        );
        expect(controller.documentIdentityRedirects[provisional], canonical);
        final cache = await repository.open(
          sourceKey: cold.cacheKeys.single!,
          sourceRevision: cold.requests.single.sourceRevision!,
        );
        expect(cache!.isComplete, isTrue);
        expect(cache.rangeCount, greaterThan(3));
        expect(controller.hasCompleteDocumentSnapshot, isTrue);
        final migrated = await ReaderPreferencesService().load();
        expect(
          migrated
              .storedDocumentCastVoiceAssignments[canonical]?['cast_narrator'],
          'af_bella',
        );
        // Deliberately retain the old provisional assignment while editing the
        // canonical one. Reopen must not let the old key overwrite this choice.
        await controller.assignVoiceToCast('cast_narrator', 'am_michael');
        final stored = await ReaderPreferencesService().load();
        expect(
          stored
              .storedDocumentCastVoiceAssignments[provisional]?['cast_narrator'],
          'af_bella',
        );
        expect(
          stored
              .storedDocumentCastVoiceAssignments[canonical]?['cast_narrator'],
          'am_michael',
        );
        await controller.shutdownPreparation();

        final warm = _RecordingPreparationSupervisor(repository);
        final warmEngine = _FakeTtsEngine(voices: _multiVoiceTestVoices);
        final reopened = ReaderController(
          preparationSupervisor: warm,
          ttsEngine: warmEngine,
        );
        addTearDown(reopened.dispose);
        await reopened.initialize();
        await reopened.importPastedText(text);
        expect(reopened.isPreparationComplete, isFalse);
        expect(reopened.sessionDocumentId, canonical);
        expect(
          reopened.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'am_michael',
        );
        expect(
          _words(await _consumeRanges(reopened, warmEngine)),
          _words(text),
        );
        expect(warm.results.single.workerName, 'prepared-range-cache');
        expect(
          warm.requests.single.sourceRevision,
          cold.requests.single.sourceRevision,
        );
        expect(
          reopened.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'am_michael',
        );
        final after = await ReaderPreferencesService().load();
        expect(
          after.storedDocumentCastVoiceAssignments[canonical]?['cast_narrator'],
          'am_michael',
        );
        await reopened.shutdownPreparation();
      },
    );

    test(
      'corrupt later cached range fails after valid prefix and retry rebuilds exact source',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-corrupt-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = ReaderDocumentRepository(directory.path);
        final text = _cacheProse();
        final source = _RecordingPreparationSupervisor(repository);
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          preparationSupervisor: source,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.importPastedText(text);
        await _consumeRanges(controller, engine);
        final cache = await repository.open(
          sourceKey: source.cacheKeys.single!,
          sourceRevision: source.requests.single.sourceRevision!,
        );
        final rangeFiles = await Directory(
          cache!.path,
        ).list().where((file) => file.path.endsWith('.json')).toList();
        expect(rangeFiles.length, cache.rangeCount);
        rangeFiles.sort((a, b) => a.path.compareTo(b.path));
        await File(rangeFiles.last.path).writeAsString('corrupt later range');
        await controller.importPastedText(text);
        expect(controller.document.speakableText, isNotEmpty);
        await expectLater(_consumeRanges(controller, engine), throwsStateError);
        expect(controller.isPreparationComplete, isFalse);
        expect(controller.hasCompleteDocumentSnapshot, isFalse);
        expect(controller.canRetryDocumentPreparation, isTrue);
        expect(
          await controller.exportAudioToPath('${directory.path}/partial.wav'),
          isNull,
        );
        expect(
          await repository.open(
            sourceKey: source.cacheKeys.first!,
            sourceRevision: source.requests.first.sourceRevision!,
          ),
          isNull,
        );
        await controller.retryDocumentPreparation();
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(controller.isPreparationComplete, isTrue);
        expect(controller.canRetryDocumentPreparation, isFalse);
        expect(source.results.last.workerName, isNot('prepared-range-cache'));
        await controller.shutdownPreparation();
      },
    );

    test(
      'repository cancellation leaves partial checkpoint and replacement rejects stale migration',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-cancel-cache-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = ReaderDocumentRepository(directory.path);
        final source = _RecordingPreparationSupervisor(repository);
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          preparationSupervisor: source,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final text = _cacheProse();
        await controller.importPastedText(text);
        final oldRequest = source.requests.single;
        final oldId = controller.sessionDocumentId;
        await controller.cancelDocumentPreparation();
        expect(controller.canRetryDocumentPreparation, isTrue);
        await controller.importPastedText('Replacement source.');
        final replacement = controller.sessionDocumentId;
        await source.migrationCallbacks.first!(
          DocumentIdentityMigration(
            ownerId: oldRequest.ownerId,
            documentRevision: oldRequest.revision,
            sourceRevision: oldRequest.effectiveSourceRevision,
            watchSession: oldRequest.watchSession ?? 0,
            provisionalDocumentId: oldId,
            canonicalDocumentId: 'obsolete-canonical',
            integrityBasis: DocumentIdentityIntegrityBasis.completeSourceBytes,
          ),
        );
        expect(controller.sessionDocumentId, replacement);
        expect(controller.documentIdentityRedirects, isNot(contains(oldId)));
        await _consumeRanges(controller, engine);
        final partial = await repository.open(
          sourceKey: source.cacheKeys.first!,
          sourceRevision: oldRequest.sourceRevision!,
        );
        expect(partial!.isComplete, isFalse);
        await controller.importPastedText(text);
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(source.results.last.workerName, isNot('prepared-range-cache'));
        await controller.shutdownPreparation();
      },
    );

    test(
      'stable file-backed intake warms without repeated source analysis and stale edits miss',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-file-cache-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final source = _RecordingPreparationSupervisor(
          ReaderDocumentRepository('${directory.path}/cache'),
        );
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          preparationSupervisor: source,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final text = _cacheProse();
        final file = await File(
          '${directory.path}/book.txt',
        ).writeAsString(text);
        await controller.importFilePaths([file.path]);
        expect(
          source.requests.single.sourceRevision,
          startsWith('file-stat-v2:'),
        );
        expect(source.cacheKeys.single, source.requests.single.sourceRevision);
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(
          controller.sessionDocumentId,
          'doc_acquired_${sha256.convert(utf8.encode(text))}',
        );
        final coldId = controller.sessionDocumentId;
        await controller.assignVoiceToCast('cast_narrator', 'af_bella');
        await controller.importFilePaths([file.path]);
        expect(controller.sessionDocumentId, coldId);
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(source.results.last.workerName, 'prepared-range-cache');
        expect(
          source.requests.last.sourceRevision,
          source.requests.first.sourceRevision,
        );
        final changed = text.replaceFirst('Ledger', 'Edited');
        final priorTime = (await file.stat()).modified;
        await file.writeAsString(changed);
        await file.setLastModified(priorTime);
        await controller.importFilePaths([file.path]);
        expect(
          _words(await _consumeRanges(controller, engine)),
          _words(changed),
        );
        expect(source.results.last.workerName, isNot('prepared-range-cache'));
        expect(
          source.requests.last.sourceRevision,
          isNot(source.requests.first.sourceRevision),
        );
        expect(await file.readAsString(), changed);
        await controller.shutdownPreparation();
      },
    );

    test(
      'complete checkpoint exports every ordered range as radoc and audio',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-range-export-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = ReaderDocumentRepository('${directory.path}/cache');
        final source = _RecordingPreparationSupervisor(repository);
        final engine = _ExportTtsEngine();
        final controller = ReaderController(
          preparationSupervisor: source,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final text = _cacheProse();
        await controller.importPastedText(text);
        expect(
          await controller.exportDocumentToPath(
            '${directory.path}/partial.radoc',
          ),
          isNull,
        );
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        engine.emitStart();
        expect(controller.hasCompleteDocumentSnapshot, isTrue);
        final canonical = controller.sessionDocumentId;
        final output = await controller.exportDocumentToPath(
          '${directory.path}/book.radoc',
        );
        expect(output, isNotNull);
        final restored = const ReaderDocumentSerializationService()
            .deserializeFromJsonString(await output!.readAsString());
        expect(_words(restored.speakableText), _words(text));
        expect(restored.displayDocument.documentId, canonical);
        expect(
          restored.speechDocument.segments.last.normalizedText,
          contains('marker999'),
        );
        final audio = await controller.exportAudioToPath(
          '${directory.path}/book.wav',
        );
        expect(audio, isNotNull, reason: controller.statusMessage);
        expect(_words(engine.exported!.text), _words(text));
        expect(
          engine.exported!.speechDocument!.totalWordCount,
          _words(text).length,
        );
        expect(
          engine
              .exported!
              .planningContext!
              .realization
              .speechDocument
              .segments
              .last
              .normalizedText,
          contains('marker999'),
        );
        await controller.assignVoiceToCast('cast_narrator', 'af_bella');
        expect(await controller.exportDocumentToPath(output.path), isNotNull);
        await controller.importFilePaths([output.path]);
        expect(controller.document.displayDocument.documentId, canonical);
        expect(_words(controller.document.speakableText), _words(text));
        expect(source.requests, hasLength(1));
        expect(
          controller.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'af_bella',
        );
        await controller.shutdownPreparation();
        SharedPreferences.setMockInitialValues({});
        final reopenSource = _RecordingPreparationSupervisor(repository);
        final reopened = ReaderController(
          preparationSupervisor: reopenSource,
          ttsEngine: _FakeTtsEngine(voices: _multiVoiceTestVoices),
        );
        addTearDown(reopened.dispose);
        await reopened.initialize();
        await reopened.importFilePaths([output.path]);
        expect(reopenSource.requests, isEmpty);
        expect(_words(reopened.document.speakableText), _words(text));
        expect(reopened.sessionDocumentId, canonical);
        expect(
          reopened.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'af_bella',
        );
        await reopened.shutdownPreparation();
      },
    );
    test(
      'damaged checkpoint export exposes preparation retry and retains source and choices',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-export-damaged-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = ReaderDocumentRepository('${directory.path}/cache');
        final source = _RecordingPreparationSupervisor(repository);
        final engine = _FakeTtsEngine(voices: _multiVoiceTestVoices);
        final controller = ReaderController(
          preparationSupervisor: source,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final text = _cacheProse();
        await controller.importPastedText(text);
        await _consumeRanges(controller, engine);
        await controller.assignVoiceToCast('cast_narrator', 'af_bella');
        final cache = (await repository.open(
          sourceKey: source.cacheKeys.single!,
          sourceRevision: source.requests.single.sourceRevision!,
        ))!;
        await File(
          '${cache.path}/${cache.rangeCount}.json',
        ).writeAsString('corrupt');
        final output = await File(
          '${directory.path}/book.radoc',
        ).writeAsString('prior export');
        expect(await controller.exportDocumentToPath(output.path), isNull);
        expect(controller.canRetryDocumentPreparation, isTrue);
        expect(controller.hasCompleteDocumentSnapshot, isFalse);
        expect(await output.readAsString(), 'prior export');
        await controller.retryDocumentPreparation();
        expect(_words(await _consumeRanges(controller, engine)), _words(text));
        expect(source.results.last.workerName, isNot('prepared-range-cache'));
        expect(
          controller.castVoiceAssignments!
              .forCastId('cast_narrator')!
              .effectiveVoiceId,
          'af_bella',
        );
        expect(await controller.exportDocumentToPath(output.path), isNotNull);
        await controller.shutdownPreparation();
      },
    );

    test(
      'replacement cancels checkpoint export before publication and preserves prior output',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'controller-export-cancel-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = _HeldExportRepository('${directory.path}/cache');
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          documentRepository: repository,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.importPastedText(_cacheProse());
        await _consumeRanges(controller, engine);
        final output = await File(
          '${directory.path}/book.radoc',
        ).writeAsString('prior export');
        repository.holdNextOpen = true;
        final exporting = controller.exportDocumentToPath(output.path);
        await repository.started.future;
        expect(
          await controller.exportDocumentToPath(
            '${directory.path}/overlap.radoc',
          ),
          isNull,
        );
        await controller.importPastedText('New current document.');
        repository.release.complete();
        expect(await exporting, isNull);
        expect(await output.readAsString(), 'prior export');
        expect(controller.document.speakableText, 'New current document.');
        expect(await File('${directory.path}/overlap.radoc').exists(), isFalse);
        await controller.shutdownPreparation();
      },
    );

    test(
      'real large-source parser feeds every bounded range once before EOF',
      () async {
        final sourceText = List.generate(
          1200,
          (index) => 'Ledger item $index ends with marker$index.',
        ).join('\n');
        expect(sourceText.length, greaterThan(8192 * 3));
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          ttsEngine: engine,
          enablePlatformIntakeChannels: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.importPastedText(sourceText);
        expect(
          controller.isPreparationComplete,
          isFalse,
          reason:
              'first fragment must be usable before bounded producer reaches EOF',
        );
        await controller.startPlayback();
        var request = engine.lastSpeakRequest!;
        final cancelled = Completer<void>();
        final emittedText = <String>[];
        var nextWord = 0;
        var sequences = 0;
        while (true) {
          expect(request.rangeSequence, ++sequences);
          expect(request.sourceWordOffset, nextWord);
          expect(controller.preparedRanges.length, lessThanOrEqualTo(3));
          emittedText.add(request.text);
          nextWord += request.speechDocument!.totalWordCount;
          request.onRangeActive?.call();
          final next = await request.continuation!
              .next(request.rangeSequence, cancelled.future)
              .timeout(const Duration(seconds: 30));
          if (next == null) break;
          request = next;
        }
        List<String> words(String text) => RegExp(
          r'\S+',
        ).allMatches(text).map((match) => match.group(0)!).toList();
        expect(sequences, greaterThan(3));
        expect(
          words(emittedText.join(' ')),
          words(sourceText),
          reason:
              'distinct marker words expose source boundary omissions/repeats',
        );
        expect(controller.isPreparationComplete, isTrue);
        expect(
          engine.speakCallCount,
          1,
          reason: 'continuation stays in the existing playback request',
        );
        await controller.shutdownPreparation();
      },
    );
    test(
      'early explicit intake waits for preferences but not speech startup',
      () async {
        final preferences = _HeldPreferences();
        final engine = _InitBarrierEngine();
        final controller = ReaderController(
          preferencesService: preferences,
          ttsEngine: engine,
          enablePlatformIntakeChannels: false,
        );
        addTearDown(controller.dispose);
        final initializing = controller.initialize();
        var imported = false;
        final importing = controller
            .loadDocument(
              DocumentImportService().importPastedText('Explicit document.'),
            )
            .then((_) => imported = true);
        await Future<void>.delayed(Duration.zero);
        expect(imported, isFalse);
        preferences.ready.complete();
        await controller.intakeReady;
        await importing;
        expect(controller.document.speakableText, 'Explicit document.');
        expect(controller.isInitializing, isTrue);
        engine.ready.complete();
        await initializing;
      },
    );
    test(
      'intake readiness and document import do not await speech startup',
      () async {
        final engine = _InitBarrierEngine();
        final controller = ReaderController(
          ttsEngine: engine,
          enablePlatformIntakeChannels: false,
        );
        addTearDown(controller.dispose);
        final initializing = controller.initialize();
        await controller.intakeReady;
        expect(controller.isInitializing, isTrue);
        await controller.loadDocument(ReaderDocument.sample());
        expect(controller.isDocumentPrepared, isTrue);
        expect(controller.canRetryDocumentPreparation, isFalse);
        engine.ready.complete();
        await initializing;
      },
    );
    test(
      'public preparation cancellation preserves display and retries exact intake',
      () async {
        final importer = _ControlledPreparationImporter();
        final controller = ReaderController(
          importer: importer,
          ttsEngine: _FakeTtsEngine(),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final pending = controller.importDroppedFiles([
          XFile.fromData(
            Uint8List.fromList(utf8.encode('Retry source.')),
            name: 'retry.txt',
          ),
        ]);
        await importer.started(0);
        final prior = controller.document;
        await controller.cancelDocumentPreparation();
        await pending;
        expect(controller.document, same(prior));
        expect(controller.isImporting, isFalse);
        expect(controller.canRetryDocumentPreparation, isTrue);
        importer.results[0].completeError(StateError('obsolete failure'));
        final retry = controller.retryDocumentPreparation();
        await importer.started(1);
        expect(controller.canRetryDocumentPreparation, isFalse);
        expect(importer.payloads, ['Retry source.', 'Retry source.']);
        importer.results[1].complete(
          DocumentImportService().importPastedText('Retry source.'),
        );
        await retry;
        expect(controller.document.speakableText, 'Retry source.');
        expect(controller.canRetryDocumentPreparation, isFalse);
      },
    );
    test(
      'range continuation preserves ordering, active display, EOF and bounded credit',
      () async {
        final source = _RangePreparationSupervisor();
        final engine = _FakeTtsEngine();
        final controller = ReaderController(
          preparationSupervisor: source,
          ttsEngine: engine,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final importing = controller.importPastedText('source');
        await source.started.future;
        await source.publish('First source words.');
        await importing;
        await controller.startPlayback();
        final first = engine.lastSpeakRequest!;
        final cancellation = Completer<void>();
        expect(first.rangeSequence, 1);
        await source.publish('Second distinct words.');
        final second = (await first.continuation!.next(
          1,
          cancellation.future,
        ))!;
        expect(controller.document.speakableText, 'First source words.');
        expect(second.sourceWordOffset, 3);
        expect(second.rangeSequence, 2);
        await expectLater(
          first.continuation!.next(1, cancellation.future),
          throwsStateError,
        );
        final thirdPublication = source.publish('Third final words.');
        expect(controller.preparedRanges.length, 3);
        second.onRangeActive!();
        await thirdPublication;
        expect(controller.document.speakableText, 'Second distinct words.');
        expect(controller.preparedRanges.map((r) => r.sequence), [2, 3]);
        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 0,
            endOffset: 6,
            word: 'Second',
            documentId: first.documentId,
            wordStartIndex: 3,
            wordEndIndex: 4,
          ),
        );
        expect(controller.currentWordIndex, 1);
        final third = (await second.continuation!.next(
          2,
          cancellation.future,
        ))!;
        expect(third.sourceWordOffset, 6);
        source.finish();
        expect(await third.continuation!.next(3, cancellation.future), isNull);
        await controller.pausePlayback();
        await controller.startPlayback();
        expect(engine.lastSpeakRequest!.rangeSequence, 2);
        expect(engine.lastSpeakRequest!.sourceWordOffset, 3);
      },
    );
    for (final terminal in ['failure', 'cancel', 'replacement']) {
      test(
        'range demand rejects $terminal without false EOF or stale display',
        () async {
          final source = _RangePreparationSupervisor();
          final engine = _FakeTtsEngine();
          final controller = ReaderController(
            preparationSupervisor: source,
            ttsEngine: engine,
          );
          addTearDown(controller.dispose);
          await controller.initialize();
          final importing = controller.importPastedText('source');
          await source.started.future;
          await source.publish('First source words.');
          await importing;
          await controller.startPlayback();
          final request = engine.lastSpeakRequest!;
          final cancellation = Completer<void>();
          final next = request.continuation!.next(1, cancellation.future);
          final assertion = expectLater(next, throwsA(anything));
          if (terminal == 'failure') {
            source.finish(error: 'injected source failure');
          } else if (terminal == 'cancel') {
            cancellation.complete();
          } else {
            await controller.loadDocument(
              DocumentImportService().importPastedText('Replacement.'),
            );
          }
          await assertion;
          if (terminal == 'failure') {
            expect(controller.canRetryDocumentPreparation, isTrue);
          }
          expect(engine.speakCallCount, 1);
        },
      );
    }
    for (final fails in [false, true]) {
      test(
        'resource intent during import converges after stale ${fails ? 'failure' : 'success'}',
        () async {
          final engine = _ResourceBarrierEngine();
          final controller = ReaderController(ttsEngine: engine);
          addTearDown(controller.dispose);
          await controller.initialize();
          final loading = controller.loadDocument(ReaderDocument.sample());
          await loading;
          final playing = controller.startPlayback();
          await engine.started.future;
          await controller.setMultiVoiceEnabled(
            !controller.isMultiVoiceEnabled,
          );
          engine.ready = true;
          if (fails) {
            engine.barrier.completeError(StateError('stale resource failure'));
          } else {
            engine.barrier.complete(const []);
          }
          await playing;
          expect(engine.preparations, 2);
          expect(controller.isDocumentPrepared, isTrue);
          expect(controller.isResourcesReady, isTrue);
          await controller.startPlayback();
          expect(controller.isDocumentPrepared, isTrue);
        },
      );
    }
    for (final fails in [false, true]) {
      test(
        'prepared range remains ready while playback waits for resource ${fails ? 'failure' : 'success'}',
        () async {
          final engine = _ResourceBarrierEngine();
          final controller = ReaderController(ttsEngine: engine);
          addTearDown(controller.dispose);
          await controller.initialize();
          final loading = controller.loadDocument(ReaderDocument.sample());
          await loading;
          final playing = controller.startPlayback();
          await engine.started.future;
          expect(controller.isDisplayReady, isTrue);
          expect(controller.isDocumentPrepared, isTrue);
          expect(controller.isResourcesReady, isFalse);
          if (fails) {
            engine.barrier.completeError(StateError('corrupted voice asset'));
          } else {
            engine.ready = true;
            engine.barrier.complete(const []);
          }
          await playing;
          expect(controller.isDocumentPrepared, isTrue);
          expect(controller.isResourcesReady, !fails);
          if (!fails) {
            expect(controller.resourceBindings, isNotEmpty);
            expect(controller.resolvedResourceBindings, isNotEmpty);
            final snapshot = controller.resolvedResourceBindings.first.toMap();
            expect(
              snapshot['documentId'],
              ReaderDocument.sample().displayDocument.documentId,
            );
            expect(snapshot['decisionKind'], isNotNull);
            await controller.setMultiVoiceEnabled(
              !controller.isMultiVoiceEnabled,
            );
            // Pending intent preserves the prepared effective resource context
            // until explicit Apply or the next Play validates replacement.
            expect(controller.isResourcesReady, isTrue);
            expect(controller.resourceBindings, isNotEmpty);
            expect(controller.voiceAssignmentState.hasPending, isTrue);
          }
          if (fails) {
            expect(controller.statusMessage, contains('corrupted voice asset'));
          }
        },
      );
    }
    for (final mode in ['cancel', 'invalid', 'error', 'superseded']) {
      test(
        'Live Feed picker $mode owns loading cleanup after replacing an import',
        () async {
          final picker = _ControlledPicker();
          FilePicker.platform = picker;
          final importer = _ControlledPreparationImporter();
          final controller = ReaderController(
            importer: importer,
            ttsEngine: _FakeTtsEngine(),
          );
          addTearDown(controller.dispose);
          await controller.initialize();
          final a = controller.importDroppedFiles([
            XFile.fromData(
              Uint8List.fromList(utf8.encode('Old.')),
              name: 'old.txt',
            ),
          ]);
          await importer.started(0);
          final picking = controller.pickAndStartLiveRead();
          await a;
          expect(controller.isImporting, isTrue);
          Future<void>? latest;
          if (mode == 'superseded') {
            latest = controller.importDroppedFiles([
              XFile.fromData(
                Uint8List.fromList(utf8.encode('Latest.')),
                name: 'latest.txt',
              ),
            ]);
          }
          switch (mode) {
            case 'error':
              picker.result.completeError(StateError('picker failed'));
            case 'invalid':
              picker.result.complete(
                FilePickerResult([PlatformFile(name: 'missing.txt', size: 0)]),
              );
            default:
              picker.result.complete(null);
          }
          await picking;
          if (mode == 'superseded') {
            expect(controller.isImporting, isTrue);
            expect(controller.statusMessage, isNull);
          } else {
            expect(controller.isImporting, isFalse);
            expect(controller.isCastProcessingVisible, isFalse);
            expect(controller.isDocumentPrepared, isTrue);
          }
          importer.results[0].completeError(
            StateError('old preparation failed'),
          );
          if (latest != null) {
            await importer.started(1);
            importer.results[1].complete(
              DocumentImportService().importPastedText('Latest.'),
            );
            await latest;
            expect(controller.document.speakableText, 'Latest.');
          }
          await controller.shutdownPreparation();
        },
      );
    }

    test('empty startup restore does not supersede an active import', () async {
      final importer = _ControlledPreparationImporter();
      final controller = ReaderController(
        importer: importer,
        ttsEngine: _FakeTtsEngine(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final pending = controller.importDroppedFiles([
        XFile.fromData(
          Uint8List.fromList(utf8.encode('Current.')),
          name: 'current.txt',
        ),
      ]);
      await importer.started(0);
      expect(await controller.restoreLastOpenedDocument(), isFalse);
      expect(controller.isImporting, isTrue);
      importer.results[0].complete(
        DocumentImportService().importPastedText('Current.'),
      );
      await pending;
      expect(controller.document.speakableText, 'Current.');
    });

    for (final cancelLive in [false, true]) {
      for (final failOld in [false, true]) {
        testWidgets(
          'two watched edits then ${cancelLive ? 'live cancellation' : 'replacement'} reject stale ${failOld ? 'failure' : 'success'} during playback',
          (tester) async {
            final directory = await tester.runAsync(
              () => Directory.systemTemp.createTemp('read-aloud-overlap'),
            );
            final file = File('${directory!.path}/live.txt');
            final events = StreamController<FileSystemEvent>(sync: true);
            final importer = _ControlledPreparationImporter();
            final supervisor = _ObservedPreparationSupervisor(importer);
            final engine = _OverlapResourceEngine();
            final controller = ReaderController(
              preparationSupervisor: supervisor,
              ttsEngine: engine,
            );
            addTearDown(() async {
              // Drain the non-cancellable test adapter even on assertion failure.
              for (final result in importer.results) {
                if (!result.isCompleted) {
                  result.complete(ReaderDocument.sample());
                }
              }
              await controller.shutdownPreparation();
              controller.dispose();
              await events.close();
              await directory.delete(recursive: true);
            });

            await IOOverrides.runWithIOOverrides(() async {
              await tester.runAsync(() async {
                await file.writeAsString('Original source words.');
                await controller.initialize();
                final connecting = controller.startLiveReadFromPath(file.path);
                await importer.started(0);
                importer.results[0].complete(
                  DocumentImportService().importPastedText(
                    'Original source words.',
                  ),
                );
                await connecting;
                await controller.startPlayback();
                engine.emitStart();
              });
              final original = controller.document;
              final originalRequest = engine.lastSpeakRequest!;
              final originalPreparations = List<String>.of(
                engine.preparedDocuments,
              );
              expect(controller.isPlaying, isTrue);
              expect(controller.resourceBindings, isNotEmpty);
              expect(events.hasListener, isTrue);

              await tester.runAsync(() => file.writeAsString('First edit.'));
              events.add(FileSystemModifyEvent(file.path, false, true));
              await tester.pump(const Duration(milliseconds: 250));
              await tester.runAsync(() => importer.started(1));
              expect(importer.payloads[1], 'First edit.');
              expect(supervisor.activeCount, 1);
              expect(controller.isImporting, isTrue);
              expect(originalRequest.isCurrent!(), isFalse);

              await tester.runAsync(() => file.writeAsString('Second edit.'));
              events.add(FileSystemModifyEvent(file.path, false, true));
              await tester.pump(const Duration(milliseconds: 250));
              await tester.runAsync(() => supervisor.admitted(2));
              expect(supervisor.activeCount, 1);
              expect(supervisor.pendingCount, 1);
              expect(
                supervisor.requests[2].revision,
                greaterThan(supervisor.requests[1].revision),
              );
              expect(
                supervisor.requests[2].watchSession,
                supervisor.requests[1].watchSession,
              );
              expect(controller.document, same(original));
              expect(controller.isCastProcessingVisible, isTrue);
              expect(controller.resourceBindings, isEmpty);
              expect(controller.isPlaying, isTrue);
              await tester.runAsync(controller.startPlayback);
              expect(engine.speakCallCount, 1);

              if (cancelLive) {
                await tester.runAsync(controller.stopLiveRead);
                expect(controller.isImporting, isFalse);
                expect(supervisor.pendingCount, 0);
                expect(controller.document, same(original));
              }
              late Future<void> replacing;
              await tester.runAsync(() async {
                replacing = controller.importDroppedFiles([
                  XFile.fromData(
                    Uint8List.fromList(utf8.encode('Replacement fresh words.')),
                    name: 'replacement.txt',
                  ),
                ]);
                await supervisor.admitted(3);
              });
              expect(controller.isLiveReadEnabled, isFalse);
              expect(events.hasListener, isFalse);
              expect(supervisor.pendingCount, 1);
              expect(controller.isImporting, isTrue);
              expect(controller.documentLoadStageLabel, contains('Preparing'));
              final replacementStatus = controller.statusMessage;

              // The cancelled first reload drains after the newer request owns
              // progress; the queued second edit must never acquire or publish.
              await tester.runAsync(() async {
                if (failOld) {
                  importer.results[1].completeError(
                    StateError('obsolete watched reload failure'),
                  );
                } else {
                  importer.results[1].complete(
                    DocumentImportService().importPastedText('First edit.'),
                  );
                }
                await importer.started(2);
              });
              expect(importer.payloads, [
                'Original source words.',
                'First edit.',
                'Replacement fresh words.',
              ]);
              expect(controller.document, same(original));
              expect(controller.isImporting, isTrue);
              expect(controller.isCastProcessingVisible, isTrue);
              expect(controller.statusMessage, replacementStatus);
              expect(engine.preparedDocuments, originalPreparations);

              await tester.runAsync(() async {
                importer.results[2].complete(
                  DocumentImportService().importPastedText(
                    'Replacement fresh words.',
                  ),
                );
                await replacing;
                await controller.startPlayback();
                engine.emitStart();
              });
              final replacementId =
                  controller.document.displayDocument.documentId;
              expect(replacementId, isNot(original.displayDocument.documentId));
              expect(
                controller.document.speakableText,
                'Replacement fresh words.',
              );
              expect(controller.isImporting, isFalse);
              expect(controller.isCastProcessingVisible, isFalse);
              expect(controller.isDocumentPrepared, isTrue);
              expect(controller.isResourcesReady, isTrue);
              expect(
                controller.resourceBindings.map((b) => b.documentId),
                everyElement(replacementId),
              );
              expect(
                engine.preparedDocuments.skip(originalPreparations.length),
                isNotEmpty,
              );
              expect(
                engine.preparedDocuments.skip(originalPreparations.length),
                everyElement(replacementId),
              );
              expect(engine.lastSpeakRequest!.documentId, replacementId);
              expect(engine.lastSpeakRequest!.isCurrent!(), isTrue);
              expect(engine.speakCallCount, 2);
              expect(supervisor.activeCount, 0);
              expect(supervisor.pendingCount, 0);

              void progress(ReaderDocument document, String chunkId) {
                engine.emitProgress(
                  TtsProgressUpdate(
                    startOffset: 12,
                    endOffset: 17,
                    word: 'fresh',
                    documentId: document.displayDocument.documentId,
                    chunkId: chunkId,
                    segmentId: document.speechDocument.segments.first.segmentId,
                    wordStartIndex: 1,
                    wordEndIndex: 2,
                    elapsedInChunk: const Duration(seconds: 1),
                    chunkAudioDuration: const Duration(seconds: 2),
                    voiceId: controller.selectedVoice!.id,
                    rate: controller.currentSpeed,
                  ),
                );
              }

              progress(controller.document, 'replacement-chunk');
              expect(controller.spokenSelection.hasSelection, isTrue);
              final word = controller.currentWordIndex;
              final selection = controller.spokenSelection;
              progress(original, 'obsolete-chunk');
              expect(controller.currentWordIndex, word);
              expect(controller.spokenSelection, same(selection));
              expect(controller.statusMessage, isNull);
              await tester.runAsync(controller.pausePlayback);
              await tester.runAsync(controller.shutdownPreparation);
              expect(supervisor.activeCount, 0);
              expect(supervisor.pendingCount, 0);
            }, _ControlledWatchOverrides(directory.path, events.stream));
          },
        );
      }
    }

    for (final failOld in [false, true]) {
      test(
        'superseded import ${failOld ? 'failure' : 'success'} cannot clear latest state',
        () async {
          final importer = _ControlledPreparationImporter();
          final engine = _FakeTtsEngine();
          final controller = ReaderController(
            importer: importer,
            ttsEngine: engine,
          );
          addTearDown(controller.dispose);
          await controller.initialize();
          final a = controller.importDroppedFiles([
            XFile.fromData(
              Uint8List.fromList(utf8.encode('First.')),
              name: 'a.txt',
            ),
          ]);
          await importer.started(0);
          final b = controller.importDroppedFiles([
            XFile.fromData(
              Uint8List.fromList(utf8.encode('Second.')),
              name: 'b.txt',
            ),
          ]);
          await a;
          expect(controller.isImporting, isTrue);
          expect(controller.isDocumentPrepared, isFalse);
          await controller.startPlayback();
          expect(engine.speakCallCount, 0);
          if (failOld) {
            importer.results[0].completeError(StateError('obsolete failure'));
          } else {
            importer.results[0].complete(
              DocumentImportService().importPastedText('First.'),
            );
          }
          await importer.started(1);
          expect(controller.isImporting, isTrue);
          expect(
            controller.statusMessage,
            contains('Preparing the requested reading range'),
          );
          importer.results[1].complete(
            DocumentImportService().importPastedText('Second.'),
          );
          await b;
          expect(controller.document.speakableText, 'Second.');
          expect(controller.isDocumentPrepared, isTrue);
          expect(controller.isImporting, isFalse);
        },
      );
    }

    test('revision is rechecked after an engine stop await', () async {
      final engine = _BarrierStopTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);
      await controller.initialize();
      engine.holdNext = true;
      final a = controller.importPastedText('First document.');
      await engine.stopped.future;
      await controller.importPastedText('Second document.');
      expect(controller.document.speakableText, 'Second document.');
      engine.release.complete();
      await a;
      expect(controller.document.speakableText, 'Second document.');
      expect(controller.isImporting, isFalse);
    });

    test(
      'stop live read cancels pending initial publication and watcher installation',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'read-aloud-live-cancel',
        );
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/fixture.txt');
        await file.writeAsString('Initial.');
        final importer = _ControlledPreparationImporter();
        final controller = ReaderController(
          importer: importer,
          ttsEngine: _FakeTtsEngine(),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final original = controller.document;
        final live = controller.startLiveReadFromPath(file.path);
        await importer.started(0);
        await controller.stopLiveRead();
        importer.results[0].complete(
          DocumentImportService().importPastedText('Obsolete.'),
        );
        await live;
        await controller.shutdownPreparation();
        expect(controller.document, same(original));
        expect(controller.isImporting, isFalse);
        await file.writeAsString('Must not reload.');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(importer.results, hasLength(1));
      },
    );

    test(
      'startup A/B/C rejects the original A start and dispatches only latest C',
      () async {
        final engine = _BarrierStartTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(() {
          engine.release();
          controller.dispose();
        });
        await controller.initialize();
        await controller.importPastedText('Alpha beta. Gamma delta.');
        await controller.selectVoiceById('af_heart');

        final startup = controller.startPlayback();
        await engine.started.future.timeout(const Duration(seconds: 5));
        expect(
          controller.playbackState,
          ReaderPlaybackPrimaryState.bufferingFirstChunk,
        );
        final originalRequest = engine.lastSpeakRequest!;
        expect(originalRequest.chunkPlan!.chunks.first.voiceId, 'af_heart');

        await controller.selectVoiceById('af_bella');
        await controller.selectVoiceById('am_michael');
        expect(controller.selectedVoice!.id, 'am_michael');
        expect(engine.speakCallCount, 1);
        expect(engine.lastSpeakRequest, same(originalRequest));

        engine.release();
        await startup.timeout(const Duration(seconds: 5));
        expect(controller.playbackState, ReaderPlaybackPrimaryState.playing);
        expect(originalRequest.chunkPlan!.chunks.first.voiceId, 'af_heart');
        expect(originalRequest.isCurrent!(), isFalse);
        expect(engine.speakCallCount, 2);
        expect(
          engine.lastSpeakRequest!.chunkPlan!.chunks.first.voiceId,
          'am_michael',
        );
        expect(
          controller.voiceAssignmentState.effectiveDefaultVoiceId,
          'am_michael',
        );
      },
    );

    test(
      'tracks primary playback state through buffering, playing, and completion',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText('Alpha beta. Gamma delta.');
        await controller.startPlayback();

        expect(
          controller.playbackState,
          ReaderPlaybackPrimaryState.bufferingFirstChunk,
        );
        expect(controller.statusMessage, isNull);

        engine.emitStart();
        expect(controller.playbackState, ReaderPlaybackPrimaryState.playing);

        final documentId = controller.document.displayDocument.documentId;
        final lastSegment = controller.document.speechDocument.segments.last;
        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 0,
            endOffset: controller.document.speakableText.length,
            word: 'delta',
            documentId: documentId,
            chunkId: 'chunk-complete',
            segmentId: lastSegment.segmentId,
            wordStartIndex: controller.document.wordCount - 1,
            wordEndIndex: controller.document.wordCount,
            elapsedInChunk: const Duration(seconds: 2),
            chunkAudioDuration: const Duration(seconds: 2),
            voiceId: controller.selectedVoice!.id,
            rate: controller.currentSpeed,
          ),
        );
        engine.emitComplete();

        expect(controller.playbackState, ReaderPlaybackPrimaryState.completed);
      },
    );

    test(
      'uses completed chunk records for timing and snaps jumps to segment starts',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          'Alpha beta. Gamma delta. Epsilon zeta.',
        );
        await controller.startPlayback();
        engine.emitStart();

        final documentId = controller.document.displayDocument.documentId;
        final segments = controller.document.speechDocument.segments;
        final voiceId = controller.selectedVoice!.id;

        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 0,
            endOffset: 10,
            word: 'beta',
            documentId: documentId,
            chunkId: 'chunk-1',
            segmentId: segments[0].segmentId,
            wordStartIndex: 0,
            wordEndIndex: 2,
            elapsedInChunk: const Duration(seconds: 2),
            chunkAudioDuration: const Duration(seconds: 2),
            voiceId: voiceId,
            rate: controller.currentSpeed,
            routeId: 'route_narration_open',
            castId: 'cast_narrator',
          ),
        );
        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 11,
            endOffset: 22,
            word: 'delta',
            documentId: documentId,
            chunkId: 'chunk-2',
            segmentId: segments[1].segmentId,
            wordStartIndex: 2,
            wordEndIndex: 4,
            elapsedInChunk: const Duration(seconds: 2),
            chunkAudioDuration: const Duration(seconds: 2),
            voiceId: voiceId,
            rate: controller.currentSpeed,
            routeId: 'route_dialogue_jennifer',
            castId: 'cast_character_jennifer',
            dialogueSpanId: 'dlg_s_1',
          ),
        );

        expect(controller.wordsPerSecond, closeTo(1.0, 0.001));
        expect(
          controller.spokenChunkRecords.any(
            (record) => record.chunkId == 'chunk-1' && record.completed,
          ),
          isTrue,
        );
        final dialogueRecord = controller.spokenChunkRecords.firstWhere(
          (record) => record.chunkId == 'chunk-2',
        );
        expect(dialogueRecord.routeId, 'route_dialogue_jennifer');
        expect(dialogueRecord.castId, 'cast_character_jennifer');
        expect(dialogueRecord.dialogueSpanId, 'dlg_s_1');
        expect(
          controller.spokenSelection.precision,
          SpokenSelectionPrecision.word,
        );
        expect(controller.spokenSelection.routeId, 'route_dialogue_jennifer');
        expect(controller.spokenSelection.castId, 'cast_character_jennifer');
        expect(controller.spokenSelection.dialogueSpanId, 'dlg_s_1');

        await controller.jumpBySeconds(-1);

        expect(controller.currentWordIndex, 2);
      },
    );

    test(
      'coalesces follower selection updates while keeping audio word position current',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          'Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu.',
        );
        await controller.startPlayback();
        engine.emitStart();

        final documentId = controller.document.displayDocument.documentId;
        final segmentId =
            controller.document.speechDocument.segments.first.segmentId;
        final voiceId = controller.selectedVoice!.id;

        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 0,
            endOffset: 5,
            word: 'Alpha',
            documentId: documentId,
            chunkId: 'chunk-1',
            segmentId: segmentId,
            wordStartIndex: 0,
            wordEndIndex: 1,
            elapsedInChunk: const Duration(milliseconds: 80),
            chunkAudioDuration: const Duration(seconds: 4),
            voiceId: voiceId,
            rate: controller.currentSpeed,
          ),
        );

        expect(controller.currentWordIndex, 1);
        expect(controller.spokenSelection.speechEndWordIndex, 1);

        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 6,
            endOffset: 10,
            word: 'beta',
            documentId: documentId,
            chunkId: 'chunk-1',
            segmentId: segmentId,
            wordStartIndex: 1,
            wordEndIndex: 2,
            elapsedInChunk: const Duration(milliseconds: 160),
            chunkAudioDuration: const Duration(seconds: 4),
            voiceId: voiceId,
            rate: controller.currentSpeed,
          ),
        );

        expect(controller.currentWordIndex, 2);
        expect(
          controller.spokenSelection.speechEndWordIndex,
          1,
          reason: 'Visible follower state should be allowed to lag briefly.',
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(controller.spokenSelection.speechEndWordIndex, 2);
      },
    );

    test(
      'hard-resynchronizes follower selection when drift grows too large',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          'one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen.',
        );
        await controller.startPlayback();
        engine.emitStart();

        final documentId = controller.document.displayDocument.documentId;
        final segmentId =
            controller.document.speechDocument.segments.first.segmentId;
        final voiceId = controller.selectedVoice!.id;

        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 0,
            endOffset: 3,
            word: 'one',
            documentId: documentId,
            chunkId: 'chunk-long',
            segmentId: segmentId,
            wordStartIndex: 0,
            wordEndIndex: 1,
            elapsedInChunk: const Duration(milliseconds: 100),
            chunkAudioDuration: const Duration(seconds: 6),
            voiceId: voiceId,
            rate: controller.currentSpeed,
          ),
        );

        expect(controller.spokenSelection.speechEndWordIndex, 1);

        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 48,
            endOffset: 62,
            word: 'twelve',
            documentId: documentId,
            chunkId: 'chunk-long',
            segmentId: segmentId,
            wordStartIndex: 11,
            wordEndIndex: 12,
            elapsedInChunk: const Duration(seconds: 3),
            chunkAudioDuration: const Duration(seconds: 6),
            voiceId: voiceId,
            rate: controller.currentSpeed,
          ),
        );

        expect(controller.currentWordIndex, 12);
        expect(
          controller.spokenSelection.speechEndWordIndex,
          12,
          reason: 'Large drift should force an immediate visible catch-up.',
        );
      },
    );

    test('records debug playback metrics with session attribution', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText('Alpha beta. Gamma delta.');
      final sessionId = controller.narrationState.sessionId;
      final documentId = controller.document.displayDocument.documentId;

      await controller.startPlayback();

      final metricsAfterPlay = PlaybackInstrumentationService.instance
          .snapshot();
      final positionMetric = metricsAfterPlay.firstWhere(
        (record) => record.metric == 'positionMapConfidence',
      );
      expect(positionMetric.documentId, documentId);
      expect(positionMetric.sessionId, sessionId);
      expect(positionMetric.voiceId, controller.selectedVoice!.id);
      expect(positionMetric.engineId, 'generic');

      engine.emitStart();

      final metricsAfterStart = PlaybackInstrumentationService.instance
          .snapshot();
      final latencyMetric = metricsAfterStart.firstWhere(
        (record) => record.metric == 'firstAudioLatencyMs',
      );
      expect(latencyMetric.documentId, documentId);
      expect(latencyMetric.sessionId, sessionId);
      expect(latencyMetric.voiceId, controller.selectedVoice!.id);
      expect(latencyMetric.engineId, 'generic');
      expect(latencyMetric.value, isA<int>());
    });

    test(
      'restores the last heard position for the last opened document',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-restore-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/remembered.txt');
        await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

        SharedPreferences.setMockInitialValues(<String, Object>{
          'reader.lastOpenedDocumentPath': file.path,
          'reader.lastOpenedDirectoryPath': tempDir.path,
          'reader.resumeState': jsonEncode(
            ReaderResumeState(
              documentPath: file.path,
              wordIndex: 3,
              wordIndexWithinSegment: 1,
              segmentTextAnchor: 'Gamma delta.',
              anchorWordText: 'delta',
            ).toJson(),
          ),
        });

        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        final restored = await controller.restoreLastOpenedDocument();

        expect(restored, isTrue);
        expect(controller.document.title, 'remembered.txt');
        expect(controller.windowTitle, 'Read Aloud - remembered.txt');
        expect(controller.currentWordIndex, 3);
        expect(
          controller.document.speakableText,
          contains('Alpha beta. Gamma delta. Epsilon zeta.'),
        );
        expect(controller.statusMessage, isNull);
        expect(
          controller.readingFocusState.activeDisplayBlockId,
          controller.document.segmentForWordIndex(3)?.blockId,
        );
      },
    );

    test(
      'reopens the remembered document through persisted directory access when available',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-restore-directory-token-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/remembered-directory-token.txt');
        await file.writeAsString('Alpha beta. Gamma delta.');
        final accessService = _FakeDocumentAccessService(
          openedLeasePath: tempDir.path,
          openedLeaseToken: 'directory-bookmark-refreshed',
        );

        SharedPreferences.setMockInitialValues(<String, Object>{
          'reader.lastOpenedDocumentPath': file.path,
          'reader.lastOpenedDirectoryPath': tempDir.path,
          'reader.lastOpenedDirectoryAccessToken':
              'directory-bookmark-original',
          'reader.resumeState': jsonEncode(
            ReaderResumeState(
              documentPath: file.path,
              wordIndex: 2,
              wordIndexWithinSegment: 0,
              segmentTextAnchor: 'Gamma delta.',
              anchorWordText: 'Gamma',
            ).toJson(),
          ),
        });

        final controller = ReaderController(
          ttsEngine: _FakeTtsEngine(),
          documentAccessService: accessService,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        final restored = await controller.restoreLastOpenedDocument();

        expect(restored, isTrue);
        expect(
          accessService.openedTokens,
          contains('directory-bookmark-original'),
        );
        expect(
          accessService.closedTokens,
          contains('directory-bookmark-refreshed'),
        );
        expect(controller.document.title, 'remembered-directory-token.txt');

        final preferences = await ReaderPreferencesService().load();
        expect(
          preferences.lastOpenedDirectoryAccessToken,
          'directory-bookmark-refreshed',
        );
        expect(preferences.lastOpenedDocumentPath, file.path);
      },
    );

    test(
      'reopens the remembered document through persisted restore access when available',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-restore-token-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/remembered-token.txt');
        await file.writeAsString('Alpha beta. Gamma delta.');
        final accessService = _FakeDocumentAccessService(
          createdToken: 'bookmark-token-refreshed',
          openedLeasePath: file.path,
          openedLeaseToken: 'bookmark-token-refreshed',
        );

        SharedPreferences.setMockInitialValues(<String, Object>{
          'reader.lastOpenedDocumentPath': '/stale/path/remembered-token.txt',
          'reader.lastOpenedDocumentAccessToken': 'bookmark-token-original',
          'reader.lastOpenedDirectoryPath': tempDir.path,
          'reader.resumeState': jsonEncode(
            ReaderResumeState(
              documentPath: file.path,
              wordIndex: 2,
              wordIndexWithinSegment: 0,
              segmentTextAnchor: 'Gamma delta.',
              anchorWordText: 'Gamma',
            ).toJson(),
          ),
        });

        final controller = ReaderController(
          ttsEngine: _FakeTtsEngine(),
          documentAccessService: accessService,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        final restored = await controller.restoreLastOpenedDocument();

        expect(restored, isTrue);
        expect(accessService.openedTokens, contains('bookmark-token-original'));
        expect(
          accessService.closedTokens,
          contains('bookmark-token-refreshed'),
        );
        expect(controller.document.title, 'remembered-token.txt');

        final preferences = await ReaderPreferencesService().load();
        expect(
          preferences.lastOpenedDocumentAccessToken,
          'bookmark-token-refreshed',
        );
        expect(preferences.lastOpenedDocumentPath, file.path);
      },
    );

    test(
      'bootstraps a missing restore token from the remembered path on startup',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-restore-bootstrap-token-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/bootstrap-token.txt');
        await file.writeAsString('Alpha beta. Gamma delta.');
        final accessService = _FakeDocumentAccessService(
          createdToken: 'bookmark-token-bootstrapped',
          openedLeasePath: file.path,
          openedLeaseToken: 'bookmark-token-bootstrapped',
        );

        SharedPreferences.setMockInitialValues(<String, Object>{
          'reader.lastOpenedDocumentPath': file.path,
          'reader.lastOpenedDirectoryPath': tempDir.path,
          'reader.resumeState': jsonEncode(
            ReaderResumeState(
              documentPath: file.path,
              wordIndex: 2,
              wordIndexWithinSegment: 0,
              segmentTextAnchor: 'Gamma delta.',
              anchorWordText: 'Gamma',
            ).toJson(),
          ),
        });

        final controller = ReaderController(
          ttsEngine: _FakeTtsEngine(),
          documentAccessService: accessService,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        final restored = await controller.restoreLastOpenedDocument();

        expect(restored, isTrue);
        expect(accessService.createdPaths, contains(file.path));
        expect(
          accessService.openedTokens,
          contains('bookmark-token-bootstrapped'),
        );

        final preferences = await ReaderPreferencesService().load();
        expect(
          preferences.lastOpenedDocumentAccessToken,
          'bookmark-token-bootstrapped',
        );
        expect(preferences.lastOpenedDocumentPath, file.path);
      },
    );

    test(
      'requests explicit directory access when no stored token can be bootstrapped',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-restore-requested-access-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/requested-access.txt');
        await file.writeAsString('Alpha beta. Gamma delta.');
        final accessService = _FakeDocumentAccessService(
          requestedLeasePath: file.path,
          requestedLeaseToken: 'bookmark-token-requested',
        );

        SharedPreferences.setMockInitialValues(<String, Object>{
          'reader.lastOpenedDocumentPath': file.path,
          'reader.lastOpenedDirectoryPath': tempDir.path,
          'reader.resumeState': jsonEncode(
            ReaderResumeState(
              documentPath: file.path,
              wordIndex: 2,
              wordIndexWithinSegment: 0,
              segmentTextAnchor: 'Gamma delta.',
              anchorWordText: 'Gamma',
            ).toJson(),
          ),
        });

        final controller = ReaderController(
          ttsEngine: _FakeTtsEngine(),
          documentAccessService: accessService,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        final restored = await controller.restoreLastOpenedDocument();

        expect(restored, isTrue);
        expect(accessService.requestedPaths, contains(tempDir.path));

        final preferences = await ReaderPreferencesService().load();
        expect(
          preferences.lastOpenedDirectoryAccessToken,
          'bookmark-token-requested',
        );
        expect(preferences.lastOpenedDocumentPath, file.path);
      },
    );

    test(
      'persists playback-derived resume state and restores it on startup',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-resume-persist-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/resume.txt');
        await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

        final firstEngine = _FakeTtsEngine();
        final firstController = ReaderController(ttsEngine: firstEngine);

        await firstController.initialize();
        await firstController.importFilePaths(<String>[file.path]);
        await firstController.startPlayback();
        firstEngine.emitStart();

        final documentId = firstController.document.displayDocument.documentId;
        final secondSegment =
            firstController.document.speechDocument.segments[1];
        firstEngine.emitProgress(
          TtsProgressUpdate(
            startOffset: 11,
            endOffset: 22,
            word: 'delta',
            documentId: documentId,
            chunkId: 'chunk-resume',
            segmentId: secondSegment.segmentId,
            wordStartIndex: 2,
            wordEndIndex: 4,
            elapsedInChunk: const Duration(seconds: 2),
            chunkAudioDuration: const Duration(seconds: 2),
            voiceId: firstController.selectedVoice!.id,
            rate: firstController.currentSpeed,
          ),
        );
        await firstController.pausePlayback();
        firstController.dispose();

        final secondEngine = _FakeTtsEngine();
        final secondController = ReaderController(ttsEngine: secondEngine);
        addTearDown(secondController.dispose);

        await secondController.initialize();
        final restored = await secondController.restoreLastOpenedDocument();

        expect(restored, isTrue);
        expect(secondController.document.title, 'resume.txt');
        expect(secondController.currentWordIndex, 4);
        expect(secondController.statusMessage, isNull);
        expect(
          secondController.readingFocusState.activeDisplayBlockId,
          secondController.document.segmentForWordIndex(4)?.blockId,
        );
      },
    );

    test(
      'restores stored narrator and character voice assignments when the same document is reopened',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-cast-memory-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/cast-memory.txt');
        await file.writeAsString('"Hello there," Jennifer said.');

        final firstController = ReaderController(
          ttsEngine: _FakeTtsEngine(voices: _multiVoiceTestVoices),
        );

        await firstController.initialize();
        await firstController.importFilePaths(<String>[file.path]);
        await firstController.assignVoiceToCast('cast_narrator', 'am_michael');
        await firstController.assignVoiceToCast(
          'cast_character_jennifer',
          'af_bella',
        );
        firstController.dispose();

        final secondController = ReaderController(
          ttsEngine: _FakeTtsEngine(voices: _multiVoiceTestVoices),
        );
        addTearDown(secondController.dispose);

        await secondController.initialize();
        final restored = await secondController.restoreLastOpenedDocument();

        expect(restored, isTrue);

        final assignments = secondController.castVoiceAssignments;
        expect(assignments, isNotNull);
        expect(
          assignments!.forCastId('cast_narrator')?.effectiveVoiceId,
          'am_michael',
        );
        expect(
          assignments.forCastId('cast_narrator')?.decisionKind,
          VoiceAssignmentDecisionKind.storedDocumentChoice,
        );
        expect(
          assignments.forCastId('cast_character_jennifer')?.effectiveVoiceId,
          'af_bella',
        );
        expect(
          assignments.forCastId('cast_character_jennifer')?.decisionKind,
          VoiceAssignmentDecisionKind.storedDocumentChoice,
        );
      },
    );

    test(
      'clearing a stored cast assignment returns that cast role to automatic resolution on reopen',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-clear-cast-memory-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/clear-cast-memory.txt');
        await file.writeAsString('"Hello there," Jennifer said.');

        final firstController = ReaderController(
          ttsEngine: _FakeTtsEngine(voices: _multiVoiceTestVoices),
        );

        await firstController.initialize();
        await firstController.importFilePaths(<String>[file.path]);
        final automaticAssignment = firstController.castVoiceAssignments!
            .forCastId('cast_character_jennifer');
        final overrideVoiceId = firstController.voices
            .map((voice) => voice.id)
            .firstWhere(
              (voiceId) => voiceId != automaticAssignment?.effectiveVoiceId,
            );

        await firstController.assignVoiceToCast(
          'cast_character_jennifer',
          overrideVoiceId,
        );
        await firstController.clearCastVoiceOverride('cast_character_jennifer');
        firstController.dispose();

        final secondController = ReaderController(
          ttsEngine: _FakeTtsEngine(voices: _multiVoiceTestVoices),
        );
        addTearDown(secondController.dispose);

        await secondController.initialize();
        final restored = await secondController.restoreLastOpenedDocument();

        expect(restored, isTrue);

        final assignment = secondController.castVoiceAssignments!.forCastId(
          'cast_character_jennifer',
        );
        expect(assignment, isNotNull);
        expect(assignment!.decisionKind, VoiceAssignmentDecisionKind.automatic);
        expect(assignment.storedVoiceId, isNull);
      },
    );

    test(
      'persists restore access when a file-backed document is opened',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-access-persist-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/persisted.txt');
        await file.writeAsString('Alpha beta. Gamma delta.');
        final accessService = _FakeDocumentAccessService(
          createdTokensByPath: <String, String>{
            tempDir.path: 'directory-bookmark-token',
            file.path: 'bookmark-created-token',
          },
        );

        final controller = ReaderController(
          ttsEngine: _FakeTtsEngine(),
          documentAccessService: accessService,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importFilePaths(<String>[file.path]);

        expect(accessService.createdPaths, contains(file.path));
        expect(accessService.createdPaths, contains(tempDir.path));
        expect(accessService.requestedPaths, isEmpty);

        final preferences = await ReaderPreferencesService().load();
        expect(preferences.lastOpenedDocumentPath, file.path);
        expect(
          preferences.lastOpenedDirectoryAccessToken,
          'directory-bookmark-token',
        );
        expect(
          preferences.lastOpenedDocumentAccessToken,
          'bookmark-created-token',
        );
      },
    );

    test(
      'recovers from a permission-shaped file-read failure by requesting directory access and retrying',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-access-recovery-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final filePath = '${tempDir.path}/recovered.txt';
        final fileBytes = Uint8List.fromList(
          utf8.encode('Alpha beta. Gamma delta.'),
        );
        final accessService = _FakeDocumentAccessService(
          createdTokensByPath: <String, String>{
            tempDir.path: 'directory-bookmark-token',
            filePath: 'file-bookmark-token',
          },
          requestedLeasePath: tempDir.path,
          requestedLeaseToken: 'directory-bookmark-token',
        );
        final controller = ReaderController(
          ttsEngine: _FakeTtsEngine(),
          documentAccessService: accessService,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importDroppedFiles(<XFile>[
          _FailOnceXFile(
            filePath,
            fileBytes,
            const FileSystemException('Operation not permitted'),
          ),
        ]);

        expect(accessService.requestedPaths, contains(tempDir.path));
        expect(controller.document.title, 'recovered.txt');
        expect(controller.statusMessage, isNull);

        final preferences = await ReaderPreferencesService().load();
        expect(
          preferences.lastOpenedDirectoryAccessToken,
          'directory-bookmark-token',
        );
      },
    );

    test(
      'does not surface a success status for ordinary readable document loads',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        controller.showStatusMessage('Old message');

        await controller.importPastedText('Alpha beta. Gamma delta.');

        expect(controller.document.wordCount, greaterThan(0));
        expect(controller.statusMessage, isNull);
      },
    );

    test(
      'suppresses non-actionable startup restore failures from user-facing status',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-restore-missing-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final missingPath = '${tempDir.path}/missing.txt';

        SharedPreferences.setMockInitialValues(<String, Object>{
          'reader.lastOpenedDocumentPath': missingPath,
          'reader.lastOpenedDirectoryPath': tempDir.path,
        });

        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        final restored = await controller.restoreLastOpenedDocument();

        expect(restored, isFalse);
        expect(controller.statusMessage, isNull);
        expect(controller.document.type, ReaderDocumentType.sample);
      },
    );

    test(
      'ignores stale progress after replacing the active document',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText('Alpha beta. Gamma delta.');
        await controller.startPlayback();
        engine.emitStart();

        final firstDocumentId = controller.document.displayDocument.documentId;
        final firstSegment = controller.document.speechDocument.segments.first;

        await controller.importPastedText('Fresh start only.');

        expect(
          controller.document.displayDocument.documentId,
          isNot(firstDocumentId),
        );
        expect(controller.currentWordIndex, 0);
        expect(controller.spokenSelection.hasSelection, isFalse);

        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 0,
            endOffset: 10,
            word: 'beta',
            documentId: firstDocumentId,
            chunkId: 'stale-chunk',
            segmentId: firstSegment.segmentId,
            wordStartIndex: 0,
            wordEndIndex: 2,
            elapsedInChunk: const Duration(seconds: 1),
            chunkAudioDuration: const Duration(seconds: 1),
            voiceId: controller.selectedVoice!.id,
            rate: controller.currentSpeed,
          ),
        );

        expect(controller.currentWordIndex, 0);
        expect(controller.spokenSelection.hasSelection, isFalse);
      },
    );

    test('surfaces debug phoneme trace snapshots from the engine', () async {
      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();

      engine.emitDebugTrace(
        TtsDebugTraceSnapshot(
          logPath: '/tmp/2026-04-03T01-45-00_af_bella.log',
          startedAt: DateTime.utc(2026, 4, 3, 1, 45),
          voiceId: 'af_bella',
          recentLines: <String>[
            'voiceId: af_bella',
            'trace: plainText text="for the road" prepared="for the road" phonemes="fˈɔɹ ðə ɹˈoʊd"',
          ],
          sessionId: 'session_debug',
        ),
      );

      expect(
        controller.ttsDebugTraceLogPath,
        '/tmp/2026-04-03T01-45-00_af_bella.log',
      );
      expect(controller.ttsDebugTraceVoiceId, 'af_bella');
      expect(
        controller.ttsDebugTraceLines.last,
        contains('phonemes="fˈɔɹ ðə ɹˈoʊd"'),
      );
    });

    test('live read mode reloads the watched file in place', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-live-read-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/live.txt');
      await file.writeAsString('Alpha beta.');

      final engine = _FakeTtsEngine();
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.startLiveReadFromPath(file.path);

      expect(controller.isLiveReadEnabled, isTrue);
      expect(controller.liveReadFilePath, file.path);
      expect(controller.document.title, 'live.txt');
      expect(controller.windowTitle, 'Read Aloud - live.txt');
      expect(controller.document.speakableText, contains('Alpha beta.'));

      await file.writeAsString('Gamma delta.');

      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (controller.document.speakableText.contains('Gamma delta.')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(controller.document.speakableText, contains('Gamma delta.'));
      expect(controller.statusMessage, contains('Live read updated'));
    });

    test(
      'live read refresh continues playback when the transport is active',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-live-read-resume-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/live-resume.txt');
        await file.writeAsString('Alpha beta. Gamma delta.');

        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.startLiveReadFromPath(file.path);
        await controller.startPlayback();
        engine.emitStart();

        expect(engine.speakCallCount, 1);
        expect(controller.isPlaying, isTrue);

        await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

        for (var attempt = 0; attempt < 30; attempt += 1) {
          if (controller.document.speakableText.contains('Epsilon zeta.') &&
              engine.speakCallCount >= 2) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        expect(controller.document.speakableText, contains('Epsilon zeta.'));
        expect(engine.speakCallCount, greaterThanOrEqualTo(2));
        expect(
          controller.playbackState,
          isIn(<ReaderPlaybackPrimaryState>[
            ReaderPlaybackPrimaryState.bufferingFirstChunk,
            ReaderPlaybackPrimaryState.playing,
          ]),
        );
      },
    );

    test(
      'live read refresh stays paused after an explicit user pause',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-live-read-paused-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/live-paused.txt');
        await file.writeAsString('Alpha beta. Gamma delta.');

        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.startLiveReadFromPath(file.path);
        await controller.startPlayback();
        engine.emitStart();
        await controller.pausePlayback();

        expect(engine.speakCallCount, 1);
        expect(controller.isPlaying, isFalse);

        await file.writeAsString('Alpha beta. Gamma delta. Epsilon zeta.');

        for (var attempt = 0; attempt < 30; attempt += 1) {
          if (controller.document.speakableText.contains('Epsilon zeta.')) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        expect(controller.document.speakableText, contains('Epsilon zeta.'));
        expect(engine.speakCallCount, 1);
        expect(controller.isPlaying, isFalse);
        expect(controller.playbackState, ReaderPlaybackPrimaryState.idle);
      },
    );

    test(
      'uses document title as the window title fallback for non-file content',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(controller.windowTitle, 'Read Aloud - For Probe');

        await controller.importPastedText('Alpha beta.');

        expect(controller.windowTitle, 'Read Aloud - Pasted Text');
      },
    );

    test(
      'maintains reading focus state across progress, pause, and user yield',
      () async {
        final engine = _FakeTtsEngine();
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          'Alpha beta. Gamma delta. Epsilon zeta.',
        );
        await controller.startPlayback();
        engine.emitStart();

        final documentId = controller.document.displayDocument.documentId;
        final secondSegment = controller.document.speechDocument.segments[1];
        final voiceId = controller.selectedVoice!.id;

        engine.emitProgress(
          TtsProgressUpdate(
            startOffset: 11,
            endOffset: 22,
            word: 'delta',
            documentId: documentId,
            chunkId: 'chunk-2',
            segmentId: secondSegment.segmentId,
            wordStartIndex: 2,
            wordEndIndex: 4,
            elapsedInChunk: const Duration(seconds: 2),
            chunkAudioDuration: const Duration(seconds: 2),
            voiceId: voiceId,
            rate: controller.currentSpeed,
          ),
        );

        expect(controller.readingFocusState.playbackActive, isTrue);
        expect(
          controller.readingFocusState.followMode,
          ReadingFocusFollowMode.following,
        );
        expect(
          controller.readingFocusState.activeDisplayBlockId,
          secondSegment.blockId,
        );
        expect(controller.readingFocusState.shouldAutoFollow, isTrue);

        controller.suspendReaderFollow();

        expect(
          controller.readingFocusState.followMode,
          ReadingFocusFollowMode.suspendedByUser,
        );
        expect(controller.readingFocusState.shouldAutoFollow, isFalse);
        expect(controller.readingFocusState.canRecenter, isTrue);

        await controller.pausePlayback();

        expect(controller.readingFocusState.playbackActive, isFalse);
        expect(
          controller.readingFocusState.activeDisplayBlockId,
          secondSegment.blockId,
        );
        expect(controller.readingFocusState.canRecenter, isTrue);

        controller.resumeReaderFollow();

        expect(
          controller.readingFocusState.followMode,
          ReadingFocusFollowMode.following,
        );
        expect(controller.readingFocusState.canRecenter, isFalse);

        await controller.jumpBySeconds(30);

        expect(controller.readingFocusState.playbackActive, isFalse);
        expect(controller.readingFocusState.activeDisplayBlockId, isNull);
        expect(
          controller.readingFocusState.followMode,
          ReadingFocusFollowMode.following,
        );
      },
    );

    test(
      'builds a multi-voice playback plan with narrator speaker tags and quoted character speech',
      () async {
        final engine = _FakeTtsEngine(
          voices: const <VoiceProfile>[
            VoiceProfile(
              id: 'af_bella',
              label: 'Bella',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
              gender: VoiceGender.female,
            ),
            VoiceProfile(
              id: 'am_michael',
              label: 'Michael',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
              gender: VoiceGender.male,
            ),
          ],
        );
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          'John said, "Are you ok?" The room was silent.',
        );

        await controller.startPlayback();

        final request = engine.lastSpeakRequest;
        expect(request, isNotNull);
        final chunkPlan = request!.chunkPlan;
        expect(chunkPlan, isNotNull);

        final chunks = chunkPlan!.chunks;
        expect(chunks.length, greaterThanOrEqualTo(3));
        expect(chunks[0].speakText, 'John said,');
        expect(chunks[0].voiceId, 'af_bella');
        expect(chunks[0].castId, 'cast_narrator');

        expect(chunks[1].speakText, '"Are you ok?"');
        expect(chunks[1].voiceId, 'am_michael');
        expect(chunks[1].castId, 'cast_character_john');
        expect(chunks[1].dialogueSpanId, isNotNull);

        expect(chunks.last.speakText, 'The room was silent.');
        expect(chunks.last.voiceId, 'af_bella');
        expect(chunks.last.castId, 'cast_narrator');
      },
    );

    test(
      'disables cast-aware routing when multi-voice mode is turned off',
      () async {
        final engine = _FakeTtsEngine(
          voices: const <VoiceProfile>[
            VoiceProfile(
              id: 'af_bella',
              label: 'Bella',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
              gender: VoiceGender.female,
            ),
            VoiceProfile(
              id: 'am_michael',
              label: 'Michael',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
              gender: VoiceGender.male,
            ),
          ],
        );
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          'John said, "Are you ok?" The room was silent.',
        );

        expect(controller.isMultiVoiceEnabled, isTrue);
        await controller.setMultiVoiceEnabled(false);
        expect(controller.castVoiceAssignments, isNull);

        await controller.startPlayback();

        final request = engine.lastSpeakRequest;
        expect(request, isNotNull);
        final chunkPlan = request!.chunkPlan;
        expect(chunkPlan, isNotNull);
        expect(
          chunkPlan!.chunks.every(
            (chunk) =>
                chunk.voiceId == 'af_bella' &&
                chunk.castId == null &&
                chunk.routeId == null &&
                chunk.dialogueSpanId == null,
          ),
          isTrue,
        );
      },
    );

    test(
      'assigns quoted Jennifer dialogue to a narrator-distinct character voice',
      () async {
        final engine = _FakeTtsEngine(
          voices: const <VoiceProfile>[
            VoiceProfile(
              id: 'af_bella',
              label: 'Bella',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
              gender: VoiceGender.female,
              qualityGrade: 'A-',
            ),
            VoiceProfile(
              id: 'af_heart',
              label: 'Heart',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Heart', 'locale': 'en-US'},
              gender: VoiceGender.female,
              qualityGrade: 'A',
            ),
            VoiceProfile(
              id: 'bf_emma',
              label: 'Emma',
              locale: 'en-GB',
              rawValue: <String, dynamic>{'name': 'Emma', 'locale': 'en-GB'},
              gender: VoiceGender.female,
              qualityGrade: 'B-',
            ),
            VoiceProfile(
              id: 'am_michael',
              label: 'Michael',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
              gender: VoiceGender.male,
              qualityGrade: 'C+',
            ),
          ],
        );
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          '"JUST STOP FIGHTING!" Jennifer screamed, pulling on her hair.',
        );

        await controller.startPlayback();

        final request = engine.lastSpeakRequest;
        expect(request, isNotNull);
        final chunkPlan = request!.chunkPlan;
        expect(chunkPlan, isNotNull);

        final quoteChunk = chunkPlan!.chunks.firstWhere(
          (chunk) => chunk.speakText == '"JUST STOP FIGHTING!"',
        );
        final narratorChunk = chunkPlan.chunks.firstWhere(
          (chunk) =>
              chunk.speakText == 'Jennifer screamed, pulling on her hair.',
        );

        expect(quoteChunk.castId, 'cast_character_jennifer');
        expect(narratorChunk.castId, 'cast_narrator');
        expect(quoteChunk.voiceId, isNot(narratorChunk.voiceId));
      },
    );

    test(
      'builds alternating narrator and character chunks for quote-tag-quote exchanges',
      () async {
        final engine = _FakeTtsEngine(
          voices: const <VoiceProfile>[
            VoiceProfile(
              id: 'af_bella',
              label: 'Bella',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
              gender: VoiceGender.female,
              qualityGrade: 'A',
            ),
            VoiceProfile(
              id: 'am_michael',
              label: 'Michael',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
              gender: VoiceGender.male,
              qualityGrade: 'A-',
            ),
            VoiceProfile(
              id: 'bm_fable',
              label: 'Fable',
              locale: 'en-US',
              rawValue: <String, dynamic>{'name': 'Fable', 'locale': 'en-US'},
              gender: VoiceGender.male,
              qualityGrade: 'B',
            ),
          ],
        );
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.importPastedText(
          '"John, why did you have to budge in front of me this morning?" Elliot said '
          '"I dunno. I thought taking someone\'s position in line is how we operate now," '
          'John replied sarcastically.',
        );

        await controller.startPlayback();

        final request = engine.lastSpeakRequest;
        expect(request, isNotNull);
        final chunkPlan = request!.chunkPlan;
        expect(chunkPlan, isNotNull);

        final chunks = chunkPlan!.chunks;
        expect(
          chunks.map((chunk) => chunk.speakText).toList(growable: false),
          containsAllInOrder(<String>[
            '"John, why did you have to budge in front of me this morning?"',
            'Elliot said',
            '"I dunno. I thought taking someone\'s position in line is how we operate now,"',
            'John replied sarcastically.',
          ]),
        );
        expect(
          chunks.map((chunk) => chunk.castId).toList(growable: false),
          containsAllInOrder(<String?>[
            'cast_character_elliot',
            'cast_narrator',
            'cast_character_john',
            'cast_narrator',
          ]),
        );

        final firstQuote = chunks.firstWhere(
          (chunk) =>
              chunk.speakText ==
              '"John, why did you have to budge in front of me this morning?"',
        );
        final narratorTag = chunks.firstWhere(
          (chunk) => chunk.speakText == 'Elliot said',
        );
        final secondQuote = chunks.firstWhere(
          (chunk) =>
              chunk.speakText ==
              '"I dunno. I thought taking someone\'s position in line is how we operate now,"',
        );
        final closingTag = chunks.firstWhere(
          (chunk) => chunk.speakText == 'John replied sarcastically.',
        );

        expect(firstQuote.voiceId, isNot(narratorTag.voiceId));
        expect(secondQuote.voiceId, isNot(closingTag.voiceId));
        expect(narratorTag.voiceId, closingTag.voiceId);
        expect(firstQuote.dialogueSpanId, isNotNull);
        expect(secondQuote.dialogueSpanId, isNotNull);
        expect(narratorTag.dialogueSpanId, isNull);
        expect(closingTag.dialogueSpanId, isNull);
      },
    );

    test(
      'exposes cast-processing state while a multi-voice import is in flight',
      () async {
        final importer = _DelayedDocumentImporter();
        final controller = ReaderController(
          importer: importer,
          ttsEngine: _FakeTtsEngine(),
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final tempDir = await Directory.systemTemp.createTemp(
          'read-aloud-cast-processing',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/processing.txt');
        await file.writeAsString('"Hello," John said.');

        final importFuture = controller.importFilePaths(<String>[file.path]);
        await Future<void>.delayed(Duration.zero);

        expect(controller.isImporting, isTrue);
        expect(controller.isCastProcessingVisible, isTrue);
        expect(controller.documentLoadStageLabel, contains('dialogue'));

        importer.complete();
        await importFuture;

        expect(controller.isImporting, isFalse);
        expect(controller.isCastProcessingVisible, isFalse);
      },
    );

    test(
      'previews a voice without changing the selected narrator voice',
      () async {
        final engine = _FakeTtsEngine(
          voices: const <VoiceProfile>[
            VoiceProfile(
              id: 'af_bella',
              label: 'Bella',
              locale: 'en-US',
              rawValue: <String, dynamic>{},
            ),
            VoiceProfile(
              id: 'am_michael',
              label: 'Michael',
              locale: 'en-US',
              rawValue: <String, dynamic>{},
            ),
          ],
        );
        final controller = ReaderController(ttsEngine: engine);
        addTearDown(controller.dispose);

        await controller.initialize();
        await controller.selectVoiceById('af_bella');
        await controller.previewVoice('am_michael');

        expect(
          controller.previewStateForVoice('am_michael'),
          VoicePreviewState.loading,
        );
        expect(controller.selectedVoice?.id, 'af_bella');
        expect(engine.lastSelectedVoiceId, 'am_michael');
        expect(
          engine.lastSpeakRequest?.text,
          'Hello. This is Read Aloud previewing this voice.',
        );

        engine.emitStart();
        expect(
          controller.previewStateForVoice('am_michael'),
          VoicePreviewState.playing,
        );

        engine.emitComplete();
        expect(
          controller.previewStateForVoice('am_michael'),
          VoicePreviewState.idle,
        );
        expect(controller.selectedVoice?.id, 'af_bella');
        expect(engine.lastSelectedVoiceId, 'af_bella');
      },
    );

    test('pauses active reading automatically before voice preview', () async {
      final engine = _FakeTtsEngine(
        voices: const <VoiceProfile>[
          VoiceProfile(
            id: 'af_bella',
            label: 'Bella',
            locale: 'en-US',
            rawValue: <String, dynamic>{},
          ),
          VoiceProfile(
            id: 'am_michael',
            label: 'Michael',
            locale: 'en-US',
            rawValue: <String, dynamic>{},
          ),
        ],
      );
      final controller = ReaderController(ttsEngine: engine);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.importPastedText('Alpha beta. Gamma delta.');
      await controller.selectVoiceById('af_bella');
      await controller.startPlayback();
      engine.emitStart();

      await controller.previewVoice('am_michael');

      expect(engine.pauseCallCount, 1);
      expect(controller.isPlaying, isFalse);
      expect(controller.statusMessage, isNull);
      expect(
        controller.previewStateForVoice('am_michael'),
        VoicePreviewState.loading,
      );
      expect(engine.lastSelectedVoiceId, 'am_michael');
    });
  });
}

const List<VoiceProfile> _multiVoiceTestVoices = <VoiceProfile>[
  VoiceProfile(
    id: 'af_heart',
    label: 'Heart',
    locale: 'en-US',
    rawValue: <String, dynamic>{'name': 'Heart', 'locale': 'en-US'},
    gender: VoiceGender.female,
    qualityGrade: 'A',
  ),
  VoiceProfile(
    id: 'af_bella',
    label: 'Bella',
    locale: 'en-US',
    rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
    gender: VoiceGender.female,
    qualityGrade: 'A-',
  ),
  VoiceProfile(
    id: 'am_michael',
    label: 'Michael',
    locale: 'en-US',
    rawValue: <String, dynamic>{'name': 'Michael', 'locale': 'en-US'},
    gender: VoiceGender.male,
    qualityGrade: 'C+',
  ),
];

class _ExportTtsEngine extends _FakeTtsEngine implements AudioExportCapable {
  _ExportTtsEngine() : super(voices: _multiVoiceTestVoices);
  TtsExportRequest? exported;
  @override
  Future<void> speak(TtsSpeakRequest request) async {
    await super.speak(request);
    request.onPlaybackReady?.call(
      TtsPlaybackAcknowledgment(
        documentId: request.documentId!,
        assignmentRevision: request.assignmentRevision,
        generationId: 'source-test',
        bindingFingerprints: const {},
      ),
    );
  }

  @override
  Future<TtsExportResult> exportAudio(TtsExportRequest request) async {
    exported = request;
    return TtsExportResult(
      outputPath: request.outputPath,
      sidecarPath: '${request.outputPath}.json',
      duration: const Duration(seconds: 1),
      chunkCount: 1,
      voiceId: 'af_bella',
      rate: 1,
      engineId: 'source-test',
      engineVersion: '1',
    );
  }
}

class _FakeTtsEngine implements TtsEngine {
  _FakeTtsEngine({
    List<VoiceProfile> voices = const <VoiceProfile>[
      VoiceProfile(
        id: 'af_bella',
        label: 'Bella',
        locale: 'en-US',
        rawValue: <String, dynamic>{'name': 'Bella', 'locale': 'en-US'},
      ),
    ],
  }) : _voices = voices;

  final List<VoiceProfile> _voices;

  void Function()? _onStart;
  void Function(String? message)? _onStatus;
  void Function(TtsProgressUpdate update)? _onProgress;
  void Function()? _onComplete;
  void Function(String message)? _onError;
  void Function(TtsPlaybackActivity activity)? _onActivity;
  void Function(TtsDebugTraceSnapshot trace)? _onDebugTrace;
  TtsSpeakRequest? lastSpeakRequest;
  String? lastSelectedVoiceId;
  int speakCallCount = 0;
  int pauseCallCount = 0;

  @override
  set onStart(void Function()? callback) => _onStart = callback;

  @override
  set onStatus(void Function(String? message)? callback) =>
      _onStatus = callback;

  @override
  set onProgress(void Function(TtsProgressUpdate update)? callback) =>
      _onProgress = callback;

  @override
  set onComplete(void Function()? callback) => _onComplete = callback;

  @override
  set onError(void Function(String message)? callback) => _onError = callback;

  @override
  set onActivity(void Function(TtsPlaybackActivity activity)? callback) =>
      _onActivity = callback;

  @override
  set onDebugTrace(void Function(TtsDebugTraceSnapshot trace)? callback) =>
      _onDebugTrace = callback;

  @override
  Future<void> initialize() async {
    _onStatus?.call(null);
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<List<VoiceProfile>> loadVoices() async => _voices;

  @override
  Future<void> selectVoice(VoiceProfile voice) async {
    lastSelectedVoiceId = voice.id;
  }

  @override
  Future<void> setSpeechRate(double multiplier) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> speak(TtsSpeakRequest request) async {
    lastSpeakRequest = request;
    speakCallCount += 1;
    _onActivity?.call(
      const TtsPlaybackActivity(phase: TtsPlaybackPhase.buffering),
    );
  }

  @override
  Future<void> pause() async {
    pauseCallCount += 1;
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  Future<void> stop() async {
    _onActivity?.call(const TtsPlaybackActivity.idle());
  }

  @override
  void dispose() {}

  void emitStart() {
    _onActivity?.call(
      const TtsPlaybackActivity(phase: TtsPlaybackPhase.playing),
    );
    _onStart?.call();
  }

  void emitProgress(TtsProgressUpdate update) {
    _onProgress?.call(update);
  }

  void emitComplete() {
    _onActivity?.call(const TtsPlaybackActivity.idle());
    _onComplete?.call();
  }

  void emitError(String message) {
    _onError?.call(message);
  }

  void emitDebugTrace(TtsDebugTraceSnapshot trace) {
    _onDebugTrace?.call(trace);
  }
}

class _InitBarrierEngine extends _FakeTtsEngine {
  final ready = Completer<void>();
  @override
  Future<void> initialize() => ready.future;
}

String _cacheProse() => List.generate(
  1000,
  (index) => 'Ledger item $index ends with marker$index.',
).join('\n');

List<String> _words(String text) =>
    RegExp(r'\S+').allMatches(text).map((match) => match.group(0)!).toList();

Future<String> _consumeRanges(
  ReaderController controller,
  _FakeTtsEngine engine,
) async {
  await controller.startPlayback();
  var request = engine.lastSpeakRequest!;
  var nextWord = 0;
  var sequence = 0;
  final output = <String>[];
  final cancelled = Completer<void>();
  while (true) {
    expect(request.rangeSequence, ++sequence);
    expect(request.sourceWordOffset, nextWord);
    expect(controller.preparedRanges.length, lessThanOrEqualTo(3));
    output.add(request.text);
    nextWord += request.speechDocument!.totalWordCount;
    request.onRangeActive?.call();
    final next = await request.continuation!
        .next(request.rangeSequence, cancelled.future)
        .timeout(const Duration(seconds: 30));
    if (next == null) break;
    request = next;
  }
  return output.join(' ');
}

class _ByteBarrierXFile extends XFile {
  _ByteBarrierXFile(String fileName) : super('/virtual-intake/$fileName');
  final started = Completer<void>();
  final bytes = Completer<Uint8List>();

  @override
  Future<Uint8List> readAsBytes() {
    started.complete();
    return bytes.future;
  }
}

class _ObservedRepositoryPreparationSupervisor
    extends DocumentPreparationSupervisor {
  _ObservedRepositoryPreparationSupervisor(ReaderDocumentRepository repository)
    : super(repository: repository);

  DocumentPreparationRequest? lastRequest;

  @override
  Future<DocumentPreparationResult> prepareRanges(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
    String? cacheKey,
    Future<void> Function(DocumentIdentityMigration)? onIdentityMigration,
    required Future<void> Function(DocumentPreparationPublication)
    onPublication,
    void Function(PreparationProgress)? onProgress,
    Future<void> Function()? acquireSource,
    Future<void> Function()? onDrained,
  }) {
    lastRequest = request;
    return super.prepareRanges(
      request,
      acquireBytes: acquireBytes,
      cacheKey: cacheKey,
      onIdentityMigration: onIdentityMigration,
      onPublication: onPublication,
      onProgress: onProgress,
      acquireSource: acquireSource,
      onDrained: onDrained,
    );
  }
}

class _CountingReaderDocumentRepository extends ReaderDocumentRepository {
  _CountingReaderDocumentRepository(super.rootPath);

  var beginCalls = 0;

  @override
  Future<ReaderDocumentCheckpoint> begin({
    required String sourceKey,
    required DocumentPreparationRequest request,
    String dependencies = ReaderDocumentRepository.dependencyVersion,
  }) {
    beginCalls += 1;
    return super.begin(
      sourceKey: sourceKey,
      request: request,
      dependencies: dependencies,
    );
  }
}

class _HeldOpenRepository extends ReaderDocumentRepository {
  _HeldOpenRepository(super.rootPath);
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ReaderDocumentCache?> open({
    required String sourceKey,
    required String sourceRevision,
    String dependencies = ReaderDocumentRepository.dependencyVersion,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.open(
      sourceKey: sourceKey,
      sourceRevision: sourceRevision,
      dependencies: dependencies,
    );
  }
}

class _HeldExportRepository extends ReaderDocumentRepository {
  _HeldExportRepository(super.rootPath);
  bool holdNextOpen = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ReaderDocumentCache?> open({
    required String sourceKey,
    required String sourceRevision,
    String dependencies = ReaderDocumentRepository.dependencyVersion,
  }) async {
    if (holdNextOpen) {
      holdNextOpen = false;
      started.complete();
      await release.future;
    }
    return super.open(
      sourceKey: sourceKey,
      sourceRevision: sourceRevision,
      dependencies: dependencies,
    );
  }
}

class _RecordingPreparationSupervisor extends DocumentPreparationSupervisor {
  _RecordingPreparationSupervisor(ReaderDocumentRepository repository)
    : super(repository: repository);
  final requests = <DocumentPreparationRequest>[];
  final cacheKeys = <String?>[];
  final results = <DocumentPreparationResult>[];
  final migrationCallbacks =
      <Future<void> Function(DocumentIdentityMigration)?>[];
  @override
  Future<DocumentPreparationResult> prepareRanges(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
    String? cacheKey,
    Future<void> Function(DocumentIdentityMigration)? onIdentityMigration,
    required Future<void> Function(DocumentPreparationPublication)
    onPublication,
    void Function(PreparationProgress)? onProgress,
    Future<void> Function()? acquireSource,
    Future<void> Function()? onDrained,
  }) async {
    requests.add(request.identityOnly);
    cacheKeys.add(cacheKey);
    migrationCallbacks.add(onIdentityMigration);
    final result = await super.prepareRanges(
      request,
      acquireBytes: acquireBytes,
      cacheKey: cacheKey,
      onIdentityMigration: onIdentityMigration,
      onPublication: onPublication,
      onProgress: onProgress,
      acquireSource: acquireSource,
      onDrained: onDrained,
    );
    results.add(result);
    return result;
  }
}

class _HeldPreferences extends ReaderPreferencesService {
  final ready = Completer<void>();
  @override
  Future<ReaderPreferences> load() async {
    await ready.future;
    return super.load();
  }
}

/// Deterministic source envelope/failure seam; production controller planning,
/// range credit and intent checks are retained. This emits no acoustic evidence.
class _RangePreparationSupervisor extends DocumentPreparationSupervisor {
  final started = Completer<void>();
  late DocumentPreparationRequest request;
  late Future<void> Function(DocumentPreparationPublication) publication;
  final result = Completer<DocumentPreparationResult>();
  int sequence = 0;
  int words = 0;
  int sourceOffset = 0;
  ReaderDocument? last;
  @override
  Future<DocumentPreparationResult> prepareRanges(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
    String? cacheKey,
    Future<void> Function(DocumentIdentityMigration)? onIdentityMigration,
    required Future<void> Function(DocumentPreparationPublication)
    onPublication,
    void Function(PreparationProgress)? onProgress,
    Future<void> Function()? acquireSource,
    Future<void> Function()? onDrained,
  }) {
    this.request = request;
    publication = onPublication;
    started.complete();
    return result.future;
  }

  Future<void> publish(String text) {
    final document = DocumentImportService().importPastedText(text);
    last = document;
    final value = DocumentPreparationPublication(
      request: request.identityOnly,
      sequence: ++sequence,
      fragment: document,
      range: PreparedDocumentRange(
        sourceStart: sourceOffset,
        sourceEnd: sourceOffset + text.length,
        wordStart: words,
        wordEnd: words + document.wordCount,
        segmentStart: 0,
        segmentEnd: document.speechDocument.segments.length,
      ),
      coverage: const {
        PreparationStage.normalization,
        PreparationStage.mapping,
        PreparationStage.analysis,
        PreparationStage.pronunciation,
      },
      progress: const [],
      isLast: false,
    );
    words += document.wordCount;
    sourceOffset += text.length;
    return publication(value);
  }

  void finish({String? error}) {
    if (result.isCompleted) return;
    result.complete(
      DocumentPreparationResult(
        request: request,
        outcome: error == null
            ? DocumentPreparationOutcome.ready
            : DocumentPreparationOutcome.failed,
        document: error == null ? last : null,
        error: error,
      ),
    );
  }

  @override
  void cancel() {
    if (started.isCompleted && !result.isCompleted) {
      result.complete(
        DocumentPreparationResult(
          request: request,
          outcome: DocumentPreparationOutcome.cancelled,
        ),
      );
    }
  }
}

// Explicit startup barrier: no wall-clock delay decides when audio starts.
// This fake proves controller acceptance only; it does not render audio.
class _BarrierStartTtsEngine extends _FakeTtsEngine {
  _BarrierStartTtsEngine() : super(voices: _multiVoiceTestVoices);

  final started = Completer<void>();
  final _released = Completer<void>();

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<void> speak(TtsSpeakRequest request) async {
    await super.speak(request);
    if (!started.isCompleted) started.complete();
    await _released.future;
    if (request.isCurrent?.call() != false) {
      request.onPlaybackReady?.call(
        TtsPlaybackAcknowledgment(
          documentId: request.documentId!,
          assignmentRevision: request.assignmentRevision,
          generationId: 'barrier-latest',
          bindingFingerprints: const {},
        ),
      );
      emitStart();
    }
  }
}

class _DelayedDocumentImporter extends DocumentImportService {
  _DelayedDocumentImporter();

  final Completer<void> _completer = Completer<void>();

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  Future<ReaderDocument> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    await _completer.future;
    return ReaderDocument.sample();
  }
}

class _FakeDocumentAccessService implements DocumentAccessService {
  _FakeDocumentAccessService({
    this.createdToken,
    this.createdTokensByPath,
    this.openedLeasePath,
    this.openedLeaseToken,
    this.requestedLeasePath,
    this.requestedLeaseToken,
  });

  final String? createdToken;
  final Map<String, String>? createdTokensByPath;
  final String? openedLeasePath;
  final String? openedLeaseToken;
  final String? requestedLeasePath;
  final String? requestedLeaseToken;
  final List<String> createdPaths = <String>[];
  final List<String> openedTokens = <String>[];
  final List<String> closedTokens = <String>[];
  final List<String> requestedPaths = <String>[];

  @override
  Future<String?> createPersistentRestoreToken(String path) async {
    createdPaths.add(path);
    final mappedToken = createdTokensByPath?[path];
    if (mappedToken != null) {
      return mappedToken;
    }
    return createdToken;
  }

  @override
  Future<DocumentAccessLease?> openPersistentRestoreToken(String token) async {
    openedTokens.add(token);
    final path = openedLeasePath;
    if (path == null) {
      return null;
    }

    final returnedToken = openedLeaseToken ?? token;
    return DocumentAccessLease(
      path: path,
      refreshedToken: returnedToken,
      close: () async {
        closedTokens.add(returnedToken);
      },
    );
  }

  @override
  Future<DocumentAccessLease?> requestPersistentRestoreAccess(
    String path,
  ) async {
    requestedPaths.add(path);
    final resolvedPath = requestedLeasePath;
    if (resolvedPath == null) {
      return null;
    }

    final returnedToken = requestedLeaseToken;
    return DocumentAccessLease(
      path: resolvedPath,
      refreshedToken: returnedToken,
      close: () async {
        if (returnedToken != null) {
          closedTokens.add(returnedToken);
        }
      },
    );
  }

  @override
  Future<DocumentAccessLease?> requestPersistentDirectoryAccess(
    String path,
  ) async {
    requestedPaths.add(path);
    final resolvedPath = requestedLeasePath;
    if (resolvedPath == null) {
      return null;
    }

    final returnedToken = requestedLeaseToken;
    return DocumentAccessLease(
      path: resolvedPath,
      refreshedToken: returnedToken,
      close: () async {
        if (returnedToken != null) {
          closedTokens.add(returnedToken);
        }
      },
    );
  }
}

class _FailOnceXFile extends XFile {
  _FailOnceXFile(this.filePath, this.payload, this.firstError)
    : super(filePath);

  final String filePath;
  final Uint8List payload;
  final FileSystemException firstError;
  var _readAttempts = 0;

  @override
  Future<Uint8List> readAsBytes() async {
    if (_readAttempts == 0) {
      _readAttempts += 1;
      throw firstError;
    }
    return payload;
  }
}

class _ControlledPreparationImporter extends DocumentImportService {
  final results = <Completer<ReaderDocument>>[];
  final payloads = <String>[];
  final _starts = <int, Completer<void>>{};
  Future<void> started(int index) {
    if (results.length > index) return Future.value();
    return (_starts[index] ??= Completer<void>()).future;
  }

  @override
  Future<ReaderDocument> importBytes({
    required String fileName,
    required Uint8List bytes,
  }) {
    final index = results.length;
    final result = Completer<ReaderDocument>();
    results.add(result);
    payloads.add(utf8.decode(bytes));
    _starts[index]?.complete();
    return result.future;
  }
}

// Only watcher delivery is substituted. File acquisition, controller reloads,
// supervisor coalescing and debounce timers retain their production paths.
final class _ControlledWatchOverrides extends IOOverrides {
  _ControlledWatchOverrides(this.path, this.events);
  final String path;
  final Stream<FileSystemEvent> events;

  @override
  Directory createDirectory(String candidate) => candidate == path
      ? _ControlledWatchDirectory(events)
      : super.createDirectory(candidate);
}

class _ControlledWatchDirectory implements Directory {
  _ControlledWatchDirectory(this.events);
  final Stream<FileSystemEvent> events;

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => this.events;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedPreparationSupervisor extends DocumentPreparationSupervisor {
  _ObservedPreparationSupervisor(DocumentImportService importer)
    : super(testImporter: importer);
  final requests = <DocumentPreparationRequest>[];
  final _admissions = <int, Completer<void>>{};

  Future<void> admitted(int index) => requests.length > index
      ? Future.value()
      : (_admissions[index] ??= Completer<void>()).future;

  @override
  Future<DocumentPreparationResult> prepare(
    DocumentPreparationRequest request, {
    Future<Uint8List> Function()? acquireBytes,
  }) {
    final index = requests.length;
    requests.add(request);
    final result = super.prepare(request, acquireBytes: acquireBytes);
    _admissions[index]?.complete();
    return result;
  }
}

class _OverlapResourceEngine extends _FakeTtsEngine
    implements ResourcePreparationCapable {
  final preparedDocuments = <String>[];
  @override
  bool resourcesReady = false;

  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) async {
    preparedDocuments.add(documentId);
    resourcesReady = true;
    return [
      for (final voiceId in voiceIds)
        PreparedVoiceBinding(
          voiceId: voiceId,
          voiceDigest: 'test-voice',
          modelDigest: 'test-model',
          engineVersion: 'test',
          pronunciationProfileId: pronunciationProfileId,
          bindingRevision: revision,
          documentId: documentId,
        ),
    ];
  }

  @override
  Future<void> releaseDocumentResources() async => resourcesReady = false;

  @override
  Future<void> shutdownResources() async => resourcesReady = false;
}

class _BarrierStopTtsEngine extends _FakeTtsEngine {
  bool holdNext = false;
  final stopped = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> stop() async {
    if (holdNext) {
      holdNext = false;
      stopped.complete();
      await release.future;
    }
    await super.stop();
  }
}

class _ControlledPicker extends FilePicker {
  final result = Completer<FilePickerResult?>();
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) => result.future;
}

class _ResourceBarrierEngine extends _FakeTtsEngine
    implements ResourcePreparationCapable {
  final started = Completer<void>();
  final barrier = Completer<List<PreparedVoiceBinding>>();
  bool ready = false;
  int preparations = 0;
  @override
  bool get resourcesReady => ready;
  @override
  Future<List<PreparedVoiceBinding>> prepareDocumentResources({
    required String documentId,
    required int revision,
    required Set<String> voiceIds,
    required String pronunciationProfileId,
  }) {
    if (!started.isCompleted) started.complete();
    ++preparations;
    return (preparations == 1
            ? barrier.future
            : Future<List<PreparedVoiceBinding>>.value(const []))
        .then(
          (_) => [
            for (final voiceId in voiceIds)
              PreparedVoiceBinding(
                voiceId: voiceId,
                voiceDigest: 'voice',
                modelDigest: 'model',
                engineVersion: 'test',
                pronunciationProfileId: pronunciationProfileId,
                bindingRevision: revision,
                documentId: documentId,
              ),
          ],
        );
  }

  @override
  Future<void> releaseDocumentResources() async {
    ready = false;
  }

  @override
  Future<void> shutdownResources() async {
    ready = false;
  }
}
