import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/native_speech_turn.dart';
import 'audio_artifact_store.dart';
import 'tts_engine.dart';

class RenderedSceneCancelled implements Exception {
  const RenderedSceneCancelled();
  @override
  String toString() => 'Rendered scene operation cancelled.';
}

/// Validated durable scene evidence. Paths are resolved locally, never identity
/// inputs. Source spans are global; startOffset remains local to prepared text.
class StoredRenderedScene {
  StoredRenderedScene._(this.metadata, this.audioPath, this.rawAudioPath);
  final Map<String, dynamic> metadata;
  final String audioPath;
  final String? rawAudioPath;
  String get sourceId => metadata['sourceId'] as String;
  String get sceneId => metadata['sceneId'] as String;
  String get dependencyDigest => metadata['dependencyDigest'] as String;
  String get rawDependencyDigest => metadata['rawDependencyDigest'] as String;
  Map<String, dynamic> get dependencies =>
      metadata['dependencies'] as Map<String, dynamic>;
  Map<String, dynamic> get provenance =>
      metadata['provenance'] as Map<String, dynamic>;
  Map<String, dynamic> get intent => metadata['intent'] as Map<String, dynamic>;
  int get startWordIndex => metadata['startWordIndex'] as int;
  int get endWordIndex => metadata['endWordIndex'] as int;
  int get startOffset => metadata['startOffset'] as int;
  String get text => metadata['text'] as String;
  String get engineSpeakText => metadata['engineSpeakText'] as String;
  int get sampleRate => metadata['sampleRate'] as int;
  int get channels => 1;
  int get frameCount => metadata['frameCount'] as int;
  Duration get duration =>
      Duration(microseconds: (frameCount * 1000000 / sampleRate).round());
  List<NativeSpeechTurn> get sceneTurns => List.unmodifiable(
    (metadata['turns'] as List).map(
      (v) => NativeSpeechTurn.fromMap(Map<String, dynamic>.from(v as Map)),
    ),
  );
}

/// One active operation and no waiting queue. The owning isolate snapshots small
/// scene evidence and owns admission; a disposable platform isolate owns JSON,
/// WAV copying/checksums and validated reads. Cancellation kills and joins it
/// before releasing artifact pins or permitting another operation. The sole
/// owner-isolate filesystem operation is the final atomic metadata rename: its
/// current check and rename form the admission linearization point. No committed
/// output is deleted. Failed/cancelled attempts may leave unreferenced artifacts.
class RenderedSceneRepository {
  RenderedSceneRepository(
    this.root, {
    this.timeout = const Duration(seconds: 30),
  });
  final Directory root;
  final Duration timeout;
  static const maxScenes = 10000;
  static const maxMetadataBytes = 2 * 1024 * 1024;
  static const maxAudioBytes = 64 * 1024 * 1024;
  _SceneJob? _active;
  bool _disposed = false;
  int get activeCount => _active == null ? 0 : 1;

  Future<StoredRenderedScene> publish(
    TtsFinalizedAudioScene scene, {
    required String sourceId,
    required Map<String, dynamic> intent,
  }) async {
    if (!scene.isCurrent()) throw const RenderedSceneCancelled();
    final pins = [
      AudioArtifactPins.shared.pin(scene.audioPath),
      if (scene.rawAudioPath != null)
        AudioArtifactPins.shared.pin(scene.rawAudioPath!),
    ];
    try {
      final result = await _execute(
        {
          'operation': 'publish',
          'sourceId': sourceId,
          'intent': intent,
          'text': scene.text,
          'engineSpeakText': scene.engineSpeakText,
          'startWordIndex': scene.startWordIndex,
          'endWordIndex': scene.endWordIndex,
          'startOffset': scene.startOffset,
          'turns': scene.sceneTurns.map((t) => t.toMap()).toList(),
          'bindings': scene.preparedBindings.map((b) => b.toMap()).toList(),
          'audioPath': scene.audioPath,
          'rawAudioPath': scene.rawAudioPath,
          'engineId': scene.engineId,
          'engineVersion': scene.engineVersion,
          'normalizationVersion': scene.normalizationVersion,
          'capabilityProfileId': scene.capabilityProfileId,
          'synthesisIdentity': scene.synthesisIdentity,
          'translationSignature': scene.translationSignature,
          'synthesisRate': scene.synthesisRate,
          'rawArtifactIdentity': scene.rawArtifactIdentity,
          'predecessorRawArtifactIdentity':
              scene.predecessorRawArtifactIdentity,
          'boundaryPolicyVersion': scene.boundaryPolicyVersion,
          'boundaryClass': scene.boundaryClass,
          'trailingSilenceMicros': scene.trailingSilenceMicros,
        },
        isCurrent: scene.isCurrent,
        cancelled: scene.cancelled,
      );
      return result as StoredRenderedScene;
    } finally {
      for (final pin in pins) {
        pin.release();
      }
    }
  }

