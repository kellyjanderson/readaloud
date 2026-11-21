part of 'reader_controller.dart';

/// Main-isolate owner of chapter discovery, publication and synthesis
/// admission. The source cursor, provider, cache and route projection share a
/// single sequential demand. Pausing transport only cancels its admission wait.
extension _ReaderChapterAnalysis on ReaderController {
  void _signalChapterAnalysis() {
    final changed = _chapterAnalysisChanged;
    _chapterAnalysisChanged = Completer<void>();
    changed.complete();
  }

  void _onChapterAnalysisChanged() {
    _signalChapterAnalysis();
    if (!characterAnalysis.enabled) {
      final cancellation = _chapterCancellation;
      if (!cancellation.isCompleted) cancellation.complete();
      if (!_useLegacyPortableAnalysis) characterAnalysis.clearDemand();
    }
    _startChapterAnalysis();
  }

  void _resetChapterAnalysis() {
    final cancellation = _chapterCancellation;
    if (!cancellation.isCompleted) cancellation.complete();
    _chapterCancellation = Completer<void>();
    _chapterSourceCancellation.complete();
    _chapterSourceCancellation = Completer<void>();
    _chapterCursor = null;
    _priorityChapterCursor = null;
    _nextChapterPriority = null;
    _chapterPending = null;
    _chapterRequest = null;
    _chapterScanFailure = null;
    _chapterScanComplete = false;
    _useLegacyPortableAnalysis = false;
    _legacyAnalysisWindowId = null;
    _completedChapterCount = 0;
    _chapterSegments.clear();
    _readyChapterSegments.clear();
    _chapterQuoteRoutes.clear();
    _pendingChapterSpeakers.clear();
    _chapterSpeakers.clear();
    _chapterProtectedSpans.clear();
    _fishSceneBoundaries.clear();
    _signalChapterAnalysis();
    characterAnalysis.invalidateWindow();
  }

