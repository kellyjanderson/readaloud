// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../controllers/reader_controller.dart';
import 'app_launch_options.dart';
import 'document_import_service.dart';
import 'headless_session_result.dart';
import 'project_test_artifact_store.dart';
import 'wav_analysis_service.dart';

const _probeManifestFileName = 'pronunciation-probe-run.json';
const _probeComparisonFileName = 'pronunciation-probe-comparison.json';

class PronunciationProbeCase {
  const PronunciationProbeCase({
    required this.id,
    required this.text,
  });

  final String id;
  final String text;
}

Future<HeadlessSessionResult> runPronunciationProbeSession(
  AppLaunchOptions options,
) async {
  final probeCases = await _loadProbeCases(options);
  if (probeCases.isEmpty) {
    return const HeadlessSessionResult(exitCode: 1, succeeded: 0, failed: 1);
  }

  print('Mode: pronunciation probe');
  print('Cases: ${probeCases.length}');

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

    final outputDirectory = await _resolveProbeOutputDirectory(options);
    final manifestEntries = <Map<String, Object?>>[];

    for (var index = 0; index < probeCases.length; index += 1) {
      final probeCase = probeCases[index];
      final sequence = '${index + 1}'.padLeft(3, '0');
      final fileBase = '${sequence}_${_sanitizeProbeId(probeCase.id)}';
      final outputPath = p.join(outputDirectory.path, '$fileBase.wav');

      try {
        print('Probe ${index + 1}/${probeCases.length}: ${probeCase.id}');
        await controller.loadDocument(importer.importPastedText(probeCase.text));
        final exportResult = await controller.exportAudioToPath(outputPath);
        if (exportResult == null) {
          failed += 1;
          print('  FAIL ${controller.statusMessage ?? 'Unknown export failure.'}');
          continue;
        }

        final wavBytes = await File(exportResult.outputPath).readAsBytes();
        final analysis = wavAnalysisService.analyzeBytes(wavBytes);
        manifestEntries.add(<String, Object?>{
          'id': probeCase.id,
          'text': probeCase.text,
          'outputPath': exportResult.outputPath,
          'sidecarPath': exportResult.sidecarPath,
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
      'probeFile': options.probeFile,
      'probeTexts': options.probeTexts,
      'voiceId': controller.selectedVoice?.id,
      'voiceDisplayName': controller.selectedVoice?.displayName,
      'rate': controller.currentSpeed,
      'caseCount': probeCases.length,
      'succeeded': succeeded,
      'failed': failed,
      'entries': manifestEntries,
    };
    final manifestFile = File(p.join(outputDirectory.path, _probeManifestFileName));
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );

    if (options.compareDirectory != null) {
      await _writeComparisonReport(
        baselineDirectory: Directory(options.compareDirectory!),
        currentDirectory: outputDirectory,
        currentManifest: manifest,
        wavAnalysisService: wavAnalysisService,
      );
    }

    print('Probe summary: $succeeded succeeded, $failed failed.');
    print('Manifest: ${manifestFile.path}');

    return HeadlessSessionResult(
      exitCode: failed == 0 ? 0 : 1,
      succeeded: succeeded,
      failed: failed,
    );
  } finally {
    controller.dispose();
  }
}

Future<List<PronunciationProbeCase>> _loadProbeCases(
  AppLaunchOptions options,
) async {
  if (options.probeTexts.isNotEmpty) {
    return <PronunciationProbeCase>[
      for (var index = 0; index < options.probeTexts.length; index += 1)
        PronunciationProbeCase(
          id: 'probe_${index + 1}',
          text: options.probeTexts[index],
        ),
    ];
  }

  final probeFile = options.probeFile;
  if (probeFile == null || probeFile.trim().isEmpty) {
    return const <PronunciationProbeCase>[];
  }

  final file = File(probeFile);
  if (!await file.exists()) {
    print('Pronunciation probe file does not exist: $probeFile');
    return const <PronunciationProbeCase>[];
  }

  final probeCases = parsePronunciationProbeCases(await file.readAsString());
  if (probeCases.isEmpty) {
    print('Pronunciation probe file did not contain any usable phrases.');
  }
  return probeCases;
}

List<PronunciationProbeCase> parsePronunciationProbeCases(String rawText) {
  final probeCases = <PronunciationProbeCase>[];
  final lines = const LineSplitter().convert(rawText);

  for (var index = 0; index < lines.length; index += 1) {
    final rawLine = lines[index].trim();
    if (rawLine.isEmpty || rawLine.startsWith('#')) {
      continue;
    }

    final tabIndex = rawLine.indexOf('\t');
    if (tabIndex > 0 && tabIndex < rawLine.length - 1) {
      final id = rawLine.substring(0, tabIndex).trim();
      final text = rawLine.substring(tabIndex + 1).trim();
      if (id.isNotEmpty && text.isNotEmpty) {
        probeCases.add(PronunciationProbeCase(id: id, text: text));
        continue;
      }
    }

    probeCases.add(
      PronunciationProbeCase(
        id: 'probe_${probeCases.length + 1}',
        text: rawLine,
      ),
    );
  }

  return probeCases;
}

Future<Directory> _resolveProbeOutputDirectory(AppLaunchOptions options) async {
  final explicitOutputDirectory = options.outputDirectory;
  if (explicitOutputDirectory != null && explicitOutputDirectory.trim().isNotEmpty) {
    final requestedDirectory = Directory(explicitOutputDirectory.trim());
    try {
      await requestedDirectory.create(recursive: true);
      return requestedDirectory;
    } catch (_) {
      print(
        'Probe output directory is not writable from this app context: '
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
  final probeRoot = await resolveProjectTestArtifactDirectory(
    'pronunciation-probes',
  );
  final directory = Directory(p.join(probeRoot.path, timestamp));
  await directory.create(recursive: true);
  return directory;
}

Future<void> _writeComparisonReport({
  required Directory baselineDirectory,
  required Directory currentDirectory,
  required Map<String, Object?> currentManifest,
  required WavAnalysisService wavAnalysisService,
}) async {
  final baselineFile = File(
    p.join(baselineDirectory.path, _probeManifestFileName),
  );
  if (!await baselineFile.exists()) {
    throw StateError(
      'Comparison directory does not contain $_probeManifestFileName.',
    );
  }

  final baselineManifest =
      jsonDecode(await baselineFile.readAsString()) as Map<String, Object?>;
  final baselineEntries = (baselineManifest['entries'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final currentEntries = (currentManifest['entries'] as List<Object?>)
      .cast<Map<String, Object?>>();

  final baselineById = <String, Map<String, Object?>>{
    for (final entry in baselineEntries) entry['id']! as String: entry,
  };
  final currentById = <String, Map<String, Object?>>{
    for (final entry in currentEntries) entry['id']! as String: entry,
  };

  final comparisons = <Map<String, Object?>>[];
  var unchanged = 0;
  var changed = 0;
  var missingBaseline = 0;
  var missingCurrent = 0;

  for (final entry in currentEntries) {
    final id = entry['id']! as String;
    final baseline = baselineById[id];
    if (baseline == null) {
      missingBaseline += 1;
      comparisons.add(<String, Object?>{
        'id': id,
        'status': 'missing_baseline',
        'text': entry['text'],
      });
      continue;
    }

    final baselineAnalysis = WavAnalysis.fromMap(
      baseline['analysis']! as Map<String, Object?>,
    );
    final currentAnalysis = WavAnalysis.fromMap(
      entry['analysis']! as Map<String, Object?>,
    );
    final comparison = wavAnalysisService.compare(
      baselineAnalysis,
      currentAnalysis,
    );
    final status = comparison.identicalPcm ? 'unchanged' : 'changed';
    if (comparison.identicalPcm) {
      unchanged += 1;
    } else {
      changed += 1;
    }

    comparisons.add(<String, Object?>{
      'id': id,
      'status': status,
      'text': entry['text'],
      'baselinePcmSha256': baselineAnalysis.pcmSha256,
      'currentPcmSha256': currentAnalysis.pcmSha256,
      'baselineWavSha256': baselineAnalysis.wavSha256,
      'currentWavSha256': currentAnalysis.wavSha256,
      'comparison': comparison.toMap(),
    });
  }

  for (final entry in baselineEntries) {
    final id = entry['id']! as String;
    if (currentById.containsKey(id)) {
      continue;
    }
    missingCurrent += 1;
    comparisons.add(<String, Object?>{
      'id': id,
      'status': 'missing_current',
      'text': entry['text'],
    });
  }

  final comparisonFile = File(
    p.join(currentDirectory.path, _probeComparisonFileName),
  );
  final comparisonReport = <String, Object?>{
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'baselineDirectory': baselineDirectory.path,
    'currentDirectory': currentDirectory.path,
    'unchanged': unchanged,
    'changed': changed,
    'missingBaseline': missingBaseline,
    'missingCurrent': missingCurrent,
    'entries': comparisons,
  };
  await comparisonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(comparisonReport),
    flush: true,
  );

  print(
    'Comparison summary: $changed changed, $unchanged unchanged, '
    '$missingBaseline missing baseline, $missingCurrent missing current.',
  );
  print('Comparison: ${comparisonFile.path}');
}

String _sanitizeProbeId(String id) {
  final sanitized = id
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  if (sanitized.isEmpty) {
    return 'probe';
  }
  return sanitized;
}
