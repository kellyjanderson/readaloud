import 'dart:convert';

/// Relative, portable member identifiers deliberately exclude Unicode/case
/// aliases. They are identifiers, never extraction destinations.
bool isRadocMemberName(String name) =>
    name.length <= 240 &&
    RegExp(r'^[a-z0-9][a-z0-9._/-]*$').hasMatch(name) &&
    name
        .split('/')
        .every(
          (part) =>
              part.isNotEmpty &&
              part != '.' &&
              part != '..' &&
              !part.endsWith('.'),
        );

class RadocAudioMember {
  const RadocAudioMember({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
  });
  final String name;
  final int sizeBytes;
  final String sha256;

  Map<String, dynamic> toJson() => {
    'name': name,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };
  factory RadocAudioMember.fromJson(Map<String, dynamic> json) =>
      RadocAudioMember(
        name: json['name'] as String,
        sizeBytes: json['sizeBytes'] as int,
        sha256: json['sha256'] as String,
      );
}

/// Half-open global source-word coverage of one existing prepared JSON codec.
class RadocPreparedRange {
  const RadocPreparedRange({
    required this.member,
    required this.startWord,
    required this.endWord,
  });
  final String member;
  final int startWord;
  final int endWord;

  Map<String, dynamic> toJson() => {
    'member': member,
    'startWord': startWord,
    'endWord': endWord,
  };
  factory RadocPreparedRange.fromJson(Map<String, dynamic> json) =>
      RadocPreparedRange(
        member: json['member'] as String,
        startWord: json['startWord'] as int,
        endWord: json['endWord'] as int,
      );
}

/// The native scene is the indivisible regeneration unit. Maps preserve the
/// existing engine-independent turn/direction/voice and raw/derivative evidence.
/// Matching dependency digests is policy owned by the playback controller.
class RadocAudioScene {
  RadocAudioScene({
    required this.sceneId,
    required this.startWord,
    required this.endWord,
    required this.audioMember,
    required this.dependencyDigest,
    required Map<String, dynamic> dependencies,
    required Map<String, dynamic> provenance,
    required this.sampleRate,
    required this.channels,
    required this.frameCount,
    this.rawAudioMember,
  }) : dependencies = _freezeMap(dependencies),
       provenance = _freezeMap(provenance);

  final String sceneId;
  final int startWord;
  final int endWord;
  final String audioMember;
  final String? rawAudioMember;
  final String dependencyDigest;
  final Map<String, dynamic> dependencies;
  final Map<String, dynamic> provenance;
  final int sampleRate;
  final int channels;
  final int frameCount;

  Map<String, dynamic> toJson() => {
    'sceneId': sceneId,
    'startWord': startWord,
    'endWord': endWord,
    'audioMember': audioMember,
    if (rawAudioMember != null) 'rawAudioMember': rawAudioMember,
    'dependencyDigest': dependencyDigest,
    'dependencies': dependencies,
    'provenance': provenance,
    'format': {
      'container': 'wav',
      'sampleRate': sampleRate,
      'channels': channels,
      'frameCount': frameCount,
    },
  };
  factory RadocAudioScene.fromJson(Map<String, dynamic> json) {
    final format = json['format'] as Map<String, dynamic>;
    if (format['container'] != 'wav') {
      throw const FormatException('Unsupported radoc audio format.');
    }
    return RadocAudioScene(
      sceneId: json['sceneId'] as String,
      startWord: json['startWord'] as int,
      endWord: json['endWord'] as int,
      audioMember: json['audioMember'] as String,
      rawAudioMember: json['rawAudioMember'] as String?,
      dependencyDigest: json['dependencyDigest'] as String,
      dependencies: json['dependencies'] as Map<String, dynamic>,
      provenance: json['provenance'] as Map<String, dynamic>,
      sampleRate: format['sampleRate'] as int,
      channels: format['channels'] as int,
      frameCount: format['frameCount'] as int,
    );
  }
}

class RadocAudioManifest {
  RadocAudioManifest({
    required this.documentId,
    required this.sourceId,
    required this.preparationComplete,
    required this.totalWords,
    required Iterable<RadocPreparedRange> preparedRanges,
    required Iterable<String> analysisMembers,
    required Iterable<RadocAudioScene> scenes,
    Map<String, dynamic> intent = const {},
    Iterable<RadocAudioMember> members = const [],
  }) : preparedRanges = List.unmodifiable(preparedRanges),
       analysisMembers = List.unmodifiable(analysisMembers),
       scenes = List.unmodifiable(scenes),
       members = List.unmodifiable(members),
       intent = _freezeMap(intent);

  static const schema = 'read-aloud-audio-book';
  static const version = 'radoc-v5';
  static const manifestMember = 'manifest.json';
  final String documentId;
  final String sourceId;
  final bool preparationComplete;

  /// Known source extent, independent of prepared and rendered coverage.
  final int totalWords;
  final List<RadocPreparedRange> preparedRanges;
  final List<String> analysisMembers;
  final List<RadocAudioScene> scenes;
  final Map<String, dynamic> intent;
  final List<RadocAudioMember> members;

  Set<String> get referencedMembers => {
    for (final range in preparedRanges) range.member,
    ...analysisMembers,
    for (final scene in scenes) ...[
      scene.audioMember,
      if (scene.rawAudioMember != null) scene.rawAudioMember!,
    ],
  };

  bool get renderingComplete =>
      preparationComplete &&
      _coversAll(scenes.map((s) => (s.startWord, s.endWord)), totalWords);

