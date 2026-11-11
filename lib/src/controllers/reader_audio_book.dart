part of 'reader_controller.dart';

/// One document owns its package worker and materialized audio until the player
/// has stopped. Viewport reads use separate short-lived workers, admitted by the
/// controller's existing eight-read bound; audio continuation has one consumer.
class _ReaderAudioBook {
  _ReaderAudioBook(
    this.package,
    this.book,
    this.engineAtOpen,
    this.sourceLease,
  );
  final RadocAudioPackage package;
  final RadocAudioBook book;
  String engineAtOpen;
  final DocumentAccessLease? sourceLease;
  bool current = true;
  Future<_BookAudio>? boundaryWork;
  Completer<void>? renderCancellation;
  Future<void>? renderWork;
  _BookRenderStream? renderStream;
  void cancelRender() {
    final cancellation = renderCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    unawaited(renderStream?.cancelConsumer());
  }

  Future<void>? _closing;
  Future<void> dispose() => _closing ??= _close();
  Future<void> _close() async {
    current = false;
    cancelRender();
    try {
      await renderWork;
    } catch (_) {
      /* The stream's owner reports the failed render. */
    }
    await package.cancelAndDrain();
    try {
      await boundaryWork;
    } catch (_) {
      /* already reported to request */
    }
    await package.dispose();
    await sourceLease?.close();
  }
}

extension ReaderAudioBookSupport on ReaderController {
  /// The screen resolves launch/open/restore intake before synthesis startup.
  Future<void> completeInitialIntake() async {
    if (_disposed ||
        _modelPreparationCancelled ||
        _audioBook != null ||
        _synthesisInitialized ||
        !deferInitialSynthesis) {
      return;
    }
    await retryInitialization();
  }

  void _bookProgress(RadocPackageProgress progress, int revision) {
    if (_disposed || revision != _documentRevision) return;
    _preparationProgress[PreparationStage.persistence] = PreparationProgress(
      stage: PreparationStage.persistence,
      state: progress.total == null
          ? PreparationWorkState.waiting
          : PreparationWorkState.working,
      completed: progress.completed,
      total: progress.total,
      unit: progress.unit,
      scope: 'Audio book ${progress.stage}',
      waitingReason: progress.total == null ? progress.stage : null,
    );
    _notifyAudioBookChanged();
  }

