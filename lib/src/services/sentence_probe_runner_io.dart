// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../controllers/reader_controller.dart';
import '../models/reader_document.dart';
import 'app_launch_options.dart';
import 'document_import_service.dart';
import 'headless_session_result.dart';
import 'project_test_artifact_store.dart';
import 'tts_engine.dart';
import 'wav_analysis_service.dart';

const _sentenceProbeManifestFileName = 'sentence-probe-run.json';
const _sentenceProbeCombinedLogFileName = 'sentence-probe.log';

class SentenceProbeCase {
  const SentenceProbeCase({
    required this.id,
    required this.segmentId,
    required this.ordinal,
    required this.paragraphIndex,
    required this.sentenceIndex,
    required this.text,
  });

  final String id;
  final String segmentId;
  final int ordinal;
  final int paragraphIndex;
  final int sentenceIndex;
  final String text;
}

List<SentenceProbeCase> sentenceProbeCasesFromDocument(ReaderDocument document) {
  return document.speechDocument.segments
      .where((segment) => segment.normalizedText.trim().isNotEmpty)
      .map(
        (segment) => SentenceProbeCase(
          id: 'sentence_${segment.ordinal + 1}',
          segmentId: segment.segmentId,
          ordinal: segment.ordinal,
          paragraphIndex: segment.paragraphIndex,
          sentenceIndex: segment.sentenceIndex,
          text: segment.normalizedText.trim(),
        ),
      )
      .toList(growable: false);
}

Future<HeadlessSessionResult> runSentenceProbeSession(
  AppLaunchOptions options,
) async {
  final inputPath = options.sentenceProbeFile;
  if (inputPath == null || inputPath.trim().isEmpty) {
    return const HeadlessSessionResult(exitCode: 1, succeeded: 0, failed: 1);
  }

  final inputFile = File(inputPath);
  if (!await inputFile.exists()) {
    print('Sentence probe source does not exist: $inputPath');
    return const HeadlessSessionResult(exitCode: 1, succeeded: 0, failed: 1);
  }

  print('Mode: sentence probe');
  print('Source: $inputPath');

  final importer = DocumentImportService();
  final controller = ReaderController(
    importer: importer,
    enablePlatformIntakeChannels: false,
  );
  final wavAnalysisService = const WavAnalysisService();

  var succeeded = 0;
  var failed = 0;

  try {
    await controller.initialize();

    if (options.voiceId != null) {
      final requestedVoice = controller.voices
          .where((voice) => voice.id == options.voiceId)
          .firstOrNull;
      if (requestedVoice == null) {
        print('Voice not found: ${options.voiceId}');
        return const HeadlessSessionResult(
          exitCode: 1,
          succeeded: 0,
          failed: 1,
        );
      }
      await controller.selectVoiceById(requestedVoice.id);
    }

    if (options.speed != null) {
      await controller.setVoiceSpeed(options.speed!.clamp(0.7, 1.4).toDouble());
    }

    final imported = await importer.importBytes(
      fileName: p.basename(inputFile.path),
      bytes: await inputFile.readAsBytes(),
    );
    final cases = sentenceProbeCasesFromDocument(imported);
    if (cases.isEmpty) {
      print('No speech sentences were extracted from the source document.');
      return const HeadlessSessionResult(exitCode: 1, succeeded: 0, failed: 1);
    }

    final outputDirectory = await _resolveSentenceProbeOutputDirectory(options);
    final combinedLogFile = File(
      p.join(outputDirectory.path, _sentenceProbeCombinedLogFileName),
    );
    await combinedLogFile.writeAsString('', flush: true);

    final manifestEntries = <Map<String, Object?>>[];
    print('Sentences: ${cases.length}');

    for (var index = 0; index < cases.length; index += 1) {
      final probeCase = cases[index];
      final sequence = '${index + 1}'.padLeft(4, '0');
      final fileBase = '${sequence}_${_sanitizeProbeId(probeCase.id)}';
      final outputPath = p.join(outputDirectory.path, '$fileBase.wav');

      try {
        print('Sentence ${index + 1}/${cases.length}: ${probeCase.text}');
        await controller.loadDocument(importer.importPastedText(probeCase.text));
        final exportResult = await controller.exportAudioToPath(outputPath);
        if (exportResult == null) {
          failed += 1;
          print('  FAIL ${controller.statusMessage ?? 'Unknown export failure.'}');
          continue;
        }

        final wavBytes = await File(exportResult.outputPath).readAsBytes();
        final analysis = wavAnalysisService.analyzeBytes(wavBytes);
        final traceLogPath = controller.ttsDebugTraceLogPath;
        final traceLines = traceLogPath == null
            ? const <String>[]
            : await _readTraceLogLines(traceLogPath);

        await _appendSentenceRunLog(
          combinedLogFile: combinedLogFile,
          caseIndex: index + 1,
          probeCase: probeCase,
          exportResult: exportResult,
          traceLogPath: traceLogPath,
          traceLines: traceLines,
        );

        manifestEntries.add(<String, Object?>{
          'id': probeCase.id,
          'segmentId': probeCase.segmentId,
          'ordinal': probeCase.ordinal,
          'paragraphIndex': probeCase.paragraphIndex,
          'sentenceIndex': probeCase.sentenceIndex,
          'text': probeCase.text,
          'outputPath': exportResult.outputPath,
          'sidecarPath': exportResult.sidecarPath,
          'traceLogPath': traceLogPath,
          'analysis': analysis.toMap(),
        });
        succeeded += 1;
        print('  OK -> ${exportResult.outputPath}');
      } catch (error) {
        failed += 1;
        print('  FAIL $error');
      }
    }

    final manifest = <String, Object?>{
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'sourcePath': inputFile.path,
      'sourceTitle': imported.title,
      'voiceId': controller.selectedVoice?.id,
      'voiceDisplayName': controller.selectedVoice?.displayName,
      'rate': controller.currentSpeed,
      'sentenceCount': cases.length,
      'succeeded': succeeded,
      'failed': failed,
      'combinedLogPath': combinedLogFile.path,
      'entries': manifestEntries,
    };
    final manifestFile = File(
      p.join(outputDirectory.path, _sentenceProbeManifestFileName),
    );
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );

    print('Sentence probe summary: $succeeded succeeded, $failed failed.');
    print('Manifest: ${manifestFile.path}');
    print('Combined log: ${combinedLogFile.path}');

    return HeadlessSessionResult(
      exitCode: failed == 0 ? 0 : 1,
      succeeded: succeeded,
      failed: failed,
    );
  } finally {
    controller.dispose();
  }
}

