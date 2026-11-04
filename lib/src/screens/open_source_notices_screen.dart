import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const openSourceNoticesAsset = 'third_party/licenses/NOTICES.txt';
const _maximumNoticeBytes = 4 * 1024 * 1024;
final _activeNoticeLoads = Expando<Future<List<String>>>('notice asset jobs');

/// Reads the complete bundled snapshot. Decoding and sectioning run off the
/// native UI isolate; only bounded, visible sections are laid out by Flutter.
Future<List<String>> loadOpenSourceNoticeSections(AssetBundle bundle) {
  final active = _activeNoticeLoads[bundle];
  if (active != null) return active;
  late final Future<List<String>> job;
  job = _readNoticeSections(bundle).whenComplete(() {
    if (identical(_activeNoticeLoads[bundle], job)) {
      _activeNoticeLoads[bundle] = null;
    }
  });
  _activeNoticeLoads[bundle] = job;
  return job;
}

Future<List<String>> _readNoticeSections(AssetBundle bundle) async {
  final bytes = await bundle.load(openSourceNoticesAsset);
  if (bytes.lengthInBytes == 0 || bytes.lengthInBytes > _maximumNoticeBytes) {
    throw const FormatException(
      'Notice snapshot is empty or exceeds its limit',
    );
  }
  return compute(
    _decodeNoticeSections,
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
}

List<String> _decodeNoticeSections(Uint8List bytes) {
  final text = utf8.decode(bytes);
  final sections = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + 8000).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end - 1);
      if (newline >= start) {
        end = newline + 1;
      } else if (text.codeUnitAt(end) >= 0xDC00 &&
          text.codeUnitAt(end) <= 0xDFFF) {
        end--;
      }
    }
    sections.add(text.substring(start, end));
    start = end;
  }
  return sections;
}

class OpenSourceNoticesScreen extends StatefulWidget {
  const OpenSourceNoticesScreen({super.key, this.bundle});

  final AssetBundle? bundle;

  @override
  State<OpenSourceNoticesScreen> createState() =>
      _OpenSourceNoticesScreenState();
}

class _OpenSourceNoticesScreenState extends State<OpenSourceNoticesScreen> {
  final _scrollController = ScrollController();
  final _scrollFocus = FocusNode(debugLabel: 'Open Source Notices text');
  Future<List<String>>? _sections;
  Timer? _slowTimer;
  Timer? _timeoutTimer;
  bool _takingLonger = false;
  bool _timedOut = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sections == null) _load();
  }

  void _load() {
    final generation = ++_generation;
    _takingLonger = false;
    _timedOut = false;
    _slowTimer?.cancel();
    _timeoutTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && generation == _generation) {
        setState(() => _takingLonger = true);
      }
    });
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && generation == _generation) {
        setState(() => _timedOut = true);
      }
    });
    // Timeout/pop cancel result consumption best-effort. AssetBundle.load and
    // compute cannot be interrupted here: the capped finite job retains its
    // own lifetime until completion, then releases the bundle's active slot.
    // Reopening attaches to that same job; Retry cannot overlap it. Results
    // after timeout never replace the timeout state, and disposed routes ignore
    // both successes and failures. Application shutdown terminates the worker.
    _sections =
        loadOpenSourceNoticeSections(
          widget.bundle ?? DefaultAssetBundle.of(context),
        ).whenComplete(() {
          if (mounted && generation == _generation) {
            _slowTimer?.cancel();
            _timeoutTimer?.cancel();
          }
        });
  }

  @override
  void dispose() {
    ++_generation;
    _slowTimer?.cancel();
    _timeoutTimer?.cancel();
    _scrollController.dispose();
    _scrollFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.of(context).pop()),
          title: const Text('Open Source Notices'),
        ),
        body: SafeArea(
          child: FutureBuilder<List<String>>(
            future: _sections,
            builder: (context, snapshot) {
              if (_timedOut) {
                final settled =
                    snapshot.connectionState == ConnectionState.done;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Loading notices timed out.'),
                        const SizedBox(height: 16),
                        Text(
                          settled
                              ? 'You can retry or return to the reader.'
                              : 'The previous load is still active. Retry will be available when it finishes.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: settled ? () => setState(_load) : null,
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          autofocus: true,
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Return to reader'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _takingLonger
                              ? 'Loading is taking longer than expected. You can return to the reader while it finishes.'
                              : 'Loading notices…',
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Unable to load the bundled notices.'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(_load),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final sections = snapshot.requireData;
              return Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: Focus(
                  focusNode: _scrollFocus,
                  autofocus: true,
                  onFocusChange: (_) => setState(() {}),
                  onKeyEvent: (_, event) {
                    if (!_scrollFocus.hasPrimaryFocus ||
                        event is KeyUpEvent ||
                        !_scrollController.hasClients) {
                      return KeyEventResult.ignored;
                    }
                    final position = _scrollController.position;
                    final key = event.logicalKey;
                    final destination = switch (key) {
                      LogicalKeyboardKey.arrowDown => position.pixels + 48,
                      LogicalKeyboardKey.arrowUp => position.pixels - 48,
                      LogicalKeyboardKey.pageDown =>
                        position.pixels + position.viewportDimension * 0.9,
                      LogicalKeyboardKey.pageUp =>
                        position.pixels - position.viewportDimension * 0.9,
                      LogicalKeyboardKey.home => position.minScrollExtent,
                      LogicalKeyboardKey.end => position.maxScrollExtent,
                      _ => null,
                    };
                    if (destination == null) return KeyEventResult.ignored;
                    _scrollController.jumpTo(
                      destination.clamp(
                        position.minScrollExtent,
                        position.maxScrollExtent,
                      ),
                    );
                    return KeyEventResult.handled;
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        width: 2,
                        color: _scrollFocus.hasFocus
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: ListView.builder(
                      key: const Key('open-source-notices-list'),
                      controller: _scrollController,
                      padding: const EdgeInsets.all(24),
                      itemCount: sections.length,
                      itemBuilder: (context, index) => SelectableText(
                        sections[index],
                        key: ValueKey('notice-section-$index'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
