import 'package:flutter/material.dart';
import '../services/modernbooknlp_analysis.dart';
import 'preparation_status.dart';

class ModernBookNlpSettings extends StatelessWidget {
  const ModernBookNlpSettings({
    super.key,
    required this.analysis,
    this.setEnabled,
  });
  final ModernBookNlpAnalysis analysis;
  final Future<void> Function(bool)? setEnabled;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: analysis,
    builder: (context, _) {
      final progress = analysis.progress;
      final done = progress?['completed'], total = progress?['total'];
      final fraction = done is num && total is num && total > 0
          ? (done / total).clamp(0.0, 1.0).toDouble()
          : null;
      final message =
          analysis.error ??
          progress?['message'] as String? ??
          (analysis.result != null
              ? '${analysis.restoredFromBook ? 'Restored saved book analysis. ' : ''}${analysis.completedWindows} analysis inputs completed; ${(analysis.result!['quotes'] as List).length} quotations in the latest input.'
              : analysis.ready
              ? 'Ready to analyze the next chapter.'
              : 'Not running.');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('Chapter analysis with ModernBookNLP'),
          const Text(
            'Analyze chapters when a document opens. Fish waits for the chapter’s analysis before generating new speech.',
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(message),
                  if (progress != null)
                    MeasuredProgress(
                      fraction: fraction,
                      label: total is num
                          ? '$done / $total ${progress['unit'] ?? ''}'
                          : null,
                    ),
                ],
              ),
            ),
          ),
          Wrap(
            children: [
              TextButton(
                key: const Key('modernbooknlp-prepare'),
                onPressed: analysis.enabled && analysis.error == null
                    ? null
                    : setEnabled == null
                    ? analysis.enable
                    : () => setEnabled!(true),
                child: Text(
                  analysis.error == null
                      ? 'Enable chapter analysis'
                      : 'Retry analysis',
                ),
              ),
              TextButton(
                key: const Key('modernbooknlp-stop'),
                onPressed: !analysis.enabled
                    ? null
                    : setEnabled == null
                    ? analysis.stop
                    : () => setEnabled!(false),
                child: const Text('Stop'),
              ),
            ],
          ),
        ],
      );
    },
  );
}