  Future<void> _openAudioBook(String path, int revision) async {
    bool current() => !_disposed && revision == _documentRevision;
    await _ensureSceneRepository();
    _requireRevision(revision);
    final package = RadocAudioPackage(
      onProgress: (p) => _bookProgress(p, revision),
    );
    DocumentAccessLease? lease;
    _ReaderAudioBook? session;
    try {
      try {
        final token = await _documentAccessService.createPersistentRestoreToken(
          path,
        );
        if (token != null) {
          lease = await _documentAccessService.openPersistentRestoreToken(
            token,
          );
        }
      } on MissingPluginException {
        // Platform-free tests have no security-scoped file access service.
      }
      _requireRevision(revision);
      final book = await package.open(
        File(path),
        materializeOpeningRange: true,
        isCurrent: current,
      );
      _requireRevision(revision);
      if (book.manifest.preparedRanges.isEmpty ||
          book.manifest.preparedRanges.first.startWord != 0) {
        throw const FormatException(
          'This audio book has no prepared opening range.',
        );
      }
      final openingPath = book.openingRangePath;
      if (openingPath == null) {
        throw const FormatException('Missing opening range.');
      }
      final opening = await _readBookRangeFile(openingPath);
      _requireRevision(revision);
      session = _ReaderAudioBook(package, book, _selectedTtsEngineId, lease);
      _audioBook = session;
      characterAnalysis.loadBookRecord = (request, isCurrent) async {
        final member =
            'analysis/${DocumentAnalysisRecord.requestKey(request)}.json';
        if (!book.manifest.analysisMembers.contains(member)) return null;
        final reader = RadocAudioPackage();
        try {
          final handle = await reader.open(File(path), isCurrent: isCurrent);
          if (handle.manifestDigest != book.manifestDigest) {
            throw const FormatException('Saved analysis book changed.');
          }
          final file = await reader.materializeMember(
            handle,
            member,
            isCurrent: isCurrent,
          );
          final recordPath = file.path;
          return await _readBookAnalysisFile(recordPath);
        } finally {
          await reader.dispose();
        }
      };
      _activeSourceRevision = book.manifest.sourceId;
      _activePreparationRequest = DocumentPreparationRequest(
        ownerId: _preparationOwner,
        revision: revision,
        kind: DocumentPreparationKind.bytes,
        fileName: p.basename(path),
        sourcePath: path,
        sourceRevision: book.manifest.sourceId,
      );
      _publicationSequence = book.manifest.preparedRanges.length;
      _preparedWordCount = book.manifest.preparedRanges.last.endWord;
      _preparationComplete = book.manifest.preparationComplete;
      final first = _publishBookRange(session, 1, opening);
      _documentIdentityRedirects[first.fragment.displayDocument.documentId] =
          book.manifest.documentId;
      // These are published voice descriptions, not claims that models exist.
      final intent = book.manifest.intent;
      final profiles = (intent['voices'] as List? ?? const []).map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return VoiceProfile(
          id: m['id'] as String,
          label: m['label'] as String,
          locale: m['locale'] as String? ?? '',
          rawValue: const {},
          gender: m['gender'] == null
              ? null
              : VoiceGender.values.byName(m['gender'] as String),
          description:
              'Published book voice. Rendering requires its speech model.',
        );
      }).toList();
      if (profiles.isNotEmpty) _voices = List.unmodifiable(profiles);
      if (intent['defaultVoiceId'] case final String voice) {
        _selectedVoiceId = voice;
      }
      if (intent['multiVoice'] case final bool multi) {
        _isMultiVoiceEnabled = multi;
      }
      if (intent['rate'] case final num rate) {
        if (_selectedVoiceId != null) {
          _voiceSpeeds[_selectedVoiceId!] = rate.toDouble();
        }
      }
      await _replaceDocument(
        first.fragment,
        revision: revision,
        sourcePath: path,
        restoreCharacters: true,
      );
      _requireRevision(revision);
      _sessionDocumentId = book.manifest.documentId;
      _preparationComplete = book.manifest.preparationComplete;
      _hasCompleteDocumentSnapshot =
          book.manifest.preparationComplete &&
          book.manifest.preparedRanges.length == 1;
      _isInitializing = false;
      _startupError = null;
      _preparationProgress.remove(PreparationStage.persistence);
      await _rememberOpenedDocumentPath(path, revision: revision);
      _requireRevision(revision);
      _notifyAudioBookChanged();
    } catch (_) {
      if (identical(_audioBook, session)) _audioBook = null;
      if (session != null) {
        await session.dispose();
      } else {
        await package.dispose();
        await lease?.close();
      }
      rethrow;
    }
  }

  Future<DocumentPreparationPublication?> _readAudioBookRange(
    _ReaderAudioBook session,
    int sequence,
    int revision,
  ) async {
    final manifest = session.book.manifest;
    final cached = _preparedRanges
        .where((r) => r.sequence == sequence)
        .firstOrNull;
    if (cached != null) return cached;
    if (sequence > manifest.preparedRanges.length) {
      if (manifest.preparationComplete) return null;
      throw StateError(
        'This book contains only part of the prepared source. Open the original document to continue preparation.',
      );
    }
    bool current() =>
        session.current && !_disposed && revision == _documentRevision;
    final descriptor = manifest.preparedRanges[sequence - 1];
    final reader = RadocAudioPackage();
    try {
      final handle = await reader.open(
        File(session.book.packagePath),
        isCurrent: current,
      );
      if (handle.manifestDigest != session.book.manifestDigest) {
        throw const FormatException(
          'Audio book changed while reading. Reopen it.',
        );
      }
      final file = await reader.materializeMember(
        handle,
        descriptor.member,
        isCurrent: current,
      );
      final restored = await _readBookRangeFile(file.path);
      _requireRevision(revision);
      if (!session.current) throw const PlanningCancelled();
      return _publishBookRange(session, sequence, restored);
    } finally {
      await reader.dispose();
    }
  }

  DocumentPreparationPublication _publishBookRange(
    _ReaderAudioBook session,
    int sequence,
    ({ReaderDocument document, Map<String, String> userVoiceAssignments})
    restored,
  ) {
    final manifest = session.book.manifest;
    final descriptor = manifest.preparedRanges[sequence - 1];
    final document = restored.document;
    if (document.wordCount != descriptor.endWord - descriptor.startWord) {
      throw const FormatException(
        'Prepared audio book range has incorrect word coverage.',
      );
    }
    _characters.migrateLegacy({
      manifest.documentId: restored.userVoiceAssignments,
    });
    _characters.restoreDocument(
      manifest.documentId,
      document.characterCastRegistry,
    );
    final publication = DocumentPreparationPublication(
      request: _activePreparationRequest!,
      sequence: sequence,
      range: PreparedDocumentRange(
        sourceStart: 0,
        sourceEnd: document.speakableText.length,
        wordStart: descriptor.startWord,
        wordEnd: descriptor.endWord,
        segmentStart: 0,
        segmentEnd: document.speechDocument.segments.length,
      ),
      fragment: document,
      coverage: const {
        PreparationStage.normalization,
        PreparationStage.mapping,
        PreparationStage.analysis,
        PreparationStage.pronunciation,
      },
      progress: const [],
      isLast:
          manifest.preparationComplete &&
          sequence == manifest.preparedRanges.length,
    );
    _preparedRanges.add(publication);
    if (_preparedRanges.length > ReaderController.preparedRangeCapacity) {
      _preparedRanges.removeAt(
        identical(_preparedRanges.first, _activePreparedRange) ? 1 : 0,
      );
    }
    return publication;
  }

  /// Match only effective choices used by this scene. An unrelated Character
  /// edit cannot invalidate this scene. Native resource identities remain in
  /// dependencies; replay itself does not need the corresponding model.
  bool _bookSceneMatches(_ReaderAudioBook book, RadocAudioScene scene) {
    if (artifactIdentity(scene.dependencies) != scene.dependencyDigest) {
      return false;
    }
    final intent =
        (scene.provenance['intent'] as Map?) ?? book.book.manifest.intent;
    if (_selectedTtsEngineId != book.engineAtOpen &&
        intent['engineId'] != _selectedTtsEngineId) {
      return false;
    }
    if (intent['rate'] != null &&
        (intent['rate'] as num).toDouble() != currentSpeed) {
      return false;
    }
    if (intent['multiVoice'] != null &&
        intent['multiVoice'] != _isMultiVoiceEnabled) {
      return false;
    }
    final turns =
        (scene.provenance['sceneTurns'] as List?) ??
        (scene.dependencies['sceneTurns'] as List?) ??
        const [];
    if (turns.isEmpty &&
        intent['defaultVoiceId'] != null &&
        intent['defaultVoiceId'] != _selectedVoiceId) {
      return false;
    }
    final assignments = _characters.selections(_voicePreferenceDocumentId);
    for (final item in turns) {
      final turn = item as Map;
      final cast = turn['castId'] as String?;
      if (cast != null && assignments.containsKey(cast)) {
        if (assignments[cast] != turn['voice']) return false;
      } else if (intent['characterSelections'] is Map &&
          (intent['characterSelections'] as Map).containsKey(cast)) {
        return false;
      } else if (intent['defaultVoiceId'] != null &&
          intent['defaultVoiceId'] != _selectedVoiceId) {
        return false;
      }
    }
    return true;
  }

  Future<_BookScene?> _findBookScene(
    _ReaderAudioBook session,
    int word,
    bool Function() current,
  ) async {
    final descriptor = session.book.manifest.scenes
        .where((s) => s.startWord <= word && word < s.endWord)
        .firstOrNull;
    final start = descriptor?.startWord ?? word;
    final repository = _renderedScenes;
    if (repository != null) {
      final reader = RenderedSceneRepository(repository.root);
      try {
        final saved = await reader.sceneStartingAt(
          session.book.manifest.sourceId,
          start,
          isCurrent: current,
        );
        if (saved != null) {
          final scene = _publishedScene(saved);
          if (_bookSceneMatches(session, scene) &&
              await _bookSceneSourceMatches(session, scene, current)) {
            return _BookScene(
              scene,
              audioPath: saved.audioPath,
              rawAudioPath: saved.rawAudioPath,
            );
          }
        }
      } finally {
        await reader.dispose();
      }
    }
    if (descriptor == null ||
        !_bookSceneMatches(session, descriptor) ||
        !await _bookSceneSourceMatches(session, descriptor, current)) {
      return null;
    }
    return _BookScene(descriptor);
  }

  Future<bool> _bookSceneSourceMatches(
    _ReaderAudioBook book,
    RadocAudioScene scene,
    bool Function() current,
  ) async {
    final index = book.book.manifest.preparedRanges.indexWhere(
      (r) => r.startWord <= scene.startWord && scene.endWord <= r.endWord,
    );
    if (index < 0) return false;
    final range = await readPreparedRange(index + 1);
    if (!current() || range == null) throw const PlanningCancelled();
    final start = range.fragment.charOffsetForWord(
      scene.startWord - range.range.wordStart,
    );
    final end = scene.endWord == range.range.wordEnd
        ? range.fragment.speakableText.length
        : range.fragment.charOffsetForWord(
            scene.endWord - range.range.wordStart,
          );
    // Native scenes join complete prepared segments with spaces. The prepared
    // surface retains paragraph breaks; compare that same textual projection,
    // while directions below retain their independent semantic identity.
    final sceneText = scene.provenance['text'] as String?;
    if (sceneText == null ||
        _joinedBookSource(sceneText) !=
            _joinedBookSource(
              range.fragment.speakableText.substring(start, end),
            )) {
      return false;
    }
    final raw = scene.dependencies['raw'] as Map?;
    final directions = raw?['canonicalDirections'];
    return directions == null ||
        artifactIdentity(directions) ==
            artifactIdentity(
              _canonicalSceneDirections(
                range.fragment,
                range.range.wordStart,
                scene.startWord,
                scene.endWord,
              ),
            );
  }

  /// One missing native scene uses the existing export owner. It commits raw
  /// and finalized output before the rendered player admits it; the next
  /// scene is resolved afresh, so valid following audio never enters inference.
  Future<_BookRenderStream> _beginRenderBookScene(
    _ReaderAudioBook session,
    int word,
    bool Function() current, {
    Future<void>? cancelled,
    _BookScene? previous,
  }) async {
    _audioGapWord = word;
    _statusMessage = 'This passage needs audio. Preparing its speech model…';
    _notifyAudioBookChanged();
    if (!_synthesisInitialized) await retryInitialization();
    if (!current()) throw const PlanningCancelled();
    if (_startupError != null) {
      throw StateError('This passage needs rendering: $_startupError');
    }
    final engine = _ttsEngine;
    if (engine is! AudioExportCapable) {
      throw StateError('The selected engine cannot render this audio book.');
    }
    final manifest = session.book.manifest;
    final index = manifest.preparedRanges.indexWhere(
      (r) => r.startWord <= word && word < r.endWord,
    );
    if (index < 0) throw StateError('No prepared text for this passage.');
    final range = await readPreparedRange(index + 1);
    if (!current() || range == null) throw const PlanningCancelled();
    final original = manifest.scenes
        .where((s) => s.startWord <= word && word < s.endWord)
        .firstOrNull;
    final following = manifest.scenes
        .where((s) => s.startWord > word && s.startWord < range.range.wordEnd)
        .firstOrNull;
    final start = (original?.startWord ?? word) - range.range.wordStart;
    final end =
        (original?.endWord ?? following?.startWord ?? range.range.wordEnd) -
        range.range.wordStart;
    final base = _planningContext(fromStart: true, document: range.fragment);
    if (base == null) throw StateError('Choose a voice before rendering.');
    final source = base.realization;
    final bounded = _bookSpeechPrefix(source.speechDocument, end);
    final segment = range.fragment.segmentForWordIndex(start);
    if (segment == null) {
      throw StateError('Prepared scene has no source segment.');
    }
    final context = SpeechPlanningContext(
      engineVersion: base.engineVersion,
      routes: base.routes,
      realization: VoiceSessionRealizationInput(
        speechDocument: bounded,
        baseAnnotations: source.baseAnnotations,
        basePronunciationArtifacts: source.basePronunciationArtifacts,
        startSegmentId: segment.segmentId,
        voiceId: source.voiceId,
        engineId: source.engineId,
        rate: source.rate,
        narrationState: source.narrationState,
        selectedProfile: source.selectedProfile,
        mergedPronunciationResources: source.mergedPronunciationResources,
        enabledActiveRuleModules: source.enabledActiveRuleModules,
      ),
    );
    session.cancelRender();
    await session.renderWork?.catchError((Object _, StackTrace _) {});
    if (!current()) throw const PlanningCancelled();
    final cancellation = Completer<void>();
    session.renderCancellation = cancellation;
    final stream = _BookRenderStream(cancellation);
    session.renderStream = stream;
    if (cancelled != null) {
      unawaited(
        cancelled.then((_) {
          if (!cancellation.isCompleted) cancellation.complete();
        }),
      );
    }
    bool renderCurrent() => current() && !cancellation.isCompleted;
    final planner = SpeechPlanningSupervisor();
    unawaited(cancellation.future.then((_) => planner.cancel()));
    final previousTrailing =
        previous?.trailingMicros ??
        previous?.scene.provenance['trailingSilenceMicros'] as int?;
    Future<void> produce() async {
      Directory? staging;
      _BookScene? finished;
      Object? failure;
      StackTrace? failureStack;
      try {
        final window = await planner.plan(context, maxChunks: 1);
        if (!renderCurrent()) throw const PlanningCancelled();
        if (window.plan.chunks.isEmpty) throw StateError('No planned scene.');
        final chunk = window.plan.chunks.single;
        // Native scene boundaries are whole prepared segments. Refuse an
        // incompatible historical partition instead of synthesizing past it.
        if (chunk.startWordIndex != start || chunk.endWordIndex > end) {
          throw StateError('Saved scene boundaries need renewed preparation.');
        }
        staging = await Directory.systemTemp.createTemp('radoc-scene-render-');
        await (engine as AudioExportCapable).exportAudio(
          TtsExportRequest(
            text: range.fragment.speakableText,
            outputPath: p.join(staging.path, 'scene.wav'),
            documentId: manifest.documentId,
            documentTitle: range.fragment.title,
            sourceDescription: range.fragment.sourceDescription,
            sessionId: 'book_${_playbackIntent}_$word',
            normalizationVersion: bounded.normalizationVersion,
            chunkPlan: ChunkPlan(planId: window.plan.planId, chunks: [chunk]),
            speechDocument: bounded,
            ttsArtifactSet: window.realization.ttsArtifactSet,
            planningContext: context,
            sourceWordOffset: range.range.wordStart,
            assignmentRevision: voiceAssignmentState.requestedRevision,
            isCurrent: renderCurrent,
            cancelled: cancellation.future,
            predecessorRawArtifactIdentity:
                previous?.scene.provenance['rawArtifactIdentity'] as String?,
            predecessorTrailingSilence: previousTrailing == null
                ? null
                : Duration(microseconds: previousTrailing),
            onPlayablePacket: (packet) async {
              if (!renderCurrent()) throw const PlanningCancelled();
              stream.add(packet);
            },
            onRenderedScene: _renderedSceneWriter(
              document: range.fragment,
              sourceWordOffset: range.range.wordStart,
            ),
          ),
        );
        if (!renderCurrent()) throw const PlanningCancelled();
        finished = await _findBookScene(session, word, renderCurrent);
        if (finished == null) {
          throw StateError('Rendered scene was not committed.');
        }
        _audioGapWord = null;
        _statusMessage = null;
        _notifyAudioBookChanged();
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      } finally {
        try {
          await planner.shutdown();
          if (staging != null) await staging.delete(recursive: true);
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        } finally {
          if (identical(session.renderCancellation, cancellation)) {
            session.renderCancellation = null;
          }
        }
      }
      if (failure != null) {
        stream.fail(failure, failureStack!);
      } else {
        stream.complete(finished!);
      }
    }

    final work = produce();
    session.renderWork = work;
    unawaited(work);
    return stream;
  }

  Future<bool> _startAudioBookPlayback(
    _ReaderAudioBook session,
    int playbackIntent,
  ) async {
    final revision = _documentRevision;
    // Keep initialization and any first missing-scene render on the user's
    // original Play clock. Readiness is not a new measurement start.
    _playbackRequestedAt ??= DateTime.now();
    bool current() =>
        session.current &&
        !_disposed &&
        revision == _documentRevision &&
        playbackIntent == _playbackIntent &&
        _resumeAfterPreparation;
    final manifest = session.book.manifest;
    var word =
        _audioGapWord ??
        (_currentWordIndex + (_activePreparedRange?.range.wordStart ?? 0));
    if (_playbackEndedAtDocumentEnd || word >= manifest.totalWords) word = 0;
    var firstScene = await _findBookScene(session, word, current);
    _BookRenderStream? rendering;
    _BookPlaybackPart? firstPart;
    if (!current()) return true;
    if (firstScene == null) {
      final publishedEngine = manifest.intent['engineId'] as String?;
      if (publishedEngine != null &&
          ReaderController._knownTtsEngineIds.contains(publishedEngine) &&
          _selectedTtsEngineId == session.engineAtOpen &&
          _selectedTtsEngineId != publishedEngine) {
        // Engine replacement advances intent. Requeue exactly this user's Play
        // after its owned replacement; a later Pause/open/selection wins.
        final oldEngine = _ttsEngine;
        await _setTtsEngineId(publishedEngine, preserveBookPlay: true);
        final expectedIntent =
            playbackIntent + (identical(oldEngine, _ttsEngine) ? 0 : 1);
        if (session.current &&
            !_disposed &&
            revision == _documentRevision &&
            _playbackIntent == expectedIntent &&
            _resumeAfterPreparation &&
            _selectedTtsEngineId == publishedEngine) {
          session.engineAtOpen = publishedEngine;
          _playbackStartPending = true;
        }
        return true;
      }
      rendering = await _beginRenderBookScene(session, word, current);
      firstPart = await rendering.take();
      if (firstPart == null) throw StateError('Rendering produced no audio.');
      if (!current()) return true;
    }
    firstPart ??= _BookPlaybackPart.complete(firstScene!);
    final engine = _ttsEngine;
    if (engine is! RenderedAudioPlaybackCapable) {
      throw StateError('The selected player cannot open published audio.');
    }
    _audioGapWord = null;
    _statusMessage = null;
    _activePlaybackDocumentId = manifest.documentId;
    _activePlaybackIntent = playbackIntent;
    _acknowledgedPlaybackIntent = null;
    _playbackState = ReaderPlaybackPrimaryState.bufferingFirstChunk;
    _playbackEndedAtDocumentEnd = false;
    var sequence = 0;
    var wordEnd = firstPart.endWord;
    _BookScene? previousScene;
    String? activePacketScene;
    late TtsRenderedAudioContinuation continuation;
    Future<TtsRenderedAudioRequest> request(
      _BookPlaybackPart part,
      int i,
    ) async {
      if (part.packet case final packet?) {
        final rangeIndex = manifest.preparedRanges.indexWhere(
          (r) =>
              r.startWord <= packet.startWordIndex &&
              packet.endWordIndex <= r.endWord,
        );
        if (rangeIndex < 0) {
          throw const FormatException('Packet scene crosses prepared range.');
        }
        final range = await readPreparedRange(rangeIndex + 1);
        if (!current() || range == null) throw const PlanningCancelled();
        final start = range.fragment.charOffsetForWord(
          packet.startWordIndex - range.range.wordStart,
        );
        final end = packet.endWordIndex == range.range.wordEnd
            ? range.fragment.speakableText.length
            : range.fragment.charOffsetForWord(
                packet.endWordIndex - range.range.wordStart,
              );
        if (_joinedBookSource(packet.text) !=
            _joinedBookSource(
              range.fragment.speakableText.substring(start, end),
            )) {
          throw const FormatException('Packet scene does not match source.');
        }
        return TtsRenderedAudioRequest(
          documentId: manifest.documentId,
          manifestIdentity: session.book.manifestDigest,
          intentRevision: playbackIntent,
          sceneId: packet.sceneId,
          text: packet.text,
          startWordIndex: packet.startWordIndex,
          endWordIndex: packet.endWordIndex,
          sourceEndWordIndex: manifest.totalWords,
          startOffset: packet.startOffset,
          sceneTurns: packet.sceneTurns,
          audioPath: packet.packet.audioPath,
          audioPacket: packet.packet,
          sceneCompletion: packet.sceneCompletion,
          boundaryClass: packet.boundaryClass,
          isInitialScene: packet.isInitialScene,
          previousTrailingSilence: packet.previousTrailingSilence,
          format: TtsRenderedAudioFormat(
            sampleRate: packet.packet.sampleRate,
            channels: packet.packet.channels,
            bitsPerSample: packet.packet.bitsPerSample,
          ),
          duration: packet.packet.duration,
          rangeSequence: i,
          isCurrent: current,
          continuation: continuation,
          onPlaybackReady: (ack) {
            if (current() &&
                ack.documentId == manifest.documentId &&
                ack.manifestIdentity == session.book.manifestDigest &&
                ack.intentRevision == playbackIntent) {
              _acknowledgedPlaybackIntent = playbackIntent;
            }
          },
          onRangeActive: () {
            final identity = '${packet.sceneId}:${packet.startWordIndex}';
            if (!current() || activePacketScene == identity) return;
            activePacketScene = identity;
            _document = range.fragment;
            _activePreparedRange = range;
            _currentWordIndex = packet.startWordIndex - range.range.wordStart;
            _utteranceStartOffset = 0;
            _mergeDiscoveredCast(
              range.fragment.characterCastRegistry,
              document: range.fragment,
            );
            _notifyAudioBookChanged();
          },
        );
      }
      final value = part.scene!;
      final scene = value.scene;
      final rangeIndex = manifest.preparedRanges.indexWhere(
        (r) => r.startWord <= scene.startWord && scene.endWord <= r.endWord,
      );
      if (rangeIndex < 0) {
        throw const FormatException('Audio scene crosses its prepared range.');
      }
      final range = await readPreparedRange(rangeIndex + 1);
      if (!current() || range == null) throw const PlanningCancelled();
      final evidence = scene.provenance;
      final text =
          evidence['text'] as String? ?? scene.dependencies['text'] as String?;
      if (text == null) {
        throw const FormatException('Audio scene is missing source text.');
      }
      final sourceStart = range.fragment.charOffsetForWord(
        scene.startWord - range.range.wordStart,
      );
      final sourceEnd = scene.endWord == range.range.wordEnd
          ? range.fragment.speakableText.length
          : range.fragment.charOffsetForWord(
              scene.endWord - range.range.wordStart,
            );
      if (_joinedBookSource(text) !=
          _joinedBookSource(
            range.fragment.speakableText.substring(sourceStart, sourceEnd),
          )) {
        throw const FormatException(
          'Saved audio text does not match its prepared source.',
        );
      }
      final resolvedAudio = await _resolveBookAudio(
        session,
        value,
        previousScene,
        current,
        document: range.fragment,
        sourceWordOffset: range.range.wordStart,
      );
      final file = File(resolvedAudio.path);
      previousScene = _BookScene(
        value.scene,
        audioPath: resolvedAudio.path,
        rawAudioPath: value.rawAudioPath,
        trailingMicros: resolvedAudio.trailingMicros,
      );
      if (!current()) throw const PlanningCancelled();
      final turnMaps = (evidence['sceneTurns'] as List?) ?? const [];
      return TtsRenderedAudioRequest(
        documentId: manifest.documentId,
        manifestIdentity: session.book.manifestDigest,
        intentRevision: playbackIntent,
        sceneId: scene.sceneId,
        text: text,
        startWordIndex: scene.startWord,
        endWordIndex: scene.endWord,
        sourceEndWordIndex: manifest.totalWords,
        startOffset: evidence['startOffset'] as int? ?? sourceStart,
        sceneTurns: turnMaps
            .map(
              (t) =>
                  NativeSpeechTurn.fromMap(Map<String, dynamic>.from(t as Map)),
            )
            .toList(),
        audioPath: file.path,
        format: TtsRenderedAudioFormat(
          sampleRate: scene.sampleRate,
          channels: scene.channels,
          bitsPerSample: 16,
        ),
        duration: resolvedAudio.duration,
        rangeSequence: i,
        isCurrent: current,
        continuation: continuation,
        onPlaybackReady: (ack) {
          if (current() &&
              ack.documentId == manifest.documentId &&
              ack.manifestIdentity == session.book.manifestDigest &&
              ack.intentRevision == playbackIntent) {
            _acknowledgedPlaybackIntent = playbackIntent;
          }
        },
        onRangeActive: () {
          if (!current()) return;
          _document = range.fragment;
          _activePreparedRange = range;
          _currentWordIndex = scene.startWord - range.range.wordStart;
          _utteranceStartOffset = 0;
          _mergeDiscoveredCast(
            range.fragment.characterCastRegistry,
            document: range.fragment,
          );
          _notifyAudioBookChanged();
        },
      );
    }

    continuation = TtsRenderedAudioContinuation(
      next: (previous, cancelled) async {
        if (previous != sequence) {
          throw StateError('Out-of-order audio scene demand.');
        }
        var canceled = false;
        unawaited(
          cancelled.then((_) {
            canceled = true;
          }),
        );
        if (rendering case final active?) {
          final nextPacket = await active.take();
          if (canceled || !current()) throw const PlanningCancelled();
          if (nextPacket != null) {
            final result = await request(nextPacket, sequence + 1);
            if (canceled || !current()) throw const PlanningCancelled();
            ++sequence;
            return result;
          }
          previousScene = await active.result;
          wordEnd = previousScene!.scene.endWord;
          rendering = null;
        }
        if (wordEnd == manifest.totalWords && manifest.preparationComplete) {
          return null;
        }
        final next = await _findBookScene(
          session,
          wordEnd,
          () => !canceled && current(),
        );
        _BookPlaybackPart part;
        if (next == null) {
          rendering = await _beginRenderBookScene(
            session,
            wordEnd,
            () => !canceled && current(),
            cancelled: cancelled,
            previous: previousScene,
          );
          final first = await rendering!.take();
          if (first == null) throw StateError('Rendering produced no audio.');
          part = first;
        } else {
          part = _BookPlaybackPart.complete(next);
        }
        if (canceled || !current()) throw const PlanningCancelled();
        if (part.startWord != wordEnd) {
          _audioGapWord = wordEnd;
          throw StateError(
            'Audio ends at word $wordEnd. Press Play to render the next passage with its speech model.',
          );
        }
        final result = await request(part, sequence + 1);
        if (canceled || !current()) throw const PlanningCancelled();
        ++sequence;
        wordEnd = part.endWord;
        return result;
      },
    );
    final first = await request(firstPart, 0);
    if (!current()) return true;
    await (engine as RenderedAudioPlaybackCapable).playRendered(first);
    return true;
  }
}