  /// Explicit export enumeration, bounded independently of document length.
  /// Returns the newest admitted version of each stable source span, in order.
  /// Corruption fails visibly rather than masquerading as EOF or empty coverage.
  Future<List<StoredRenderedScene>> scenesForSource(
    String sourceId, {
    int limit = maxScenes,
    bool Function()? isCurrent,
  }) async {
    if (limit < 1 || limit > maxScenes) {
      throw ArgumentError.value(limit, 'limit');
    }
    return (await _execute({
          'operation': 'read',
          'sourceId': sourceId,
          'limit': limit,
        }, isCurrent: isCurrent))
        as List<StoredRenderedScene>;
  }

  Future<StoredRenderedScene?> sceneAt(
    String sourceId,
    int word, {
    Map<String, dynamic>? intent,
    bool Function()? isCurrent,
  }) async =>
      (await _execute({
            'operation': 'read',
            'sourceId': sourceId,
            'word': word,
            'intent': intent,
            'limit': maxScenes,
          }, isCurrent: isCurrent))
          as StoredRenderedScene?;

  /// Playback already knows scene starts from its bounded source manifest.
  /// Read only that span's versions; never enumerate a whole book to start audio.
  Future<StoredRenderedScene?> sceneStartingAt(
    String sourceId,
    int startWord, {
    bool Function()? isCurrent,
  }) async =>
      (await _execute({
            'operation': 'read',
            'sourceId': sourceId,
            'word': startWord,
            'exactStart': true,
            'limit': 1,
          }, isCurrent: isCurrent))
          as StoredRenderedScene?;

  Future<void> cancelAndDrain() async {
    final job = _active;
    if (job == null) return;
    if (!job.cancelled.isCompleted) job.cancelled.complete();
    await job.drained.future;
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancelAndDrain();
  }

