part of 'reader_controller.dart';

extension ReaderAudioBookPersistence on ReaderController {
  Future<void> _ensureSceneRepository() async {
    if (_renderedScenes != null) return;
    try {
      final support = await getApplicationSupportDirectory();
      if (!_disposed) {
        _renderedScenes ??= RenderedSceneRepository(
          Directory(p.join(support.path, 'rendered-scenes')),
        );
      }
    } on MissingPluginException {
      // Platform-free tests inject their store. Real application builds provide
      // path_provider; a failed durable publication is still an actionable error.
    }
  }

  Map<String, dynamic> _bookIntent() => {
    'defaultVoiceId': _selectedVoiceId,
    'multiVoice': _isMultiVoiceEnabled,
    'rate': currentSpeed,
    'engineId': _engineId(),
    'voices': [
      for (final v in _voices)
        {
          'id': v.id,
          'label': v.label,
          'locale': v.locale,
          'gender': v.gender?.name,
        },
    ],
    'characterSelections': Map<String, String>.of(
      _characters.selections(_voicePreferenceDocumentId),
    ),
  };

  Future<void> Function(TtsFinalizedAudioScene) _renderedSceneWriter({
    ReaderDocument? document,
    int? sourceWordOffset,
  }) {
    final capturedDocument = document ?? _document;
    final capturedOffset =
        sourceWordOffset ?? _activePreparedRange?.range.wordStart ?? 0;
    final source =
        _activeSourceRevision ??
        _document.normalizedImportResult.sourceFingerprint;
    final intent = _bookIntent();
    final revision = _documentRevision;
    final epoch = _engineEpoch;
    return (scene) async {
      if (_disposed ||
          epoch != _engineEpoch ||
          revision != _documentRevision ||
          !scene.isCurrent()) {
        return;
      }
      var repository = _renderedScenes;
      if (repository == null) {
        try {
          final support = await getApplicationSupportDirectory();
          if (_disposed ||
              epoch != _engineEpoch ||
              revision != _documentRevision ||
              !scene.isCurrent()) {
            return;
          }
          repository = _renderedScenes ??= RenderedSceneRepository(
            Directory(p.join(support.path, 'rendered-scenes')),
          );
        } on MissingPluginException {
          // Platform-free legacy fakes have no support directory. Native app
          // persistence failures propagate through the engine's error boundary.
          if (!kDebugMode) rethrow;
          return;
        }
      }
      final ticket = beginReadingStage(
        PreparationStage.persistence,
        producerId: 'rendered-scene-store',
        scope: 'Saved scene output',
      );
      publishReadingStage(
        ticket,
        const PreparationProgress(
          stage: PreparationStage.persistence,
          state: PreparationWorkState.working,
          completed: 0,
          total: 1,
          unit: 'scenes',
        ),
      );
      try {
        await repository.publish(
          scene,
          sourceId: source,
          intent: {
            ...intent,
            'canonicalDirections': _canonicalSceneDirections(
              capturedDocument,
              capturedOffset,
              scene.startWordIndex,
              scene.endWordIndex,
            ),
          },
        );
        if (_disposed ||
            epoch != _engineEpoch ||
            revision != _documentRevision ||
            !scene.isCurrent()) {
          return;
        }
        publishReadingStage(
          ticket,
          const PreparationProgress(
            stage: PreparationStage.persistence,
            state: PreparationWorkState.complete,
            completed: 1,
            total: 1,
            unit: 'scenes',
          ),
        );
      } catch (error) {
        if (_disposed ||
            epoch != _engineEpoch ||
            revision != _documentRevision ||
            !scene.isCurrent()) {
          return;
        }
        publishReadingStage(
          ticket,
          PreparationProgress(
            stage: PreparationStage.persistence,
            state: PreparationWorkState.failed,
            completed: 0,
            total: 1,
            unit: 'scenes',
            error: '$error',
          ),
        );
        rethrow;
      }
    };
  }