Future<Directory> _resolveSentenceProbeOutputDirectory(
  AppLaunchOptions options,
) async {
  final explicitOutputDirectory = options.outputDirectory;
  if (explicitOutputDirectory != null && explicitOutputDirectory.trim().isNotEmpty) {
    final requestedDirectory = Directory(explicitOutputDirectory.trim());
    try {
      await requestedDirectory.create(recursive: true);
      return requestedDirectory;
    } catch (_) {
      print(
        'Sentence probe output directory is not writable from this app context: '
        '${requestedDirectory.path}',
      );
      print('Falling back to the default project test-artifact directory.');
    }
  }

  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final root = await resolveProjectTestArtifactDirectory('sentence-probes');
  final directory = Directory(p.join(root.path, timestamp));
  await directory.create(recursive: true);
  return directory;
}

Future<List<String>> _readTraceLogLines(String logPath) async {
  final file = File(logPath);
  if (!await file.exists()) {
    return const <String>[];
  }
  return const LineSplitter().convert(await file.readAsString());
}

Future<void> _appendSentenceRunLog({
  required File combinedLogFile,
  required int caseIndex,
  required SentenceProbeCase probeCase,
  required TtsExportResult exportResult,
  required String? traceLogPath,
  required List<String> traceLines,
}) async {
  final buffer = StringBuffer()
    ..writeln('=== sentence $caseIndex ===')
    ..writeln('id: ${probeCase.id}')
    ..writeln('segmentId: ${probeCase.segmentId}')
    ..writeln('ordinal: ${probeCase.ordinal}')
    ..writeln('paragraphIndex: ${probeCase.paragraphIndex}')
    ..writeln('sentenceIndex: ${probeCase.sentenceIndex}')
    ..writeln('text: ${jsonEncode(probeCase.text)}')
    ..writeln('outputPath: ${exportResult.outputPath}')
    ..writeln('sidecarPath: ${exportResult.sidecarPath}')
    ..writeln('traceLogPath: ${traceLogPath ?? 'missing'}');

  if (traceLines.isNotEmpty) {
    buffer.writeln('--- trace ---');
    for (final line in traceLines) {
      buffer.writeln(line);
    }
  }
  buffer.writeln();

  await combinedLogFile.writeAsString(
    buffer.toString(),
    mode: FileMode.append,
    flush: true,
  );
}

String _sanitizeProbeId(String id) {
  final sanitized = id
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  return sanitized.isEmpty ? 'sentence' : sanitized;
}
