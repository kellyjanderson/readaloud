part of 'reader_controller.dart';

extension ReaderAudioBookPersistence on ReaderController {
  /// Playback and export each await one callback on their own producer tail:
  /// one can publish while the other waits. Keep cancellable waiting outside
  /// Lock's non-removable queue so retired callers detach without queued I/O.
  Future<void> _admitRenderedScene(
    TtsFinalizedAudioScene scene, {
    required bool Function() isCurrent,
    required Future<void> Function() publish,
  }) async {
    if (!isCurrent()) return;
    while (_renderedScenePublicationLock.locked) {
      final previous = _renderedScenePublication!;
      final ready = await Future.any([
        previous.then((_) => true),
        scene.cancelled.then((_) => false),
      ]);
      if (!ready || !isCurrent()) return;
    }
    if (!isCurrent()) return;
    final completed = Completer<void>();
    _renderedScenePublication = completed.future;
    try {
      // No await separates the unlocked check from lock acquisition on the
      // controller isolate. The maintained lock owns active work, never waits.
      await _renderedScenePublicationLock.synchronized(publish);
    } finally {
      // Failure belongs to this producer; another caller waits only for drain.
      completed.complete();
    }
  }

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
    Map<String, dynamic>? preservedIntent,
    bool Function()? isCurrent,
    void Function()? onPersisted,
  }) {
    final capturedDocument = document ?? _document;
    final capturedOffset =
        sourceWordOffset ?? _activePreparedRange?.range.wordStart ?? 0;
    final source =
        _activeSourceRevision ??
        _document.normalizedImportResult.sourceFingerprint;
    final intent = Map<String, dynamic>.from(preservedIntent ?? _bookIntent());
    final revision = _documentRevision;
    final epoch = _engineEpoch;
    return (scene) {
      bool current() =>
          !_disposed &&
          epoch == _engineEpoch &&
          revision == _documentRevision &&
          scene.isCurrent() &&
          (isCurrent?.call() ?? true);
      return _admitRenderedScene(
        scene,
        isCurrent: current,
        publish: () async {
          var repository = _renderedScenes;
          if (repository == null) {
            try {
              final support = await getApplicationSupportDirectory();
              if (!current()) {
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
              isCurrent == null
                  ? scene
                  : _sceneWithPublicationOwner(scene, current),
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
            onPersisted?.call();
            if (!current()) {
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
            if (!current()) {
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
        },
      );
    };
  }

  /// Explicit publishing enumerates committed ranges sequentially. PCM and
  /// prepared graph serialization stay on their existing worker paths. A book
  /// with no rendered output retains the legacy JSON export route.
  Future<File?> _exportAudioBookToPath(
    String outputPath,
    int revision, {
    bool force = false,
    void Function(ReadingStageTicket)? onOperation,
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
    // A cold plain-document session may already have committed scenes from an
    // earlier run, without opening a v5 book or producing new audio this run.
    await _ensureSceneRepository();
    requireCurrent();
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
    return _trackBookOperation<File?>(revision, 'Save audio book', (
      report,
    ) async {
      final stage = await Directory.systemTemp.createTemp('radoc-publish-');
      final transport = RadocAudioPackage(
        createExportStage: Platform.isMacOS
            ? const RadocExportStaging().createStage
            : null,
        onProgress: report,
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
            throw const FormatException(
              'Prepared publishing ranges have a gap.',
            );
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
            scenes.add(
              _bookSceneForPublication(
                scene,
                intent,
                sourceBookIntent: importedHandle.manifest.intent,
              ),
            );
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
            _bookSceneForPublication(
              _publishedScene(s),
              intent,
              sourceBookIntent: importedHandle?.manifest.intent,
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
        if (!current()) throw const PlanningCancelled();
        _statusMessage = 'Saved audio book to $outputPath.';
        return File(outputPath);
      } finally {
        await transport.dispose();
        await stage.delete(recursive: true);
      }
    }, onOperation: onOperation);
  }
}

RadocAudioScene _bookSceneForPublication(
  RadocAudioScene scene,
  Map<String, dynamic> bookIntent, {
  Map<String, dynamic>? sourceBookIntent,
}) {
  final captured = _capturedBookSceneIntent(scene, sourceBookIntent);
  if (captured == null) return scene;
  // Published VoiceProfiles are read only from manifest.intent. Keep their
  // identical descriptions once, rather than once per native scene. All
  // scene-specific intent and exact raw model/capability/binding dependencies
  // remain captured; a different engine or catalogue never shares this copy.
  final intent = Map<String, dynamic>.from(captured);
  if (_bookSceneSharesEngine(scene, captured, bookIntent) &&
      captured['voices'] is List &&
      bookIntent['voices'] is List &&
      jsonEncode(captured['voices']) == jsonEncode(bookIntent['voices'])) {
    intent.remove('voices');
  }
  if (jsonEncode(intent) == jsonEncode(scene.provenance['intent'])) {
    return scene;
  }
  return RadocAudioScene(
    sceneId: scene.sceneId,
    startWord: scene.startWord,
    endWord: scene.endWord,
    audioMember: scene.audioMember,
    rawAudioMember: scene.rawAudioMember,
    dependencyDigest: scene.dependencyDigest,
    dependencies: scene.dependencies,
    provenance: {...scene.provenance, 'intent': intent},
    sampleRate: scene.sampleRate,
    channels: scene.channels,
    frameCount: scene.frameCount,
  );
}

// A compacted scene shares only its original root's descriptive catalogue.
// Restore that copy before moving the scene to another root or committing a
// new boundary derivative. Never borrow catalogue metadata across engines.
Map<String, dynamic>? _capturedBookSceneIntent(
  RadocAudioScene scene,
  Map<String, dynamic>? bookIntent,
) {
  final captured = scene.provenance['intent'];
  if (captured is! Map) return null;
  final intent = Map<String, dynamic>.from(captured);
  if (!intent.containsKey('voices') &&
      bookIntent != null &&
      bookIntent['voices'] is List &&
      _bookSceneSharesEngine(scene, intent, bookIntent)) {
    intent['voices'] = bookIntent['voices'];
  }
  return intent;
}

bool _bookSceneSharesEngine(
  RadocAudioScene scene,
  Map captured,
  Map bookIntent,
) {
  final engine = captured['engineId'];
  final raw = scene.dependencies['raw'];
  return engine is String &&
      engine.isNotEmpty &&
      engine == bookIntent['engineId'] &&
      raw is Map &&
      raw['engineId'] == engine;
}

Future<void> _writeBookAnalysisFile(
  String path,
  DocumentAnalysisRecord record,
) => Isolate.run(
  () => File(path).writeAsStringSync(jsonEncode(record.toJson()), flush: true),
);

// Preserve the accepted engine evidence byte-for-byte while narrowing durable
// admission independently of the already-captured WAV export's lifetime.
TtsFinalizedAudioScene _sceneWithPublicationOwner(
  TtsFinalizedAudioScene scene,
  bool Function() isCurrent,
) => TtsFinalizedAudioScene(
  documentId: scene.documentId,
  generationId: scene.generationId,
  sceneId: scene.sceneId,
  text: scene.text,
  engineSpeakText: scene.engineSpeakText,
  startWordIndex: scene.startWordIndex,
  endWordIndex: scene.endWordIndex,
  startOffset: scene.startOffset,
  sceneTurns: scene.sceneTurns,
  preparedBindings: scene.preparedBindings,
  audioPath: scene.audioPath,
  duration: scene.duration,
  engineId: scene.engineId,
  engineVersion: scene.engineVersion,
  normalizationVersion: scene.normalizationVersion,
  capabilityProfileId: scene.capabilityProfileId,
  synthesisIdentity: scene.synthesisIdentity,
  translationSignature: scene.translationSignature,
  synthesisRate: scene.synthesisRate,
  assignmentRevision: scene.assignmentRevision,
  cancelled: scene.cancelled,
  isCurrent: isCurrent,
  rawAudioPath: scene.rawAudioPath,
  rawArtifactIdentity: scene.rawArtifactIdentity,
  predecessorRawArtifactIdentity: scene.predecessorRawArtifactIdentity,
  boundaryPolicyVersion: scene.boundaryPolicyVersion,
  boundaryClass: scene.boundaryClass,
  trailingSilenceMicros: scene.trailingSilenceMicros,
);