  RadocAudioManifest withMembers(Iterable<RadocAudioMember> value) =>
      RadocAudioManifest(
        documentId: documentId,
        sourceId: sourceId,
        preparationComplete: preparationComplete,
        totalWords: totalWords,
        preparedRanges: preparedRanges,
        analysisMembers: analysisMembers,
        scenes: scenes,
        intent: intent,
        members: value,
      );

  /// Validate coverage independently of payload availability. Missing/corrupt
  /// payload bytes are deliberately reported when that member is demanded.
  void validate({bool requireMembers = true}) {
    if (documentId.isEmpty || sourceId.isEmpty || totalWords < 0) {
      throw const FormatException('Missing radoc document/source identity.');
    }
    _orderedCoverage(
      preparedRanges.map((r) => (r.startWord, r.endWord)),
      totalWords,
    );
    _orderedCoverage(scenes.map((s) => (s.startWord, s.endWord)), totalWords);
    if (preparationComplete &&
        !_coversAll(
          preparedRanges.map((r) => (r.startWord, r.endWord)),
          totalWords,
        )) {
      throw const FormatException('Complete preparation has uncovered words.');
    }
    final sceneIds = <String>{};
    for (final scene in scenes) {
      if (scene.sceneId.isEmpty ||
          !sceneIds.add(scene.sceneId) ||
          !_digest.hasMatch(scene.dependencyDigest) ||
          scene.sampleRate < 1 ||
          scene.sampleRate > 384000 ||
          scene.channels < 1 ||
          scene.channels > 8 ||
          scene.frameCount < 1 ||
          !_coversScene(scene, preparedRanges)) {
        throw const FormatException(
          'Invalid radoc scene identity/coverage/format.',
        );
      }
    }
    final refs = referencedMembers;
    if (refs.any(
      (name) => !isRadocMemberName(name) || name == manifestMember,
    )) {
      throw const FormatException('Invalid radoc member reference.');
    }
    if (analysisMembers.toSet().length != analysisMembers.length ||
        preparedRanges.map((r) => r.member).toSet().length !=
            preparedRanges.length) {
      throw const FormatException('Duplicate radoc range/analysis reference.');
    }
    final names = <String>{};
    for (final member in members) {
      if (!isRadocMemberName(member.name) ||
          !names.add(member.name) ||
          member.sizeBytes < 0 ||
          !_digest.hasMatch(member.sha256)) {
        throw const FormatException('Invalid radoc member checksum/size/name.');
      }
    }
    if (requireMembers &&
        (names.length != refs.length || !names.containsAll(refs))) {
      throw const FormatException(
        'Radoc manifest member index differs from references.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'version': version,
    'documentId': documentId,
    'sourceId': sourceId,
    'preparationComplete': preparationComplete,
    'totalWords': totalWords,
    'preparedRanges': preparedRanges.map((r) => r.toJson()).toList(),
    'analysisMembers': analysisMembers,
    'scenes': scenes.map((s) => s.toJson()).toList(),
    'intent': intent,
    'members': members.map((m) => m.toJson()).toList(),
  };

  factory RadocAudioManifest.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != schema || json['version'] != version) {
      throw const FormatException(
        'Unsupported radoc audio-book schema/version.',
      );
    }
    final manifest = RadocAudioManifest(
      documentId: json['documentId'] as String,
      sourceId: json['sourceId'] as String,
      preparationComplete: json['preparationComplete'] as bool,
      totalWords: json['totalWords'] as int,
      preparedRanges: (json['preparedRanges'] as List).map(
        (r) => RadocPreparedRange.fromJson(r as Map<String, dynamic>),
      ),
      analysisMembers: (json['analysisMembers'] as List).cast<String>(),
      scenes: (json['scenes'] as List).map(
        (s) => RadocAudioScene.fromJson(s as Map<String, dynamic>),
      ),
      intent: json['intent'] as Map<String, dynamic>,
      members: (json['members'] as List).map(
        (m) => RadocAudioMember.fromJson(m as Map<String, dynamic>),
      ),
    );
    manifest.validate();
    return manifest;
  }
}

final _digest = RegExp(r'^[0-9a-f]{64}$');

void _orderedCoverage(Iterable<(int, int)> ranges, int total) {
  var end = 0;
  for (final range in ranges) {
    if (range.$1 < end ||
        range.$1 < 0 ||
        range.$2 <= range.$1 ||
        range.$2 > total) {
      throw const FormatException('Unordered/overlapping radoc word coverage.');
    }
    end = range.$2;
  }
}

bool _coversAll(Iterable<(int, int)> ranges, int total) {
  var end = 0;
  for (final range in ranges) {
    if (range.$1 != end) return false;
    end = range.$2;
  }
  return end == total;
}

bool _coversScene(RadocAudioScene scene, List<RadocPreparedRange> ranges) {
  var end = scene.startWord;
  for (final range in ranges) {
    if (range.endWord <= end) continue;
    if (range.startWord > end) return false;
    end = range.endWord;
    if (end >= scene.endWord) return true;
  }
  return false;
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) {
  // JSON round-trip rejects process handles and preserves portable content
  // intent. Freeze recursively so caller mutations cannot change a request.
  dynamic freeze(dynamic item) => switch (item) {
    Map<String, dynamic>() => Map<String, dynamic>.unmodifiable(
      item.map((key, child) => MapEntry(key, freeze(child))),
    ),
    List() => List<dynamic>.unmodifiable(item.map(freeze)),
    _ => item,
  };
  return freeze(jsonDecode(jsonEncode(value))) as Map<String, dynamic>;
}
