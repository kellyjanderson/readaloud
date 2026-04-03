import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/app_launch_options.dart';

void main() {
  group('parseAppLaunchOptions', () {
    test('parses UI mode file inputs without headless', () {
      final result = parseAppLaunchOptions(<String>['article.pdf']);

      expect(result.options.headless, isFalse);
      expect(result.options.inputPaths, <String>['article.pdf']);
      expect(result.options.validationError, isNull);
    });

    test('parses headless export options', () {
      final result = parseAppLaunchOptions(<String>[
        '--headless',
        '--voice',
        'af_bella',
        '--speed',
        '1.15',
        '--output-dir',
        'exports',
        'article.pdf',
        'notes.txt',
      ]);

      expect(result.options.headless, isTrue);
      expect(result.options.voiceId, 'af_bella');
      expect(result.options.speed, 1.15);
      expect(result.options.outputDirectory, 'exports');
      expect(result.options.inputPaths, <String>['article.pdf', 'notes.txt']);
      expect(result.options.validationError, isNull);
    });

    test('rejects single output path for multiple files', () {
      final result = parseAppLaunchOptions(<String>[
        '--headless',
        '--output',
        'combined.wav',
        'article.pdf',
        'notes.txt',
      ]);

      expect(
        result.options.validationError,
        '--output may be used only with a single input file.',
      );
    });

    test('parses pronunciation probe mode and implies headless', () {
      final result = parseAppLaunchOptions(<String>[
        '--probe-file',
        'probes.txt',
        '--output-dir',
        'probe-runs/current',
        '--compare-dir',
        'probe-runs/baseline',
      ]);

      expect(result.options.headless, isTrue);
      expect(result.options.probeFile, 'probes.txt');
      expect(result.options.outputDirectory, 'probe-runs/current');
      expect(result.options.compareDirectory, 'probe-runs/baseline');
      expect(result.options.validationError, isNull);
    });

    test('parses inline pronunciation probe text', () {
      final result = parseAppLaunchOptions(<String>[
        '--probe-text',
        'for the road.',
        '--probe-text',
        "John's hand.",
      ]);

      expect(result.options.headless, isTrue);
      expect(
        result.options.probeTexts,
        <String>['for the road.', "John's hand."],
      );
      expect(result.options.probeFile, isNull);
      expect(result.options.validationError, isNull);
    });

    test('rejects pronunciation probe mode with input files', () {
      final result = parseAppLaunchOptions(<String>[
        '--probe-file',
        'probes.txt',
        'article.txt',
      ]);

      expect(
        result.options.validationError,
        'Pronunciation probe mode does not accept input files.',
      );
    });

    test('rejects mixed probe file and inline probe text', () {
      final result = parseAppLaunchOptions(<String>[
        '--probe-file',
        'probes.txt',
        '--probe-text',
        'for the road.',
      ]);

      expect(
        result.options.validationError,
        'Use either --probe-file or --probe-text, not both.',
      );
    });

    test('parses sentence probe mode and implies headless', () {
      final result = parseAppLaunchOptions(<String>[
        '--sentence-probe-file',
        'project/testdocs/Love.txt',
        '--voice',
        'af_bella',
        '--output-dir',
        'sentence-runs/current',
      ]);

      expect(result.options.headless, isTrue);
      expect(result.options.sentenceProbeFile, 'project/testdocs/Love.txt');
      expect(result.options.voiceId, 'af_bella');
      expect(result.options.outputDirectory, 'sentence-runs/current');
      expect(result.options.validationError, isNull);
    });

    test('rejects sentence probe mode with trailing input files', () {
      final result = parseAppLaunchOptions(<String>[
        '--sentence-probe-file',
        'project/testdocs/Love.txt',
        'article.txt',
      ]);

      expect(
        result.options.validationError,
        'Sentence probe mode does not accept trailing input files.',
      );
    });
  });
}