  Future<Object?> _execute(
    Map<String, dynamic> request, {
    bool Function()? isCurrent,
    Future<void>? cancelled,
  }) async {
    if (_disposed) throw StateError('Rendered scene repository is disposed.');
    if (_active != null) throw StateError('Rendered scene repository is busy.');
    final job = _SceneJob();
    _active = job;
    // Copy mutable caller evidence before the first suspension. PCM never crosses
    // this port; only bounded scene evidence and local file paths do.
    final messages = ReceivePort();
    final response = Completer<Map<String, dynamic>>();
    final exited = Completer<void>();
    final subscription = messages.listen((message) {
      if (message == null) {
        if (!exited.isCompleted) exited.complete();
        if (!response.isCompleted) {
          response.completeError(
            StateError('Scene worker exited without result.'),
          );
        }
      } else if (message is List) {
        if (!response.isCompleted) {
          response.completeError(StateError('$message'));
        }
      } else if (!response.isCompleted) {
        response.complete(Map<String, dynamic>.from(message as Map));
      }
    });
    Isolate? worker;
    Timer? timer;
    try {
      final snapshot = _copyJson(request) as Map<String, dynamic>;
      worker = await Isolate.spawn(
        _sceneWorker,
        {...snapshot, 'root': root.path, 'reply': messages.sendPort},
        onExit: messages.sendPort,
        onError: messages.sendPort,
      );
      void cancel() {
        if (!job.cancelled.isCompleted) job.cancelled.complete();
      }

      cancelled?.then((_) => cancel(), onError: (Object _) => cancel());
      timer = Timer(timeout, cancel);
      final result = await Future.any([
        response.future,
        job.cancelled.future.then<Map<String, dynamic>>(
          (_) => throw const RenderedSceneCancelled(),
        ),
      ]);
      if (job.cancelled.isCompleted || !(isCurrent?.call() ?? true)) {
        throw const RenderedSceneCancelled();
      }
      if (result['error'] != null) {
        throw FormatException(result['error'] as String);
      }
      if (request['operation'] == 'publish') {
        // Tiny atomic commit only. All serialization, flush and parent creation
        // happened in the worker. No await may split current-check and rename.
        File(
          result['stage'] as String,
        ).renameSync(result['destination'] as String);
        return _stored(result['scene'] as Map<String, dynamic>);
      }
      final scenes = (result['scenes'] as List)
          .map((v) => _stored(Map<String, dynamic>.from(v as Map)))
          .toList(growable: false);
      return request.containsKey('word')
          ? (scenes.isEmpty ? null : scenes.single)
          : scenes;
    } finally {
      timer?.cancel();
      worker?.kill(priority: Isolate.immediate);
      if (worker != null) await exited.future;
      await subscription.cancel();
      messages.close();
      _active = null;
      job.drained.complete();
    }
  }
}

class _SceneJob {
  final cancelled = Completer<void>();
  final drained = Completer<void>();
}

Object? _copyJson(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _copyJson(entry.value),
    };
  }
  if (value is List) return value.map(_copyJson).toList();
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw ArgumentError('Scene evidence must be JSON data.');
}

Object? _freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freezeJson(entry.value),
    });
  }
  if (value is List) return List.unmodifiable(value.map(_freezeJson));
  return value;
}

StoredRenderedScene _stored(Map<String, dynamic> value) =>
    StoredRenderedScene._(
      _freezeJson(value['metadata']) as Map<String, dynamic>,
      value['audioPath'] as String,
      value['rawAudioPath'] as String?,
    );

Future<void> _sceneWorker(Map<String, dynamic> request) async {
  final reply = request['reply'] as SendPort;
  try {
    final result = request['operation'] == 'publish'
        ? _stageScene(request)
        : await _readScenes(request);
    Isolate.exit(reply, result);
  } catch (error) {
    Isolate.exit(reply, {'error': 'Rendered scene persistence: $error'});
  }
}

