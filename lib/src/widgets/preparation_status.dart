import 'package:flutter/material.dart';

import '../models/document_preparation.dart';

/// A stable, scrollable status region. Counters belong to their own stage;
/// finishing parsing never implies that resources or persistence are ready.
class PreparationStatus extends StatelessWidget {
  const PreparationStatus({
    super.key,
    required this.progress,
    required this.isImporting,
    required this.isInitializing,
    required this.isComplete,
    this.message,
    this.startupError,
    this.onCancel,
    this.onRetry,
    this.onRetryStartup,
  });

  final Iterable<PreparationProgress> progress;
  final bool isImporting;
  final bool isInitializing;
  final bool isComplete;
  final String? message;
  final String? startupError;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRetryStartup;

  @override
  Widget build(BuildContext context) {
    final stages = progress.toList();
    return SizedBox(
      key: const Key('preparation-status'),
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      startupError ??
                          message ??
                          (isInitializing
                              ? 'Preparing speech resources. You can open a document now.'
                              : isImporting
                              ? 'Preparing the next reading range…'
                              : isComplete
                              ? 'Ready to read'
                              : 'Partial document — more ranges are available as you read.'),
                    ),
                    if (startupError != null &&
                        message != null &&
                        message != startupError)
                      Text(message!),
                    if (isInitializing) ...[
                      const SizedBox(height: 4),
                      const LinearProgressIndicator(
                        semanticsLabel: 'Speech resources; total work unknown',
                      ),
                    ],
                    for (final stage in stages) ...[
                      const SizedBox(height: 4),
                      Text(_stageDescription(stage)),
                      if (stage.state != PreparationWorkState.failed &&
                          stage.state != PreparationWorkState.cancelled)
                        LinearProgressIndicator(
                          // A finished counter does not imply a finished stage.
                          value: stage.state == PreparationWorkState.complete
                              ? 1
                              : stage.total != null &&
                                    stage.total! > 0 &&
                                    stage.completed < stage.total!
                              ? stage.fraction?.clamp(0, 1)
                              : null,
                          semanticsLabel: _stageDescription(stage),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (onCancel != null || onRetry != null || startupError != null)
            SizedBox(
              width: 128,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (onCancel != null)
                      TextButton(
                        key: const Key('cancel-preparation'),
                        onPressed: onCancel,
                        child: const Text('Cancel'),
                      ),
                    if (onRetry != null)
                      TextButton(
                        key: const Key('retry-preparation'),
                        onPressed: onRetry,
                        child: const Text('Retry document'),
                      ),
                    if (startupError != null && onRetryStartup != null)
                      TextButton(
                        key: const Key('retry-startup'),
                        onPressed: onRetryStartup,
                        child: const Text('Retry speech'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _stageDescription(PreparationProgress progress) {
  final total = progress.total;
  final counter = total == null
      ? '${progress.completed} ${progress.unit}; total unknown'
      : '${progress.completed} of $total ${progress.unit}';
  final discovered = progress.discovered == null
      ? ''
      : '; ${progress.discovered} discovered so far; total may grow';
  final detail = progress.error ?? progress.waitingReason;
  return '${progress.scope ?? progress.stage.name}: $counter$discovered — '
      '${progress.state.name}${detail == null ? '' : ': $detail'}';
}