  void _startChapterAnalysis() {
    if (_disposed ||
        !characterAnalysis.enabled ||
        _useLegacyPortableAnalysis ||
        characterAnalysis.error != null ||
        _chapterScanComplete ||
        _chapterScanFailure != null ||
        _chapterDriver != null ||
        !_documentPrepared ||
        _preparedDocumentRevision != _documentRevision ||
        _document.type == ReaderDocumentType.sample) {
      return;
    }
    if (_chapterCancellation.isCompleted) {
      _chapterCancellation = Completer<void>();
    }
    characterAnalysis.repository ??= _preparation.repository?.analysis;
    final cancellation = _chapterCancellation;
    final revision = _documentRevision;
    bool current() =>
        !_disposed &&
        characterAnalysis.enabled &&
        !cancellation.isCompleted &&
        revision == _documentRevision;
    final sourceCancellation = _chapterSourceCancellation;
    final cursor = _chapterCursor ??= ModernBookNlpChapters(
      (sequence) =>
          readPreparedRange(sequence, cancelled: sourceCancellation.future),
      document: _activePreparationRequest == null ? _document : null,
    );
    final ticket = beginReadingStage(
      PreparationStage.analysis,
      producerId: 'modernbooknlp-chapter-worker',
      scope: 'Chapter analysis',
    );
    void report(PreparationWorkState state, {String? message, String? error}) {
      publishReadingStage(
        ticket,
        PreparationProgress(
          stage: PreparationStage.analysis,
          state: state,
          completed: _completedChapterCount,
          total: state == PreparationWorkState.complete
              ? _completedChapterCount
              : null,
          unit: 'chapters',
          waitingReason: message,
          error: error,
        ),
      );
    }

    // Defer entry until the driver is assigned. Provider progress and widget
    // listeners can run synchronously before the first await.
    _chapterDriver =
        Future<void>.microtask(() async {
              while (current()) {
                report(
                  PreparationWorkState.waiting,
                  message: 'Reading source for the next chapter',
                );
                // A cancelled range read may have advanced its cursor. Keep its
                // bounded demand alive across settings toggles and only invalidate
                // it when the document revision changes.
                if (_nextChapterPriority case (final range, final start)
                    when _chapterPending == null &&
                        _chapterSegments.isEmpty &&
                        _priorityChapterCursor == null) {
                  _priorityChapterCursor = ModernBookNlpChapters(
                    (sequence) => readPreparedRange(
                      sequence,
                      cancelled: sourceCancellation.future,
                    ),
                    document: _activePreparationRequest == null
                        ? _document
                        : null,
                    startRange: range,
                    startSegment: start,
                  );
                  _nextChapterPriority = null;
                }
                final pending =
                    _chapterPending ??
                    await (_priorityChapterCursor ?? cursor).next();
                if (revision != _documentRevision || _disposed) return;
                _chapterPending = pending;
                if (!current()) break;
                if (pending == null) {
                  if (_priorityChapterCursor != null) {
                    _priorityChapterCursor = null;
                    continue;
                  }
                  _chapterScanComplete = true;
                  report(PreparationWorkState.complete);
                  break;
                }
                if (pending.window.targetSegmentIds.every(
                  _readyChapterSegments.contains,
                )) {
                  _chapterPending = null;
                  if (pending.endsChapter) _priorityChapterCursor = null;
                  continue;
                }
                final sequence = ++_characterDeltaSequence;
                final request = ModernBookNlpRequest(
                  requestId: '$_preparationOwner-$revision-$sequence',
                  ownerId: _preparationOwner,
                  workId: _voicePreferenceDocumentId,
                  sourceRevision: _characterSourceRevision,
                  analysisRevision: revision,
                  sequence: sequence,
                  text: pending.window.text,
                  windowPolicy: 'chapter-context-v1',
                );
                _chapterRequest = request;
                characterAnalysis.offer(request);
                report(
                  PreparationWorkState.working,
                  message: 'Analyzing chapter ${pending.chapter}',
                );
                while (current() &&
                    characterAnalysis.error == null &&
                    characterAnalysis.result?['requestId'] !=
                        request.requestId) {
                  await _chapterAnalysisChanged.future;
                }
                if (!current()) break;
                if (characterAnalysis.error case final error?) {
                  report(
                    PreparationWorkState.failed,
                    error: '$error Retry in ModernBookNLP settings.',
                  );
                  break;
                }
                _chapterPending = null;
                _chapterRequest = null;
                if (pending.endsChapter) _priorityChapterCursor = null;
              }
              if (!current() && revision == _documentRevision && !_disposed) {
                report(PreparationWorkState.cancelled);
              }
            })
            .catchError((Object error) {
              if (!current()) return;
              _chapterScanFailure = '$error';
              _logDiagnostic('Chapter analysis failed', error: error);
              report(
                PreparationWorkState.failed,
                error: '$_chapterScanFailure',
              );
            })
            .whenComplete(() {
              _chapterDriver = null;
              _signalChapterAnalysis();
              _startChapterAnalysis();
            });
  }

  void _prioritizeChapterAtCurrentPosition() {
    if (!characterAnalysis.enabled || _useLegacyPortableAnalysis) return;
    _nextChapterPriority = null;
    final segment = _document.segmentForWordIndex(_currentWordIndex);
    if (segment == null ||
        _readyChapterSegments.contains(segment.segmentId) ||
        _chapterSegments.contains(segment.segmentId) ||
        _chapterPending?.window.targetSegmentIds.contains(segment.segmentId) ==
            true) {
      return;
    }
    final anchor = ModernBookNlpChapters.chapterAnchor(
      _document,
      segment.segmentId,
    );
    if (anchor == null) return;
    _nextChapterPriority = (_activePreparedRange?.sequence ?? 1, anchor);
  }

  void _offerLegacyPortableAnalysis() {
    if (!_useLegacyPortableAnalysis) return;
    final window = ModernBookNlpWindow.at(
      _document,
      wordIndex: _currentWordIndex,
    );
    if (window == null || _legacyAnalysisWindowId == window.identity) return;
    _legacyAnalysisWindowId = window.identity;
    final sequence = ++_characterDeltaSequence;
    characterAnalysis.offer(
      ModernBookNlpRequest(
        requestId: '$_preparationOwner-$_documentRevision-$sequence',
        ownerId: _preparationOwner,
        workId: _voicePreferenceDocumentId,
        sourceRevision: _characterSourceRevision,
        analysisRevision: _documentRevision,
        sequence: sequence,
        text: window.text,
        windowPolicy: 'paragraph-context-v2',
      ),
    );
  }

