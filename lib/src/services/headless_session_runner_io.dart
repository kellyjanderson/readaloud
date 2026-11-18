// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/reader_document.dart';
import 'app_launch_options.dart';
import 'document_import_service.dart';
import 'headless_session_result.dart';
import 'headless_reader_session.dart';
import 'pronunciation_probe_runner_io.dart';
import 'sentence_probe_runner_io.dart';

Future<HeadlessSessionResult> runHeadlessSessionInternal(
  AppLaunchOptions options,
) async {
  if (options.probeFile != null || options.probeTexts.isNotEmpty) {
    return runPronunciationProbeSession(options);
  }
  if (options.sentenceProbeFile != null) {
    return runSentenceProbeSession(options);
  }

  print('Mode: headless export');

  final session = HeadlessReaderSession();
  final importer = session.importer;
  final controller = session.controller;

  var succeeded = 0;
  var failed = 0;

  try {
    if (!await session.initialize(options)) {
      print('Voice not found: ${options.voiceId}');
      return const HeadlessSessionResult(exitCode: 1, succeeded: 0, failed: 1);
    }

    for (final inputPath in options.inputPaths) {
      final file = File(inputPath);
      if (!await file.exists()) {
        failed += 1;
        print('FAIL $inputPath');
        print('  File does not exist.');
        continue;
      }

      try {
        print('Processing $inputPath');
        final imported = await _importDocument(importer, file);
        await controller.loadDocument(imported);
        if (controller.document.speakableText.trim().isEmpty) {
          failed += 1;
          print('FAIL $inputPath');
          print('  No readable text was extracted for speech.');
          continue;
        }

        final outputPath = _resolveOutputPath(
          inputPath: file.path,
          document: controller.document,
          voiceId: controller.selectedVoice?.id,
          options: options,
        );
        final result = await controller.exportAudioToPath(outputPath);
        if (result == null) {
          failed += 1;
          print('FAIL $inputPath');
          print('  ${controller.statusMessage ?? 'Unknown export failure.'}');
          continue;
        }

        succeeded += 1;
        print('OK   $inputPath');
        print('  -> ${result.outputPath}');
      } catch (error) {
        failed += 1;
        print('FAIL $inputPath');
        print('  $error');
      }
    }
  } finally {
    session.close();
  }

  print('Summary: $succeeded succeeded, $failed failed.');
  return HeadlessSessionResult(
    exitCode: failed == 0 ? 0 : 1,
    succeeded: succeeded,
    failed: failed,
  );
}

Future<ReaderDocument> _importDocument(
  DocumentImportService importer,
  File file,
) async {
  final bytes = await file.readAsBytes();
  return importer.importBytes(fileName: p.basename(file.path), bytes: bytes);
}

String _resolveOutputPath({
  required String inputPath,
  required ReaderDocument document,
  required String? voiceId,
  required AppLaunchOptions options,
}) {
  if (options.outputPath != null) {
    return _ensureWavExtension(options.outputPath!);
  }

  final fileName = _defaultExportFileName(document.title, voiceId);
  if (options.outputDirectory != null) {
    return p.join(options.outputDirectory!, fileName);
  }

  return p.join(p.dirname(inputPath), fileName);
}

String _defaultExportFileName(String title, String? voiceId) {
  final withoutExtension = p.basenameWithoutExtension(title.trim());
  final base = withoutExtension.isEmpty
      ? 'Read Aloud Export'
      : withoutExtension;
  final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  final suffix = (voiceId == null || voiceId.trim().isEmpty)
      ? ''
      : ' - ${voiceId.trim()}';
  return '$sanitized$suffix.wav';
}

String _ensureWavExtension(String path) {
  return p.extension(path).toLowerCase() == '.wav' ? path : '$path.wav';
}