Map<String, dynamic> _stageScene(Map<String, dynamic> r) {
  final source = r['sourceId'] as String;
  final start = r['startWordIndex'] as int;
  final end = r['endWordIndex'] as int;
  if (source.isEmpty ||
      start < 0 ||
      end <= start ||
      (r['synthesisRate'] as num) <= 0) {
    throw const FormatException('Invalid source scene span or rate.');
  }
  final sceneId = artifactIdentity([
    'rendered-source-span-v1',
    source,
    start,
    end,
  ]);
  final usedVoices = (r['turns'] as List)
      .map((t) => (t as Map)['voice'])
      .toSet();
  final bindings =
      (r['bindings'] as List)
          .where((b) => usedVoices.contains((b as Map)['voiceId']))
          .map((v) {
            final b = v as Map;
            return {
              for (final k in [
                'voiceId',
                'voiceDigest',
                'modelDigest',
                'engineVersion',
                'pronunciationProfileId',
              ])
                k: b[k],
            };
          })
          .toList()
        ..sort((a, b) => artifactIdentity(a).compareTo(artifactIdentity(b)));
  final rawDependencies = <String, dynamic>{
    'canonicalDirections': (r['intent'] as Map)['canonicalDirections'],
    for (final key in [
      'text',
      'engineSpeakText',
      'engineId',
      'engineVersion',
      'normalizationVersion',
      'capabilityProfileId',
      'synthesisIdentity',
      'translationSignature',
      'synthesisRate',
    ])
      key: r[key],
    'turns': (r['turns'] as List).map((v) {
      final t = v as Map;
      return {
        for (final k in [
          'voice',
          'text',
          'startWord',
          'endWord',
          'bindingFingerprint',
          'castId',
          'directions',
        ])
          k: t[k],
      };
    }).toList(),
    'bindings': bindings,
  };
  final rawDigest = artifactIdentity(rawDependencies);
  final dependencies = {
    'raw': rawDependencies,
    'predecessorRawArtifactIdentity': r['predecessorRawArtifactIdentity'],
    'boundaryPolicyVersion': r['boundaryPolicyVersion'],
  };
  final digest = artifactIdentity(dependencies);
  final store = AudioArtifactStore(Directory('${r['root']}/artifacts'));
  AudioArtifact copy(String path, String kind) {
    final file = File(path);
    if (file.lengthSync() > RenderedSceneRepository.maxAudioBytes) {
      throw const FormatException('Scene audio exceeds bounded size.');
    }
    final bytes = file.readAsBytesSync();
    // Local immutable storage uses content identity. Captured synthesis/raw keys
    // remain provenance and never let incorrect upstream reuse replace bytes.
    return store.publish(
      identity: sha256.convert(bytes).toString(),
      wav: bytes,
      metadata: {'kind': kind},
    );
  }

  final finalAudio = copy(r['audioPath'] as String, 'final');
  final raw = r['rawAudioPath'] == null
      ? null
      : copy(r['rawAudioPath'] as String, 'raw');
  final metadata = <String, dynamic>{
    'schema': 1,
    'sourceId': source,
    'sceneId': sceneId,
    'dependencyDigest': digest,
    'rawDependencyDigest': rawDigest,
    'dependencies': dependencies,
    'provenance': {
      'rawArtifactIdentity': r['rawArtifactIdentity'],
      'predecessorRawArtifactIdentity': r['predecessorRawArtifactIdentity'],
      'boundaryPolicyVersion': r['boundaryPolicyVersion'],
      'boundaryClass': r['boundaryClass'],
      'trailingSilenceMicros': r['trailingSilenceMicros'],
      'bindings': r['bindings'],
    },
    for (final key in [
      'intent',
      'text',
      'engineSpeakText',
      'startWordIndex',
      'endWordIndex',
      'startOffset',
      'turns',
    ])
      key: r[key],
    'audioArtifactIdentity': finalAudio.identity,
    'rawAudioArtifactIdentity': raw?.identity,
    'sampleRate': finalAudio.sampleRate,
    'channels': 1,
    'frameCount': finalAudio.frames,
    'committedMicros': DateTime.now().microsecondsSinceEpoch,
  };
  final envelope = jsonEncode({
    'metadata': metadata,
    'checksum': artifactIdentity(metadata),
  });
  if (utf8.encode(envelope).length > RenderedSceneRepository.maxMetadataBytes) {
    throw const FormatException('Scene metadata exceeds bounded size.');
  }
  final directory = Directory(
    '${r['root']}/scenes/${artifactIdentity(source)}/$start',
  )..createSync(recursive: true);
  final nonce = List.generate(
    4,
    (_) => Random.secure().nextInt(1 << 32),
  ).join('-');
  final file = File('${directory.path}/.stage-$nonce')
    ..writeAsStringSync(envelope, flush: true);
  // Version files retain all committed dependencies without overwriting history.
  final destination =
      '${directory.path}/$sceneId-$digest-${metadata['committedMicros']}.json';
  return {
    'stage': file.path,
    'destination': destination,
    'scene': {
      'metadata': metadata,
      'audioPath': finalAudio.audioPath,
      'rawAudioPath': raw?.audioPath,
    },
  };
}