  Future<void> _acceptChapterAnalysis(
    ModernBookNlpRequest request,
    Map<String, dynamic> result,
    bool Function() providerOwns,
  ) async {
    bool owns() =>
        providerOwns() &&
        !_disposed &&
        !_chapterCancellation.isCompleted &&
        request.analysisRevision == _documentRevision &&
        request.requestId == _chapterRequest?.requestId;
    if (!owns()) return;
    final pending = _chapterPending!;
    final window = pending.window;
    final boundaries = await projectFishSceneBoundaries(pending, result);
    if (!owns()) return;
    bool apply = false;
    // If an authored correction arrived during projection, reread the
    // merged registry and reconcile against it before releasing the window.
    for (var attempt = 0; owns() && !apply && attempt < 3; attempt++) {
      final registry = _characters.registry(
        _voicePreferenceDocumentId,
        documentId: _document.displayDocument.documentId,
      );
      final (delta, speakers) = await projectChapterCharacters(
        request,
        result,
        registry,
        window,
      );
      if (!owns()) return;
      apply = _characters.apply(delta);
      if (!apply) continue;
      _pendingChapterSpeakers.addAll(speakers);
      for (final ref in delta.dialogues) {
        if (ref.sourceMatched &&
            !window.protectedSpanIds.contains(ref.dialogueSpanId)) {
          (_chapterQuoteRoutes[ref.segmentId] ??= []).add(ref);
        }
      }
    }
    if (!owns()) return;
    if (!apply) {
      throw StateError('Character corrections changed during analysis.');
    }
    _fishSceneBoundaries.addAll(boundaries);
    _chapterProtectedSpans.addAll(window.protectedSpanIds);
    _chapterSegments.addAll(window.targetSegmentIds);
    if (pending.endsChapter) {
      _readyChapterSegments.addAll(_chapterSegments);
      _chapterSegments.clear();
      _chapterSpeakers.addAll(_pendingChapterSpeakers);
      _pendingChapterSpeakers.clear();
      ++_completedChapterCount;
      _refreshCharacterProjection();
      _instrumentation.recordMetric(
        metric: 'chapterAnalysisPublished',
        documentId: sessionDocumentId,
        sessionId: request.requestId,
        voiceId: _selectedVoiceId ?? '',
        engineId: _engineId(),
        value: {
          'completedChapters': _completedChapterCount,
          'savedAnalysis': result['restoredFromBook'] == true,
        },
      );
    }
    _signalChapterAnalysis();
    unawaited(_persistPreferences());
    _notifyChapterAnalysisChanged();
  }

  Future<void> _awaitChapterAnalysis(
    ReaderDocument document, {
    required bool Function() current,
    Future<void>? cancelled,
    bool completeBook = false,
  }) async {
    if (!characterAnalysis.enabled ||
        !isDramaEngine(_engineId()) ||
        document.type == ReaderDocumentType.sample) {
      return;
    }
    if (_useLegacyPortableAnalysis) {
      _useLegacyPortableAnalysis = false;
      characterAnalysis.clearDemand();
    }
    _startChapterAnalysis();
    final revision = _documentRevision;
    Future<void> waitForCoverage() async {
      var announcedWait = false;
      while (current() &&
          revision == _documentRevision &&
          characterAnalysis.enabled) {
        final ready = completeBook
            ? _chapterScanComplete
            : document.speechDocument.segments.every(
                (s) => _readyChapterSegments.contains(s.segmentId),
              );
        if (ready) return;
        final failure = _chapterScanFailure ?? characterAnalysis.error;
        if (failure != null || _chapterScanComplete) {
          throw StateError(
            failure ?? 'Chapter analysis did not cover this prepared text.',
          );
        }
        final changed = _chapterAnalysisChanged.future;
        if (!announcedWait) {
          announcedWait = true;
          // Expose pending Play even if analysis was already working and quiet.
          _notifyChapterAnalysisChanged();
        }
        await changed;
      }
    }

    await (cancelled == null
        ? waitForCoverage()
        : Future.any<void>([waitForCoverage(), cancelled]));
    if (!current() || revision != _documentRevision) {
      throw const PlanningCancelled();
    }
  }
}
