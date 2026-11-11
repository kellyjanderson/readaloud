import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/document_preparation.dart';
import '../models/reader_operation.dart';
import '../services/tts_engine.dart';

/// A bar is evidence of measured work, never a substitute for missing telemetry.
class MeasuredProgress extends StatelessWidget {
  const MeasuredProgress({super.key, required this.fraction, this.label});
  final double? fraction;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final value = fraction;
    if (value == null || !value.isFinite || value < 0) {
      return Text(label ?? 'Waiting for a measurable total');
    }
    if (value >= 1) {
      return Text(label == null ? 'Finishing…' : '$label · Finishing…');
    }
    final percent = '${(value * 100).floor()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label == null ? percent : '$label · $percent',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: value, semanticsLabel: label),
      ],
    );
  }
}

/// UI-only history: one entry per stage, with no expiry of active work/errors.
/// Timers own only presentation and are cancelled on restart/removal/disposal.
class PreparationStatus extends StatefulWidget {
  const PreparationStatus({
    super.key,
    required this.progress,
    required this.isImporting,
    required this.isInitializing,
    required this.isComplete,
    this.resourceProgress,
    this.message,
    this.startupError,
    this.onCancel,
    this.onRetry,
    this.onRetryStartup,
    this.onClearFailure,
    this.operations,
    this.activityExpanded,
    this.onActivityExpandedChanged,
  });

  final Iterable<PreparationProgress> progress;
  final bool isImporting;
  final bool isInitializing;
  final bool isComplete;
  final TtsResourceProgress? resourceProgress;
  final String? message;
  final String? startupError;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRetryStartup;
  final ValueChanged<ReaderOperation>? onClearFailure;
  final List<ReaderOperation>? operations;
  final bool? activityExpanded;
  final ValueChanged<bool>? onActivityExpandedChanged;

  @override
  State<PreparationStatus> createState() => _PreparationStatusState();
}

class _PreparationStatusState extends State<PreparationStatus> {
  bool _details = false;
  bool _reducedMotion = false;
  final _completed = <String>{};
  final _timers = <String, Timer>{};
  final _fading = <String>{};
  final _hidden = <String>{};

  List<ReaderOperation> get _allOperations =>
      widget.operations ??
      [
        for (final p in widget.progress) p.toOperation(),
        if (widget.resourceProgress case final resource?)
          resource.toOperation(),
      ];

  @override
  void initState() {
    super.initState();
    _details = widget.activityExpanded ?? false;
    _reconcile();
  }

  @override
  void didUpdateWidget(PreparationStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _details = widget.activityExpanded ?? _details;
    _reconcile();
  }

  void _forget(String stage) {
    _timers.remove(stage)?.cancel();
    _completed.remove(stage);
    _fading.remove(stage);
    _hidden.remove(stage);
  }

