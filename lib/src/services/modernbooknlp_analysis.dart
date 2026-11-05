import 'dart:async';
import 'package:flutter/foundation.dart';
import 'modernbooknlp_provider.dart';
import 'document_analysis_record.dart';
import 'document_analysis_repository.dart';

/// Main-isolate owner of opt-in diagnostic refinement. One active window plus
/// one replaceable demand, with no playback/preparation dependency or voice edits.
class ModernBookNlpAnalysis extends ChangeNotifier {
  ModernBookNlpAnalysis(this.createProvider);
  final Future<ModernBookNlpProvider> Function() createProvider;
  ModernBookNlpProvider? _provider;
  DocumentAnalysisRepository? repository;
  final Map<String, DocumentAnalysisRecord> _embedded = {};
  bool restoredFromBook = false;
  void restoreRecords(List<DocumentAnalysisRecord> records) {
    _embedded.clear();
    for (final record in records) {
      _embedded[record.key] = record;
    }
  }

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

  Future<void> _prepare(bool Function() current) async {
    _provider ??= await createProvider();
    if (!current()) return;
    if (ready) return;
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
    if (current()) {
      ready = true;
      progress = null;
    }
  }

  Future<void> _run() async {
    final session = _session;
    bool current() => !_closed && enabled && session == _session;
    try {
      // Explicit Prepare without a document retains its actionable setup behavior.
      if (_pending == null) await _prepare(current);
      while (current() && _pending != null) {
        final request = _pending!;
        _pending = null;
        _active = request;
        final epoch = _windowEpoch;
        bool windowCurrent() => current() && epoch == _windowEpoch;
        try {
          DocumentAnalysisRecord? saved =
              _embedded[DocumentAnalysisRecord.requestKey(request)];
          progress = {
            'message': 'Checking saved book analysis',
            'completed': 0,
            'total': null,
          };
          notifyListeners();
          try {
            saved ??= await repository?.read(request);
          } on FormatException {
            // Keep the damaged original until a fresh validated result replaces it.
            saved = null;
          }
          if (!windowCurrent()) continue;
          Map<String, dynamic> next;
          if (saved != null && saved.reusable) {
            next = await saved.restoreForRequest(request);
          } else {
            await _prepare(windowCurrent);
            if (!windowCurrent()) continue;
            _analyzing = true;
            next = await _provider!.analyze(
              request,
              onProgress: (p) {
                if (windowCurrent()) {
                  progress = p;
                  notifyListeners();
                }
              },
            );
            _analyzing = false;
            if (!windowCurrent()) continue;
            if (repository != null) {
              progress = {
                'message': 'Saving book analysis',
                'completed': 0,
                'total': null,
              };
              notifyListeners();
              await repository!.save(request, next, isCurrent: windowCurrent);
            }
          }
          if (windowCurrent()) {
            result = next;
            restoredFromBook = next['restoredFromBook'] == true;
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
    restoredFromBook = false;
    _embedded.clear();
    if (_analyzing) unawaited(_provider?.cancel());
  }

  Future<void> stop() async {
    enabled = false;
    _session++;
    final desired = _desired;
    final embedded = Map<String, DocumentAnalysisRecord>.of(_embedded);
    invalidateWindow();
    _desired = desired;
    _embedded.addAll(embedded);
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
