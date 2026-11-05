import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';

void main() {
  final root = Platform.environment['READALOUD_MODERNBOOKNLP_ROOT'];
  test(
    'real offline CPU provider crosses Dart process and source-coordinate boundary',
    () async {
      final provider = ModernBookNlpProvider(
        pythonPath:
            Platform.environment['READALOUD_MODERNBOOKNLP_PYTHON'] ??
            '${Directory.current.path}/.venv/bin/python',
        helperPath: '${Directory.current.path}/assets/modernbooknlp_worker.py',
        runtimePath: root!,
      );
      addTearDown(provider.close);
      final result = await provider.analyze(
        ModernBookNlpRequest(
          requestId: 'local',
          ownerId: 'test',
          workId: 'fixture',
          sourceRevision: 'v1',
          analysisRevision: 1,
          sequence: 1,
          text:
              'Ada opened the gate. "Come inside," Ada said. Bruno smiled. "Thank you," Bruno replied.',
        ),
      );
      expect(result['quotes'], hasLength(2));
      expect(
        result['linguisticArtifacts']['files'].keys,
        unorderedEquals(['tokens', 'entities', 'quotes', 'book']),
      );
      expect(
        result['linguisticArtifacts']['files']['book'],
        contains('characters'),
      );
      expect(
        (result['quotes'] as List).map((q) => q['entityId']).toSet(),
        hasLength(2),
      );
      expect(result['peakRssBytes'], greaterThan(0));
      final pid = provider.processId;
      final second = await provider.analyze(
        ModernBookNlpRequest(
          requestId: 'second',
          ownerId: 'test',
          workId: 'fixture',
          sourceRevision: 'v1',
          analysisRevision: 1,
          sequence: 2,
          text: '"I will return," Miriam said.',
        ),
      );
      expect(provider.processId, pid);
      expect(second['reusedModel'], true);
      expect(second['loadSeconds'], lessThan(0.05));
      stdout.writeln(
        'Resident second load=${second['loadSeconds']} inference=${second['inferenceSeconds']} pid=$pid',
      );
      await provider.close();
      expect(
        (await Process.run('/bin/kill', ['-0', '$pid'])).exitCode,
        isNot(0),
      );

      stdout.writeln(
        'ModernBookNLP load=${result['loadSeconds']} inference=${result['inferenceSeconds']} peakRSS=${result['peakRssBytes']}',
      );
    },
    skip: root == null
        ? 'Set READALOUD_MODERNBOOKNLP_ROOT for optional real-model qualification'
        : false,
  );
}
