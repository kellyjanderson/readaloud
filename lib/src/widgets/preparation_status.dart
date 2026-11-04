import 'dart:async';

import 'package:flutter/material.dart';

import '../models/document_preparation.dart';
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

  @override
  State<PreparationStatus> createState() => _PreparationStatusState();
}

class _PreparationStatusState extends State<PreparationStatus> {
  bool _details = false;
  final _completed = <PreparationStage, String?>{};
  final _timers = <PreparationStage, Timer>{};
  final _fading = <PreparationStage>{};
  final _hidden = <PreparationStage>{};

  @override
  void initState() {
    super.initState();
    _reconcile();
  }

  @override
  void didUpdateWidget(PreparationStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcile();
  }

  void _forget(PreparationStage stage) {
    _timers.remove(stage)?.cancel();
    _completed.remove(stage);
    _fading.remove(stage);
    _hidden.remove(stage);
  }

  void _reconcile() {
    final stages = {for (final p in widget.progress) p.stage: p};
    for (final stage in _completed.keys.toList()) {
      final p = stages[stage];
      if (p == null ||
          p.state != PreparationWorkState.complete ||
          p.workRevision != _completed[stage]) {
        _forget(stage);
      }
    }
    for (final p in stages.values) {
      if (p.state != PreparationWorkState.complete ||
          _completed.containsKey(p.stage)) {
        continue;
      }
      _completed[p.stage] = p.workRevision;
      _timers[p.stage] = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        setState(() => _fading.add(p.stage));
        _timers[p.stage] = Timer(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _hidden.add(p.stage));
          _timers.remove(p.stage);
        });
      });
    }
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  int _priority(PreparationProgress p) => switch (p.state) {
    PreparationWorkState.failed || PreparationWorkState.stalled => 0,
    PreparationWorkState.working => 1,
    PreparationWorkState.waiting => 2,
    PreparationWorkState.cancelled => 3,
    PreparationWorkState.complete => 4,
  };

  @override
  Widget build(BuildContext context) {
    final stages = widget.progress.toList()
      ..sort((a, b) {
        final order = _priority(a).compareTo(_priority(b));
        return order != 0 ? order : a.stage.index.compareTo(b.stage.index);
      });
    final active = stages
        .where((p) => p.state == PreparationWorkState.working)
        .firstOrNull;
    final problem = stages
        .where(
          (p) =>
              p.state == PreparationWorkState.failed ||
              p.state == PreparationWorkState.stalled,
        )
        .firstOrNull;
    final paused = stages.any(
      (p) =>
          p.waitingReason?.startsWith('Prepared reading window is full') ??
          false,
    );
    final resource = widget.startupError == null
        ? widget.resourceProgress
        : null;
    final title =
        widget.startupError ??
        (problem == null
            ? null
            : '${_stageName(problem.stage)}: ${problem.error ?? problem.waitingReason ?? 'Needs attention'}') ??
        resource?.message ??
        widget.message ??
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
                  if (resource != null)
                    MeasuredProgress(
                      fraction: resource.fraction,
                      label: resourceProgressLabel(resource),
                    )
                  else if (widget.startupError == null &&
                      problem == null &&
                      active != null &&
                      !paused &&
                      !_details)
                    MeasuredProgress(
                      fraction: active.fraction,
                      label:
                          '${_stageName(active.stage)} · ${_counter(active)}',
                    ),
                  if (_details) ...[
                    const Divider(height: 20),
                    if (stages.isEmpty) const Text('No document activity yet.'),
                    for (final p in stages.where(
                      (p) => !_hidden.contains(p.stage),
                    ))
                      AnimatedOpacity(
                        key: ValueKey('activity-${p.stage.name}'),
                        opacity: _fading.contains(p.stage) ? 0 : 1,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 600),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${_stageName(p.stage)} · ${p.state.name}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              if (p.state == PreparationWorkState.working)
                                MeasuredProgress(
                                  fraction: p.fraction,
                                  label: _counter(p),
                                )
                              else
                                Text(
                                  _counter(p),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (p.error ?? p.waitingReason
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
          const SizedBox(width: 8),
          SizedBox(
            width: 128,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    onPressed: () => setState(() => _details = !_details),
                    child: Text(_details ? 'Hide activity' : 'Activity'),
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

String _counter(PreparationProgress p) {
  final counter = p.total == null
      ? '${p.completed} ${p.unit}; total unknown'
      : '${p.completed} of ${p.total} ${p.unit}';
  return '$counter${p.discovered == null ? '' : '; ${p.discovered} discovered so far; total may grow'}';
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
  return '${amount(p.completed ?? 0)} of ${amount(p.total!)}';
}

String _stageName(PreparationStage stage) => switch (stage) {
  PreparationStage.acquisition => 'Reading file',
  PreparationStage.parsing => 'Reading text',
  PreparationStage.normalization => 'Preparing text',
  PreparationStage.mapping => 'Mapping reading position',
  PreparationStage.analysis => 'Finding characters',
  PreparationStage.pronunciation => 'Preparing pronunciation',
  PreparationStage.planning => 'Preparing speech',
  PreparationStage.resources => 'Preparing voices',
  PreparationStage.synthesis => 'Generating audio',
  PreparationStage.persistence => 'Saving prepared document',
};