  /// Explicit publishing enumerates committed ranges sequentially. PCM and
  /// prepared graph serialization stay on their existing worker paths. A book
  /// with no rendered output retains the legacy JSON export route.
  Future<File?> _exportAudioBookToPath(
    String outputPath,
    int revision, {
    bool force = false,
  }) async {
    final intent = _bookIntent();
    final assignment = voiceAssignmentState.requestedRevision;
    final speed = currentSpeed;
    final epoch = _engineEpoch;
    bool current() =>
        !_disposed &&
        revision == _documentRevision &&
        assignment == voiceAssignmentState.requestedRevision &&
        speed == currentSpeed &&
        epoch == _engineEpoch;
    void requireCurrent() {
      if (!current()) throw const PlanningCancelled();
    }

    final source =
        _audioBook?.book.manifest.sourceId ??
        _activeSourceRevision ??
        _document.normalizedImportResult.sourceFingerprint;
    final imported = _audioBook;
    var repository = _renderedScenes;
    // A separate read owner never competes with the serialized publication
    // callback. Both observe immutable, atomically committed generations.
    RenderedSceneRepository? reader;
    final stored = <StoredRenderedScene>[];
    if (repository != null) {
      reader = RenderedSceneRepository(repository.root);
      try {
        stored.addAll(await reader.scenesForSource(source, isCurrent: current));
      } finally {
        await reader.dispose();
      }
    }
    requireCurrent();
    if (!force && imported == null && stored.isEmpty) return null;
    final stage = await Directory.systemTemp.createTemp('radoc-publish-');
    final transport = RadocAudioPackage(
      createExportStage: Platform.isMacOS
          ? const RadocExportStaging().createStage
          : null,
      onProgress: (p) {
        if (current()) _bookProgress(p, revision);
      },
    );
    RadocAudioBook? importedHandle;
    try {
      if (imported != null) {
        importedHandle = await transport.open(
          File(imported.book.packagePath),
          isCurrent: current,
        );
        if (importedHandle.manifestDigest != imported.book.manifestDigest) {
          throw const FormatException(
            'The source audio book changed. Reopen it before publishing.',
          );
        }
      }
      final members = <String, File>{};
      final ranges = <RadocPreparedRange>[];
      final count = _publicationSequence == 0 ? 1 : _publicationSequence;
      var totalWords = 0;
      for (var i = 1; i <= count; i++) {
        requireCurrent();
        final range = _publicationSequence == 0
            ? null
            : await readPreparedRange(i);
        requireCurrent();
        final document = range?.fragment ?? _document;
        _characters.restoreDocument(
          _voicePreferenceDocumentId,
          document.characterCastRegistry,
        );
        final selections = Map<String, String>.of(
          _characters.selections(_voicePreferenceDocumentId),
        );
        final start = range?.range.wordStart ?? 0;
        final end = range?.range.wordEnd ?? document.wordCount;
        if (start != totalWords) {
          throw const FormatException('Prepared publishing ranges have a gap.');
        }
        final member = 'prepared/$i.json';
        // Preserve each range's explicit choices. Later range Characters keep
        // their choices in their own range and the shared registry.
        final file = await const ReaderDocumentSerializationService()
            .writeToFile(
              document: document,
              outputPath: p.join(stage.path, '$i.json'),
              isCurrent: current,
              characters: _characters.registry(
                _voicePreferenceDocumentId,
                documentId: document.displayDocument.documentId,
              ),
              userVoiceAssignments: {
                for (final entry in selections.entries)
                  if (document.characterCastRegistry.entries.any(
                        (c) => c.castId == entry.key,
                      ) ||
                      document.characterCastRegistry.castIdRedirects
                          .containsKey(entry.key))
                    entry.key: entry.value,
              },
            );
        members[member] = file;
        ranges.add(
          RadocPreparedRange(member: member, startWord: start, endWord: end),
        );
        totalWords = end;
      }
      final scenes = <RadocAudioScene>[];
      // Old package scenes remain valid data even when changed intent makes
      // them temporarily unsuitable for playback. New versions replace only
      // overlapping native source spans; unrelated files retain exact bytes.
      if (importedHandle != null) {
        for (final scene in importedHandle.manifest.scenes) {
          if (stored.any(
            (s) =>
                s.startWordIndex < scene.endWord &&
                scene.startWord < s.endWordIndex,
          )) {
            continue;
          }
          members[scene.audioMember] = await transport.materializeMember(
            importedHandle,
            scene.audioMember,
            isCurrent: current,
          );
          if (scene.rawAudioMember case final raw?) {
            members[raw] = await transport.materializeMember(
              importedHandle,
              raw,
              isCurrent: current,
            );
          }
          scenes.add(scene);
        }
      }
      for (final s in stored) {
        final audio = 'audio/${s.sceneId}-${s.dependencyDigest}.wav';
        final raw = s.rawAudioPath == null
            ? null
            : 'raw/${s.rawDependencyDigest}.wav';
        members[audio] = File(s.audioPath);
        if (raw != null) members[raw] = File(s.rawAudioPath!);
        scenes.add(
          RadocAudioScene(
            sceneId: s.sceneId,
            startWord: s.startWordIndex,
            endWord: s.endWordIndex,
            audioMember: audio,
            rawAudioMember: raw,
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
          ),
        );
      }
      scenes.sort((a, b) => a.startWord.compareTo(b.startWord));
      final analysis = <String>[];
      // Preserve already-published independent analysis members byte for byte.
      if (importedHandle != null) {
        for (final member in importedHandle.manifest.analysisMembers) {
          members[member] = await transport.materializeMember(
            importedHandle,
            member,
            isCurrent: current,
          );
          analysis.add(member);
        }
      }
      final analysisRepository = _preparation.repository?.analysis;
      if (analysisRepository != null) {
        final records = await analysisRepository.recordsForSource(source);
        for (final record in records) {
          final member = 'analysis/${record.key}.json';
          if (members.containsKey(member)) continue;
          final filePath = p.join(stage.path, '${record.key}.analysis.json');
          await _writeBookAnalysisFile(filePath, record);
          members[member] = File(filePath);
          analysis.add(member);
        }
      }
      requireCurrent();
      await transport.export(
        destination: File(outputPath),
        manifest: RadocAudioManifest(
          documentId: sessionDocumentId,
          sourceId: source,
          preparationComplete:
              _preparationComplete || _hasCompleteDocumentSnapshot,
          totalWords: totalWords,
          preparedRanges: ranges,
          analysisMembers: analysis,
          scenes: scenes,
          intent: intent,
        ),
        members: members,
        isCurrent: current,
      );
      requireCurrent();
      _preparationProgress.remove(PreparationStage.persistence);
      if (!current()) throw const PlanningCancelled();
      _statusMessage = 'Saved audio book to $outputPath.';
      return File(outputPath);
    } finally {
      await transport.dispose();
      await stage.delete(recursive: true);
    }
  }
}

Future<void> _writeBookAnalysisFile(
  String path,
  DocumentAnalysisRecord record,
) => Isolate.run(
  () => File(path).writeAsStringSync(jsonEncode(record.toJson()), flush: true),
);
