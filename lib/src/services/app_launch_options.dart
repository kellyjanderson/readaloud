import 'package:args/args.dart';

class AppLaunchOptions {
  const AppLaunchOptions({
    this.headless = false,
    this.showHelp = false,
    this.inputPaths = const <String>[],
    this.probeTexts = const <String>[],
    this.sentenceProbeFile,
    this.voiceId,
    this.speed,
    this.outputPath,
    this.outputDirectory,
    this.probeFile,
    this.compareDirectory,
    this.validationError,
  });

  final bool headless;
  final bool showHelp;
  final List<String> inputPaths;
  final List<String> probeTexts;
  final String? sentenceProbeFile;
  final String? voiceId;
  final double? speed;
  final String? outputPath;
  final String? outputDirectory;
  final String? probeFile;
  final String? compareDirectory;
  final String? validationError;

  bool get hasInputs => inputPaths.isNotEmpty;
  bool get hasValidationError => validationError != null;

  AppLaunchOptions copyWith({
    bool? headless,
    bool? showHelp,
    List<String>? inputPaths,
    List<String>? probeTexts,
    String? sentenceProbeFile,
    String? voiceId,
    double? speed,
    String? outputPath,
    String? outputDirectory,
    String? probeFile,
    String? compareDirectory,
    String? validationError,
  }) {
    return AppLaunchOptions(
      headless: headless ?? this.headless,
      showHelp: showHelp ?? this.showHelp,
      inputPaths: inputPaths ?? this.inputPaths,
      probeTexts: probeTexts ?? this.probeTexts,
      sentenceProbeFile: sentenceProbeFile ?? this.sentenceProbeFile,
      voiceId: voiceId ?? this.voiceId,
      speed: speed ?? this.speed,
      outputPath: outputPath ?? this.outputPath,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      probeFile: probeFile ?? this.probeFile,
      compareDirectory: compareDirectory ?? this.compareDirectory,
      validationError: validationError ?? this.validationError,
    );
  }
}

class AppLaunchParseResult {
  const AppLaunchParseResult({
    required this.options,
    required this.usage,
  });

  final AppLaunchOptions options;
  final String usage;
}