  void _reconcile() {
    final stages = {for (final p in _allOperations) p.key: p};
    for (final stage in _completed.toList()) {
      final p = stages[stage];
      if (p == null || p.state != OperationState.succeeded) {
        _forget(stage);
      }
    }
    for (final p in stages.values) {
      if (p.state != OperationState.succeeded || _completed.contains(p.key)) {
        continue;
      }
      _completed.add(p.key);
      _timers[p.key] = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        if (_reducedMotion) {
          setState(() => _hidden.add(p.key));
          _timers.remove(p.key);
          return;
        }
        setState(() => _fading.add(p.key));
        _timers[p.key] = Timer(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _hidden.add(p.key));
          _timers.remove(p.key);
        });
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      for (final key in _fading) {
        _timers.remove(key)?.cancel();
        _hidden.add(key);
      }
    }
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  int _priority(ReaderOperation p) => p.state.isTerminal ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final stages = _allOperations.toList()
      ..sort((a, b) {
        final order = _priority(a).compareTo(_priority(b));
        return order != 0 ? order : b.updatedAt.compareTo(a.updatedAt);
      });
    final currentByLane = <String, ReaderOperation>{};
    for (final operation in stages.where((p) => p.readerBlocking)) {
      final previous = currentByLane[operation.lane];
      if (previous == null ||
          operation.ownerEpoch > previous.ownerEpoch ||
          (operation.ownerEpoch == previous.ownerEpoch &&
              operation.updatedAt.isAfter(previous.updatedAt))) {
        currentByLane[operation.lane] = operation;
      }
    }
    final epochs = <OperationOwnerKind, int>{};
    for (final p in currentByLane.values) {
      final epoch = epochs[p.ownerKind];
      if (epoch == null || epoch < p.ownerEpoch) {
        epochs[p.ownerKind] = p.ownerEpoch;
      }
    }
    final current = currentByLane.values
        .where((p) => p.readerBlocking && epochs[p.ownerKind] == p.ownerEpoch)
        .toList();
    final active = current
        .where(
          (p) =>
              p.visibleState == OperationState.running ||
              p.visibleState == OperationState.finalizing ||
              p.state == OperationState.queued,
        )
        .firstOrNull;
    final problem = current
        .where((p) => p.state == OperationState.failed || p.error != null)
        .firstOrNull;
    final paused = current.any((p) => p.state == OperationState.idleDemand);
    final resource = current
        .where(
          (p) => p.ownerKind == OperationOwnerKind.model && !p.state.isTerminal,
        )
        .firstOrNull;
    final winner = problem ?? resource ?? active;
    final title =
        widget.startupError ??
        (problem == null
            ? null
            : '${_operationStageName(problem.stage)}: ${problem.error ?? problem.message ?? 'Needs attention'}') ??
        resource?.message ??
        widget.message ??
        (active == null ? null : '${_operationStageName(active.stage)}…') ??
        (widget.isInitializing
            ? 'Preparing speech — you can open a document now.'
            : paused
            ? 'Ready to read — more will be prepared as you listen.'
            : widget.isComplete
            ? 'Ready to read'
            : widget.isImporting
            ? 'Preparing your document…'
            : 'Open a document to start reading');
    return SizedBox(
      key: const Key('preparation-status'),
      height: _details ? 260 : 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (widget.startupError == null &&
                        problem == null &&
                        winner != null &&
                        !_details)
                      MeasuredProgress(
                        fraction:
                            winner.visibleState == OperationState.finalizing
                            ? 1
                            : winner.fraction,
                        label:
                            '${_operationStageName(winner.stage)} · ${_operationCounter(winner)}',
                      ),
                    if (_details) ...[
                      const Divider(height: 20),
                      if (stages.isEmpty)
                        const Text('No document activity yet.'),
                      for (final p in stages.where(
                        (p) => !_hidden.contains(p.key),
                      ))
                        AnimatedOpacity(
                          key: ValueKey(
                            p.operationId.startsWith('legacy:') &&
                                    p.scope.isEmpty
                                ? 'activity-${p.stage}'
                                : 'activity-${p.key}',
                          ),
                          opacity: _fading.contains(p.key) ? 0 : 1,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 600),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${_operationStageName(p.stage)}${p.scope.isEmpty ? '' : ' · ${p.scope}'} · ${p.visibleState.name}',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                if (p.state == OperationState.running ||
                                    p.state == OperationState.finalizing)
                                  MeasuredProgress(
                                    fraction: p.fraction,
                                    label: _operationCounter(p),
                                  )
                                else
                                  Text(
                                    _operationCounter(p),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (p.error ?? p.message
                                    case final String detail)
                                  Text(detail),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 128,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (problem != null &&
                      problem.recoveryActions.contains(
                        OperationRecoveryAction.clear,
                      ) &&
                      widget.onClearFailure != null)
                    TextButton(
                      key: const Key('clear-operation-failure'),
                      onPressed: () => widget.onClearFailure!(problem),
                      child: const Text('Clear error'),
                    ),
                  if (widget.onCancel != null)
                    TextButton(
                      key: const Key('cancel-preparation'),
                      onPressed: widget.onCancel,
                      child: const Text('Cancel document'),
                    ),
                  if (widget.onRetry != null)
                    TextButton(
                      key: const Key('retry-preparation'),
                      onPressed: widget.onRetry,
                      child: const Text('Retry document'),
                    ),
                  if (widget.startupError != null &&
                      widget.onRetryStartup != null)
                    TextButton(
                      key: const Key('retry-startup'),
                      onPressed: widget.onRetryStartup,
                      child: const Text('Retry speech'),
                    ),
                  TextButton(
                    key: const Key('toggle-activity'),
                    onPressed: () {
                      setState(() => _details = !_details);
                      widget.onActivityExpandedChanged?.call(_details);
                    },
                    child: Text(_details ? 'Hide activity' : 'Activity'),
                  ),

                  TextButton.icon(
                    key: const Key('copy-reader-status'),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(
                        text: [
                          title,
                          if (resource != null) _operationCounter(resource),
                          for (final p in stages)
                            '${_operationStageName(p.stage)} · ${p.scope} · ${p.visibleState.name} · ${_operationCounter(p)}'
                                '${p.error == null ? '' : '\n${p.error}'}'
                                '${p.message == null ? '' : '\n${p.message}'}',
                        ].join('\n\n'),
                      ),
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
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

String _operationCounter(ReaderOperation p) {
  if (!p.completedKnown) return 'Completed-work count not yet available';
  if (!p.hasValidCounter) return 'Waiting for valid completed-work accounting';
  final counter = p.totalUnits == null
      ? '${p.completedUnits} ${p.unit}; total unknown'
      : '${p.completedUnits} of ${p.totalUnits} ${p.unit}';
  return '$counter${p.discoveredUnits == null ? '' : '; ${p.discoveredUnits} discovered so far; total may grow'}';
}

String resourceProgressLabel(TtsResourceProgress p) {
  String amount(int n) => p.unit == 'bytes'
      ? n >= 1000000000
            ? '${(n / 1000000000).toStringAsFixed(1)} GB'
            : '${(n / 1000000).toStringAsFixed(1)} MB'
      : '$n ${p.unit}';
  if (p.total == null) {
    return p.completed == null
        ? 'Progress total not yet available'
        : '${amount(p.completed!)} completed; total unknown';
  }
  if (p.completed == null) {
    return 'Completed-work count not yet available; total ${amount(p.total!)}';
  }
  return '${amount(p.completed ?? 0)} of ${amount(p.total!)}';
}

String _operationStageName(String stage) => switch (stage) {
  'preparation' => 'Preparing document',
  'acquisition' => 'Reading file',
  'parsing' => 'Reading text',
  'normalization' => 'Preparing text',
  'mapping' => 'Mapping reading position',
  'analysis' => 'Finding characters',
  'pronunciation' => 'Preparing pronunciation',
  'planning' => 'Preparing speech',
  'resources' => 'Preparing voices',
  'synthesis' => 'Generating audio',
  'persistence' => 'Saving prepared document',
  _ => stage,
};
