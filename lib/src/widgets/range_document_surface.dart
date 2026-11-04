import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../controllers/reader_controller.dart';
import '../models/document_preparation.dart';
import '../models/spoken_selection.dart';
import 'document_surface.dart';

/// A novel is a lazy list of immutable display ranges, not the active audio
/// fragment. Cells own their pending reads and release them on disposal.
class RangeDocumentSurface extends StatefulWidget {
  const RangeDocumentSurface({super.key, required this.controller});
  final ReaderController controller;
  @override
  State<RangeDocumentSurface> createState() => _RangeDocumentSurfaceState();
}

class _RangeDocumentSurfaceState extends State<RangeDocumentSurface> {
  final _scroll = ScrollController();
  final _list = ListController();
  final _keys = <int, GlobalKey>{};
  int? _lastActive;
  int _lastFollowTick = -1;

  @override
  void initState() {
    super.initState();
    _lastActive = widget.controller.activePreparedRangeSequence;
    _lastFollowTick = widget.controller.readingFocusState.recenterRequestTick;
  }

  @override
  void didUpdateWidget(covariant RangeDocumentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reader = widget.controller;
    final active = reader.activePreparedRangeSequence;
    final focus = reader.readingFocusState;
    final recenter = focus.recenterRequestTick != _lastFollowTick;
    if ((focus.shouldAutoFollow && active != _lastActive) || recenter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || active == null || !_list.isAttached) return;
        if (_keys[active]?.currentContext == null) {
          _list.jumpToItem(
            index: active - 1,
            scrollController: _scroll,
            alignment: 0.2,
          );
        }
      });
    }
    _lastActive = active;
    _lastFollowTick = focus.recenterRequestTick;
  }

  void _follow(int sequence, double fraction) {
    if (!mounted || !_scroll.hasClients) return;
    final range = _keys[sequence]?.currentContext?.findRenderObject();
    final viewport = context.findRenderObject();
    if (range is! RenderBox || viewport is! RenderBox || !range.hasSize) return;
    final top =
        range.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
    final target =
        top + fraction * (range.size.height - 48).clamp(0, double.infinity);
    final height = _scroll.position.viewportDimension;
    if (target >= height * 0.18 && target <= height * 0.72) return;
    final offset = (_scroll.offset + target - height * 0.22).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((offset - _scroll.offset).abs() < 24) return;
    unawaited(
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.controller;
    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction != ScrollDirection.idle &&
            reader.readingFocusState.shouldAutoFollow) {
          reader.suspendReaderFollow();
        }
        return false;
      },
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SuperListView.builder(
          key: const Key('whole-document-scroll'),
          controller: _scroll,
          listController: _list,
          cacheExtent: 400,
          itemCount: reader.preparedRangeCount + 1,
          itemBuilder: (context, index) {
            if (index == reader.preparedRangeCount &&
                reader.isPreparationComplete) {
              return Padding(
                key: const Key('document-end'),
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'End of document · ${reader.preparedWordCount} words',
                ),
              );
            }
            final sequence = index + 1;
            return _RangeCell(
              key: _keys.putIfAbsent(sequence, GlobalKey.new),
              sequence: sequence,
              reader: reader,
              onFocus: (fraction) => _follow(sequence, fraction),
            );
          },
        ),
      ),
    );
  }
}

class _RangeCell extends StatefulWidget {
  const _RangeCell({
    super.key,
    required this.sequence,
    required this.reader,
    required this.onFocus,
  });
  final int sequence;
  final ReaderController reader;
  final ValueChanged<double> onFocus;
  @override
  State<_RangeCell> createState() => _RangeCellState();
}

class _RangeCellState extends State<_RangeCell> {
  final _cancelled = Completer<void>();
  late Future<DocumentPreparationPublication?> _range;
  @override
  void initState() {
    super.initState();
    _range = _load();
  }

  Future<DocumentPreparationPublication?> _load() => widget.reader
      .readPreparedRange(widget.sequence, cancelled: _cancelled.future);
  @override
  void dispose() {
    _cancelled.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<DocumentPreparationPublication?>(
        future: _range,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SizedBox(
              height: 96,
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() => _range = _load()),
                  child: const Text(
                    'Could not load this part of the document. Retry',
                  ),
                ),
              ),
            );
          }
          final range = snapshot.data;
          if (range == null) {
            return const SizedBox(
              height: 96,
              child: Center(child: Text('Loading more text…')),
            );
          }
          final reader = widget.reader;
          final active = widget.sequence == reader.activePreparedRangeSequence;
          return DocumentSurface(
            key: ValueKey('display-range-${widget.sequence}'),
            document: range.fragment,
            inline: true,
            fontFamily: reader.fontFamily,
            fontScale: reader.fontScale,
            spokenSelection: active
                ? reader.spokenSelection
                : const SpokenSelection.none(),
            focusedDisplayBlockId: active
                ? reader.readingFocusState.activeDisplayBlockId
                : null,
            autoFollowActive:
                active && reader.readingFocusState.shouldAutoFollow,
            followRequestTick: active
                ? reader.readingFocusState.recenterRequestTick
                : 0,
            onInlineFocus: widget.onFocus,
          );
        },
      );
}