Future<Map<String, dynamic>> _readScenes(Map<String, dynamic> r) async {
  final source = r['sourceId'] as String;
  final directory = Directory(
    '${r['root']}/scenes/${artifactIdentity(source)}${r['exactStart'] == true ? '/${r['word']}' : ''}',
  );
  if (!directory.existsSync()) return {'scenes': <Object>[]};
  final store = AudioArtifactStore(Directory('${r['root']}/artifacts'));
  final selected = <String, Map<String, dynamic>>{};
  var count = 0;
  await for (final entry in directory.list(
    followLinks: false,
    recursive: r['exactStart'] != true,
  )) {
    if (entry is! File || !entry.path.endsWith('.json')) continue;
    if (++count > RenderedSceneRepository.maxScenes * 4) {
      throw const FormatException(
        'Scene version count exceeds bounded enumeration.',
      );
    }
    if (entry.lengthSync() > RenderedSceneRepository.maxMetadataBytes) {
      throw const FormatException('Oversized scene metadata.');
    }
    final envelope = jsonDecode(entry.readAsStringSync()) as Map;
    final m = Map<String, dynamic>.from(envelope['metadata'] as Map);
    if (envelope['checksum'] != artifactIdentity(m) ||
        m['schema'] != 1 ||
        m['sourceId'] != source ||
        m['channels'] != 1 ||
        m['startWordIndex'] is! int ||
        m['endWordIndex'] is! int ||
        (m['startWordIndex'] as int) < 0 ||
        (m['endWordIndex'] as int) <= (m['startWordIndex'] as int) ||
        m['sceneId'] !=
            artifactIdentity([
              'rendered-source-span-v1',
              source,
              m['startWordIndex'],
              m['endWordIndex'],
            ]) ||
        m['dependencyDigest'] != artifactIdentity(m['dependencies']) ||
        m['rawDependencyDigest'] !=
            artifactIdentity((m['dependencies'] as Map)['raw'])) {
      throw const FormatException('Invalid scene metadata identity/checksum.');
    }
    if (r.containsKey('word') &&
        ((r['word'] as int) < (m['startWordIndex'] as int) ||
            (r['word'] as int) >= (m['endWordIndex'] as int))) {
      continue;
    }
    if (r['intent'] != null &&
        artifactIdentity(r['intent']) != artifactIdentity(m['intent'])) {
      continue;
    }
    final id = m['sceneId'] as String;
    final previous = selected[id];
    if (previous == null ||
        (m['committedMicros'] as int) > (previous['committedMicros'] as int)) {
      selected[id] = m;
    }
    if (selected.length > (r['limit'] as int)) {
      throw const FormatException('Scene count exceeds requested limit.');
    }
  }
  final ordered = selected.values.toList()
    ..sort(
      (a, b) =>
          (a['startWordIndex'] as int).compareTo(b['startWordIndex'] as int),
    );
  if (r.containsKey('word') && ordered.length > 1) {
    // A changed scene partition may retain older overlapping history. Select the
    // newest admitted span for point lookup; export rejects ambiguous coverage.
    ordered.sort(
      (a, b) =>
          (b['committedMicros'] as int).compareTo(a['committedMicros'] as int),
    );
    ordered.removeRange(1, ordered.length);
  }
  var previousEnd = -1;
  final result = <Map<String, dynamic>>[];
  for (final m in ordered) {
    if ((m['startWordIndex'] as int) < previousEnd) {
      throw const FormatException('Overlapping stored scene coverage.');
    }
    previousEnd = m['endWordIndex'] as int;
    final audio = store.lookup(m['audioArtifactIdentity'] as String);
    final rawId = m['rawAudioArtifactIdentity'] as String?;
    final raw = rawId == null ? null : store.lookup(rawId);
    if (audio == null ||
        (rawId != null && raw == null) ||
        audio.frames != m['frameCount'] ||
        audio.sampleRate != m['sampleRate']) {
      throw const FormatException('Missing or corrupt stored scene audio.');
    }
    // Validate turn evidence before exposing it to the player/controller.
    for (final t in m['turns'] as List) {
      NativeSpeechTurn.fromMap(Map<String, dynamic>.from(t as Map));
    }
    result.add({
      'metadata': m,
      'audioPath': audio.audioPath,
      'rawAudioPath': raw?.audioPath,
    });
  }
  return {'scenes': result};
}