Future<({ReaderDocument document, Map<String, String> userVoiceAssignments})>
_readBookRangeFile(String path) => Isolate.run(
  () => decodeReaderDocumentWithPreferences(File(path).readAsStringSync()),
);

Future<DocumentAnalysisRecord> _readBookAnalysisFile(String path) =>
    Isolate.run(
      () => DocumentAnalysisRecord.fromJson(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
      ),
    );

class _BookScene {
  const _BookScene(
    this.scene, {
    this.audioPath,
    this.rawAudioPath,
    this.trailingMicros,
  });
  final RadocAudioScene scene;
  final String? audioPath, rawAudioPath;
  final int? trailingMicros;
}

/// Playback metadata is either a committed scene or a packet from an owned
/// render. A packet never masquerades as a checksummed, complete package scene.
class _BookPlaybackPart {
  const _BookPlaybackPart.complete(this.scene) : packet = null;
  const _BookPlaybackPart.packet(this.packet) : scene = null;
  final _BookScene? scene;
  final TtsPlayableAudioPacket? packet;
  int get startWord => packet?.startWordIndex ?? scene!.scene.startWord;
  int get endWord => packet?.endWordIndex ?? scene!.scene.endWord;
}

/// One producer and one pull consumer. Dart's stream owns delivery/cancellation;
/// scene packet limits bound its queued metadata while the player is paused.
class _BookRenderStream {
  _BookRenderStream(this.cancellation) {
    _iterator = StreamIterator(_events.stream);
    unawaited(cancellation.future.then((_) => cancelConsumer()));
    // A replacement can abandon the result before it fails. Its stream/current
    // consumer still receives the error, without an unobserved future error.
    unawaited(
      _result.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
  final Completer<void> cancellation;
  final _events = StreamController<_BookPlaybackPart>();
  late final StreamIterator<_BookPlaybackPart> _iterator;
  final _result = Completer<_BookScene>();
  int _packets = 0;
  bool _ended = false;
  Future<_BookScene> get result => _result.future;

  void add(TtsPlayableAudioPacket packet) {
    if (_ended || cancellation.isCompleted) throw const PlanningCancelled();
    if (++_packets > SpeechAudioPacket.maxPackets) {
      throw StateError('Native scene packet buffer limit exceeded.');
    }
    _events.add(_BookPlaybackPart.packet(packet));
  }

  void complete(_BookScene scene) {
    if (_ended) return;
    if (cancellation.isCompleted) {
      fail(const PlanningCancelled(), StackTrace.current);
      return;
    }
    _ended = true;
    _result.complete(scene);
    // A valid cache hit/legacy export can complete without producing packets.
    if (_packets == 0) _events.add(_BookPlaybackPart.complete(scene));
    unawaited(_events.close());
  }

  void fail(Object error, StackTrace stack) {
    if (_ended) return;
    _ended = true;
    _result.completeError(error, stack);
    if (!cancellation.isCompleted) _events.addError(error, stack);
    unawaited(_events.close());
  }

  Future<_BookPlaybackPart?> take() async {
    if (cancellation.isCompleted) throw const PlanningCancelled();
    final hasNext = await Future.any([
      _iterator.moveNext(),
      cancellation.future.then((_) => false),
    ]);
    if (cancellation.isCompleted) throw const PlanningCancelled();
    return hasNext ? _iterator.current : null;
  }

  Future<void> cancelConsumer() => _iterator.cancel();
}

String _joinedBookSource(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

RadocAudioScene _publishedScene(StoredRenderedScene s) => RadocAudioScene(
  sceneId: s.sceneId,
  startWord: s.startWordIndex,
  endWord: s.endWordIndex,
  audioMember: 'audio/${s.sceneId}-${s.dependencyDigest}.wav',
  rawAudioMember: s.rawAudioPath == null
      ? null
      : 'raw/${s.rawDependencyDigest}.wav',
  dependencyDigest: s.dependencyDigest,
  dependencies: s.dependencies,
  provenance: {
    ...s.provenance,
    'intent': s.intent,
    'text': s.text,
    'startOffset': s.startOffset,
    'sceneTurns': s.sceneTurns.map((t) => t.toMap()).toList(),
  },
  sampleRate: s.sampleRate,
  channels: s.channels,
  frameCount: s.frameCount,
);

class _BookAudio {
  const _BookAudio(this.path, this.duration, {this.trailingMicros});
  final String path;
  final Duration duration;
  final int? trailingMicros;
}

extension ReaderAudioBookBoundaries on ReaderController {
  Future<_BookAudio> _resolveBookAudio(
    _ReaderAudioBook session,
    _BookScene value,
    _BookScene? previous,
    bool Function() current, {
    required ReaderDocument document,
    required int sourceWordOffset,
  }) async {
    final scene = value.scene;
    final previousRaw =
        previous?.scene.provenance['rawArtifactIdentity'] as String?;
    final capturedPrevious =
        scene.provenance['predecessorRawArtifactIdentity'] as String?;
    final changedPredecessor =
        previous != null &&
        previousRaw != null &&
        previousRaw != capturedPrevious;
    if (!changedPredecessor) {
      final file = value.audioPath == null
          ? await session.package.materializeMember(
              session.book,
              scene.audioMember,
              isCurrent: current,
            )
          : File(value.audioPath!);
      return _BookAudio(
        file.path,
        Duration(
          microseconds: (scene.frameCount * 1000000 / scene.sampleRate).round(),
        ),
        trailingMicros: scene.provenance['trailingSilenceMicros'] as int?,
      );
    }
    final rawMember = scene.rawAudioMember;
    final boundary = scene.provenance['boundaryClass'] as String?;
    final trailing =
        previous.trailingMicros ??
        previous.scene.provenance['trailingSilenceMicros'] as int?;
    if (rawMember == null || boundary == null || trailing == null) {
      throw StateError(
        'The preceding scene changed, but this book lacks raw boundary evidence. Render this passage again.',
      );
    }
    final rawFile = value.rawAudioPath == null
        ? await session.package.materializeMember(
            session.book,
            rawMember,
            isCurrent: current,
          )
        : File(value.rawAudioPath!);
    if (!current()) throw const PlanningCancelled();
    // Existing native-rate boundary policy owns DSP. A single bounded scene
    // worker drains before package cleanup; Pause invalidates admission at once.
    final work = _correctBookBoundary(
      rawFile.path,
      scene.sceneId,
      boundary,
      trailing,
      previousRaw,
    );
    session.boundaryWork = work;
    final audio = await work;
    if (!current()) throw const PlanningCancelled();
    final raw = scene.dependencies['raw'] as Map?;
    final bindings = scene.provenance['bindings'] as List?;
    if (raw == null || bindings == null) {
      throw const FormatException('Missing reusable scene dependencies.');
    }
    final cancelled = Completer<void>();
    await _renderedSceneWriter(
      document: document,
      sourceWordOffset: sourceWordOffset,
    )(
      TtsFinalizedAudioScene(
        documentId: session.book.manifest.documentId,
        generationId: 'book-boundary',
        sceneId: scene.sceneId,
        text: scene.provenance['text'] as String,
        engineSpeakText: raw['engineSpeakText'] as String,
        startWordIndex: scene.startWord,
        endWordIndex: scene.endWord,
        startOffset: scene.provenance['startOffset'] as int,
        sceneTurns: (scene.provenance['sceneTurns'] as List)
            .map(
              (t) =>
                  NativeSpeechTurn.fromMap(Map<String, dynamic>.from(t as Map)),
            )
            .toList(),
        preparedBindings: bindings
            .map((b) => PreparedVoiceBinding.fromMap(b as Map))
            .toList(),
        audioPath: audio.path,
        duration: audio.duration,
        engineId: raw['engineId'] as String,
        engineVersion: raw['engineVersion'] as String,
        normalizationVersion: raw['normalizationVersion'] as String,
        capabilityProfileId: raw['capabilityProfileId'] as String,
        synthesisIdentity: raw['synthesisIdentity'] as String,
        translationSignature: raw['translationSignature'] as String,
        synthesisRate: (raw['synthesisRate'] as num).toDouble(),
        assignmentRevision: voiceAssignmentState.requestedRevision,
        cancelled: cancelled.future,
        isCurrent: current,
        rawAudioPath: rawFile.path,
        rawArtifactIdentity: scene.provenance['rawArtifactIdentity'] as String?,
        predecessorRawArtifactIdentity: previousRaw,
        boundaryPolicyVersion: SynthesisBoundaryPolicy.version,
        boundaryClass: boundary,
        trailingSilenceMicros: audio.trailingMicros,
      ),
    );
    return audio;
  }
}

Future<_BookAudio> _correctBookBoundary(
  String rawPath,
  String sceneId,
  String boundary,
  int previousTrailing,
  String? previousRaw,
) => Isolate.run(() {
  final outcome = const SynthesisBoundaryPolicy().correctWavFileSync(
    chunkId: sceneId,
    wavFilePath: rawPath,
    boundaryClass: BreakClass.values.byName(boundary),
    isInitialChunk: false,
    isResumedChunk: false,
    previousTrailingSilence: Duration(microseconds: previousTrailing),
    previousArtifactIdentity: previousRaw,
  );
  final path = outcome.audioPath ?? rawPath;
  final format = AudioArtifactStore.validateWav(File(path).readAsBytesSync());
  return _BookAudio(
    path,
    Duration(
      microseconds: (format.frames * 1000000 / format.sampleRate).round(),
    ),
    trailingMicros: outcome.trailingSilenceAfter.inMicroseconds,
  );
});

List<Map<String, Object?>> _canonicalSceneDirections(
  ReaderDocument document,
  int offset,
  int startWord,
  int endWord,
) {
  final starts = <String, int>{};
  var word = offset;
  for (final segment in document.speechDocument.segments) {
    starts[segment.segmentId] = word;
    word += segment.wordCount;
  }
  final result = <Map<String, Object?>>[];
  for (final annotation in document.baseSpeechAnnotations.annotations) {
    if (annotation.deliveryIntent == null &&
        annotation.inflectionIntent == null) {
      continue;
    }
    final segmentStart = starts[annotation.segmentId];
    if (segmentStart == null) continue;
    final start = segmentStart + annotation.startWord;
    final end = segmentStart + annotation.endWord;
    if (start < endWord && end > startWord) {
      result.add({
        'startWord': start,
        'endWord': end,
        'source': annotation.source.name,
        'confidence': annotation.confidence,
        'delivery': annotation.deliveryIntent?.name,
        'inflection': annotation.inflectionIntent?.name,
      });
    }
  }
  result.sort((a, b) => artifactIdentity(a).compareTo(artifactIdentity(b)));
  return result;
}

// Keep prefix ordinals/word coordinates intact while preventing the planner
// from admitting an unaffected following scene. Runs on an already bounded
// prepared range; synthesis and realization remain worker-owned.
SpeechDocument _bookSpeechPrefix(SpeechDocument source, int endWord) {
  var count = 0;
  final segments = <SpeechSegment>[];
  for (final segment in source.segments) {
    if (count >= endWord) break;
    if (count + segment.wordCount > endWord) {
      throw StateError("Saved scene ends inside a prepared segment.");
    }
    segments.add(segment);
    count += segment.wordCount;
  }
  if (count != endWord) {
    throw StateError('Saved scene exceeds prepared source.');
  }
  return SpeechDocument(
    documentId: source.documentId,
    sourceType: source.sourceType,
    languageTag: source.languageTag,
    segments: List.unmodifiable(segments),
    segmentIndexById: {
      for (var i = 0; i < segments.length; i++) segments[i].segmentId: i,
    },
    totalWordCount: count,
    normalizationVersion: source.normalizationVersion,
  );
}
