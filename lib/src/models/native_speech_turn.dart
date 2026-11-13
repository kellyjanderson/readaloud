/// One ordered source turn in a bounded native scene. No inferred audio timing.
class NativeSpeechTurn {
  const NativeSpeechTurn({
    required this.voiceId,
    required this.text,
    required this.segmentIds,
    required this.startWord,
    required this.endWord,
    required this.bindingFingerprint,
    required this.bindingRevision,
    this.castId,
    this.routeId,
    this.dialogueSpanId,
    this.directions = const <Map<String, Object?>>[],
  });
  final String voiceId;
  final String text;
  final List<String> segmentIds;
  final int startWord;
  final int endWord;
  final String bindingFingerprint;
  final int bindingRevision;
  final String? castId;
  final String? routeId;
  final String? dialogueSpanId;
  final List<Map<String, Object?>> directions;
  Map<String, Object?> toMap() => {
    'voice': voiceId,
    'text': text,
    'segmentIds': segmentIds,
    'startWord': startWord,
    'endWord': endWord,
    'bindingFingerprint': bindingFingerprint,
    'bindingRevision': bindingRevision,
    'castId': castId,
    'routeId': routeId,
    'dialogueSpanId': dialogueSpanId,
    'directions': directions,
  };
  factory NativeSpeechTurn.fromMap(Map<String, dynamic> m) => NativeSpeechTurn(
    voiceId: m['voice'] as String,
    text: m['text'] as String,
    segmentIds: List<String>.unmodifiable(m['segmentIds'] as List),
    startWord: m['startWord'] as int,
    endWord: m['endWord'] as int,
    bindingFingerprint: m['bindingFingerprint'] as String,
    bindingRevision: m['bindingRevision'] as int,
    castId: m['castId'] as String?,
    routeId: m['routeId'] as String?,
    dialogueSpanId: m['dialogueSpanId'] as String?,
    directions: List.unmodifiable(
      (m['directions'] as List? ?? []).map(
        (v) => Map<String, Object?>.unmodifiable(v as Map),
      ),
    ),
  );
}
