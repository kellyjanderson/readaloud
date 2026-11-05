import 'package:flutter/material.dart';
import '../services/modernbooknlp_analysis.dart';
import 'preparation_status.dart';

class ModernBookNlpSettings extends StatelessWidget {
  const ModernBookNlpSettings({super.key, required this.analysis});
  final ModernBookNlpAnalysis analysis;
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
              ? '${analysis.completedWindows} windows evaluated; ${(analysis.result!['quotes'] as List).length} quotations in the latest window.'
              : analysis.ready
              ? 'Ready for a reading window.'
              : 'Not running.');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('ModernBookNLP evaluation'),
          const Text(
            'Experimental second-pass analysis. Results are diagnostic and do not yet change character voices or dialogue.',
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
                    : analysis.enable,
                child: Text(
                  analysis.error == null
                      ? 'Prepare and evaluate'
                      : 'Retry analysis',
                ),
              ),
              TextButton(
                key: const Key('modernbooknlp-stop'),
                onPressed: analysis.enabled ? analysis.stop : null,
                child: const Text('Stop'),
              ),
            ],
          ),
        ],
      );
    },
  );
}
