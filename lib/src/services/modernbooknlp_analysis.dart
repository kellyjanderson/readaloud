import 'dart:async';
import 'package:flutter/foundation.dart';
import 'modernbooknlp_provider.dart';

/// Main-isolate owner of opt-in diagnostic refinement. One active window plus
/// one replaceable demand, with no playback/preparation dependency or voice edits.
class ModernBookNlpAnalysis extends ChangeNotifier {
  ModernBookNlpAnalysis(this.createProvider);
  final Future<ModernBookNlpProvider> Function() createProvider;
  ModernBookNlpProvider? _provider;
  ModernBookNlpRequest? _pending, _desired, _active;
  Future<void>? _work;
  bool enabled = false, ready = false, _closed = false, _analyzing = false;
  int _windowEpoch = 0, _session = 0, completedWindows = 0;
  String? error;
  Map<String, dynamic>? progress, result;
  String? _completedKey;
  bool get busy => _work != null;
  bool get hasPendingWindow => _pending != null;
  String _key(ModernBookNlpRequest r) =>
      '${r.ownerId}/${r.workId}/${r.sourceRevision}/${r.analysisRevision}/${r.sequence}';

  void offer(ModernBookNlpRequest request) {
    _desired = request;
    if (!enabled ||
        _closed ||
        _key(request) == _completedKey ||
        (_active != null && _key(request) == _key(_active!)) ||
        (_pending != null && _key(request) == _key(_pending!))) {
      return;
    }
    _pending = request;
    _kick();
  }

  void enable() {
    if (_closed) return;
    enabled = true;
    error = null;
    _pending = _desired;
    _kick();
  }

  void _kick() {
    if (_work != null || !enabled || _closed) return;
    _work = _run().whenComplete(() {
      _work = null;
      if (!_closed) notifyListeners();
      if (enabled && _pending != null && error == null) _kick();
    });
    notifyListeners();
  }

  Future<void> _run() async {
    final session = _session;
    bool current() => !_closed && enabled && session == _session;
    try {
      _provider ??= await createProvider();
      if (!current()) return;
      if (!ready) {
        progress = {
          'message': 'Preparing analysis runtime',
          'completed': 0,
          'total': null,
        };
        notifyListeners();
        await _provider!.prepare(
          onProgress: (p) {
            if (current()) {
              progress = p;
              notifyListeners();
            }
          },
        );
        if (!current()) return;
        ready = true;
        progress = null;
      }
      while (current() && _pending != null) {
        final request = _pending!;
        _pending = null;
        _active = request;
        _analyzing = true;
        final epoch = _windowEpoch;
        bool windowCurrent() => current() && epoch == _windowEpoch;
        try {
          final next = await _provider!.analyze(
            request,
            onProgress: (p) {
              if (windowCurrent()) {
                progress = p;
                notifyListeners();
              }
            },
          );
          if (windowCurrent()) {
            ready = true;
            result = next;
            completedWindows++;
            _completedKey = _key(request);
            progress = null;
          }
        } on ModernBookNlpCancelled {
          ready = false;
          if (windowCurrent()) rethrow;
        } catch (_) {
          ready = false;
          if (windowCurrent()) rethrow;
        } finally {
          _active = null;
          _analyzing = false;
        }
        if (current()) notifyListeners();
      }
    } catch (failure) {
      if (current()) {
        error = '$failure';
        progress = null;
        ready = false;
        _pending = null;
      }
    }
  }

  void invalidateWindow() {
    _windowEpoch++;
    _pending = _desired = null;
    _completedKey = null;
    result = null;
    if (_analyzing) unawaited(_provider?.cancel());
  }

  Future<void> stop() async {
    enabled = false;
    _session++;
    final desired = _desired;
    invalidateWindow();
    _desired = desired;
    progress = null;
    await _provider?.cancel();
    await _work;
    ready = false;
    if (!_closed) notifyListeners();
  }

  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    await stop();
    await _provider?.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