AppLaunchParseResult parseAppLaunchOptions(List<String> args) {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addFlag(
      'headless',
      abbr: 'H',
      negatable: false,
      help: 'Run export without launching the normal UI.',
    )
    ..addOption(
      'voice',
      help: 'Voice id to use for playback or headless export.',
    )
    ..addOption(
      'speed',
      help: 'Speech speed multiplier, for example 1.0 or 1.15.',
    )
    ..addOption(
      'output',
      help: 'Output WAV path for single-file headless export.',
    )
    ..addOption(
      'output-dir',
      help: 'Directory for one or more headless export outputs.',
    )
    ..addOption(
      'probe-file',
      help:
          'Run a pronunciation probe from a phrase list file. '
          'Each non-empty line is a phrase, or use "<id>\\t<phrase>".',
    )
    ..addOption(
      'sentence-probe-file',
      help:
          'Import a real document file and export one WAV per speech sentence, '
          'with a combined harness log and per-sentence trace references.',
    )
    ..addMultiOption(
      'probe-text',
      help:
          'Run a pronunciation probe from inline text. '
          'Repeat the option for multiple phrases.',
      valueHelp: 'phrase',
    )
    ..addOption(
      'compare-dir',
      help:
          'Compare the current pronunciation probe run to a previous probe output directory.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print command-line help.',
    );

  final usage = [
    'Usage: read_aloud [options] [file ...]',
    '',
    parser.usage,
    '',
    'Examples:',
    '  read_aloud notes.txt',
    '  read_aloud --headless --voice af_bella report.pdf',
    '  read_aloud --headless --output-dir exports article.html notes.txt',
    '  read_aloud --probe-file probes.txt --output-dir pronunciation-runs/baseline',
    '  read_aloud --probe-text "for the road." --output-dir pronunciation-runs/try-1',
    '  read_aloud --probe-file probes.txt --output-dir pronunciation-runs/try-2 --compare-dir pronunciation-runs/baseline',
    '  read_aloud --sentence-probe-file project/testdocs/Love.txt --voice af_bella',
  ].join('\n');

  try {
    final results = parser.parse(args);
    final speedText = results['speed'] as String?;
    final parsedSpeed = speedText == null || speedText.trim().isEmpty
        ? null
        : double.tryParse(speedText);
    final probeFile = (results['probe-file'] as String?)?.trim().isEmpty ?? true
        ? null
        : (results['probe-file'] as String).trim();
    final sentenceProbeFile =
        (results['sentence-probe-file'] as String?)?.trim().isEmpty ?? true
        ? null
        : (results['sentence-probe-file'] as String).trim();
    final compareDirectory =
        (results['compare-dir'] as String?)?.trim().isEmpty ?? true
        ? null
        : (results['compare-dir'] as String).trim();
    final probeTexts = (results['probe-text'] as List<String>)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    var options = AppLaunchOptions(
      headless:
          (results['headless'] as bool) ||
          probeFile != null ||
          probeTexts.isNotEmpty ||
          sentenceProbeFile != null,
      showHelp: results['help'] as bool,
      inputPaths: results.rest,
      probeTexts: probeTexts,
      sentenceProbeFile: sentenceProbeFile,
      voiceId: (results['voice'] as String?)?.trim().isEmpty ?? true
          ? null
          : (results['voice'] as String).trim(),
      speed: parsedSpeed,
      outputPath: (results['output'] as String?)?.trim().isEmpty ?? true
          ? null
          : (results['output'] as String).trim(),
      outputDirectory:
          (results['output-dir'] as String?)?.trim().isEmpty ?? true
          ? null
          : (results['output-dir'] as String).trim(),
      probeFile: probeFile,
      compareDirectory: compareDirectory,
    );

    if (options.showHelp) {
      return AppLaunchParseResult(options: options, usage: usage);
    }

    final validationError = _validateLaunchOptions(options, speedText);
    if (validationError != null) {
      options = options.copyWith(validationError: validationError);
    }

    return AppLaunchParseResult(options: options, usage: usage);
  } on ArgParserException catch (error) {
    return AppLaunchParseResult(
      options: AppLaunchOptions(validationError: error.message),
      usage: usage,
    );
  } on FormatException catch (error) {
    return AppLaunchParseResult(
      options: AppLaunchOptions(validationError: error.message),
      usage: usage,
    );
  }
}

String? _validateLaunchOptions(AppLaunchOptions options, String? speedText) {
  if (speedText != null &&
      speedText.trim().isNotEmpty &&
      options.speed == null) {
    return 'Speed must be a valid number.';
  }

  if (options.outputPath != null && options.outputDirectory != null) {
    return 'Use either --output or --output-dir, not both.';
  }

  if (options.probeFile != null && options.probeTexts.isNotEmpty) {
    return 'Use either --probe-file or --probe-text, not both.';
  }

  if (options.sentenceProbeFile != null &&
      (options.probeFile != null || options.probeTexts.isNotEmpty)) {
    return 'Use sentence probe mode by itself, not with phrase probe options.';
  }

  if (options.probeFile != null || options.probeTexts.isNotEmpty) {
    if (options.inputPaths.isNotEmpty) {
      return 'Pronunciation probe mode does not accept input files.';
    }
    if (options.outputPath != null) {
      return 'Pronunciation probe mode does not support --output. Use --output-dir.';
    }
    return null;
  }

  if (options.sentenceProbeFile != null) {
    if (options.inputPaths.isNotEmpty) {
      return 'Sentence probe mode does not accept trailing input files.';
    }
    if (options.outputPath != null) {
      return 'Sentence probe mode does not support --output. Use --output-dir.';
    }
    return null;
  }

  if (!options.headless) {
    return null;
  }

  if (options.inputPaths.isEmpty) {
    return 'Headless mode requires at least one input file.';
  }

  if (options.outputPath != null && options.inputPaths.length != 1) {
    return '--output may be used only with a single input file.';
  }

  return null;
}
