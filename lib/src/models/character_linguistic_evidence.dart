/// Bounded projections of immutable book evidence, attached to the one Character
/// aggregate. The complete upstream record remains in the working book/.radoc.
enum CharacterObservationKind {
  proper,
  nominal,
  pronoun,
  agent,
  patient,
  modifier,
  possession,
}

class CharacterObservation {
  const CharacterObservation({
    required this.kind,
    required this.segmentId,
    required this.startUtf16,
    required this.endUtf16,
    required this.text,
  });
  final CharacterObservationKind kind;
  final String segmentId, text;
  final int startUtf16, endUtf16;
  String get anchor => '$segmentId:$startUtf16:$endUtf16';
  Map<String, Object> toJson() => {
    'kind': kind.name,
    'segmentId': segmentId,
    'start': startUtf16,
    'end': endUtf16,
    'text': text,
  };
  factory CharacterObservation.fromJson(Map<String, dynamic> j) {
    if (j['segmentId'] is! String ||
        (j['segmentId'] as String).isEmpty ||
        j['text'] is! String ||
        (j['text'] as String).isEmpty ||
        j['start'] is! int ||
        j['end'] is! int ||
        j['start'] < 0 ||
        j['end'] <= j['start']) {
      throw const FormatException('Invalid character observation');
    }
    return CharacterObservation(
      kind: CharacterObservationKind.values.byName(j['kind']),
      segmentId: j['segmentId'],
      startUtf16: j['start'],
      endUtf16: j['end'],
      text: j['text'],
    );
  }
}

class CharacterLinguisticEvidence {
  CharacterLinguisticEvidence({
    required this.recordKey,
    required this.sourceRevision,
    required this.localEntityId,
    required this.providerVersion,
    required this.modelIdentity,
    required this.adapterVersion,
    required List<CharacterObservation> observations,
    Map<String, double> referentialGender = const {},
  }) : observations = List.unmodifiable(
         observations.length <= 64
             ? observations
             : [
                 ...observations.take(32),
                 ...observations.skip(observations.length - 32),
               ],
       ),
       referentialGender = Map.unmodifiable(referentialGender);
  final String recordKey, sourceRevision, localEntityId;
  final String providerVersion, modelIdentity, adapterVersion;
  final List<CharacterObservation> observations;

  /// Upstream estimates include name priors. Retain them as evidence; only
  /// observed linked pronouns contribute to the automatic voice hint.
  final Map<String, double> referentialGender;
  String get key => '$recordKey/$localEntityId';
  Map<String, Object> toJson() => {
    'recordKey': recordKey,
    'sourceRevision': sourceRevision,
    'localEntityId': localEntityId,
    'providerVersion': providerVersion,
    'modelIdentity': modelIdentity,
    'adapterVersion': adapterVersion,
    'observations': observations.map((o) => o.toJson()).toList(),
    'referentialGender': referentialGender,
  };
  factory CharacterLinguisticEvidence.fromJson(Map<String, dynamic> j) {
    for (final key in [
      'recordKey',
      'sourceRevision',
      'localEntityId',
      'providerVersion',
      'modelIdentity',
      'adapterVersion',
    ]) {
      if (j[key] is! String || (j[key] as String).isEmpty) {
        throw const FormatException('Missing linguistic provenance');
      }
    }
    final estimates = (j['referentialGender'] as Map).map(
      (k, v) => MapEntry(k as String, (v as num).toDouble()),
    );
    if (estimates.values.any((v) => !v.isFinite || v < 0 || v > 1)) {
      throw const FormatException('Invalid referential estimate');
    }
    return CharacterLinguisticEvidence(
      recordKey: j['recordKey'],
      sourceRevision: j['sourceRevision'],
      localEntityId: j['localEntityId'],
      providerVersion: j['providerVersion'],
      modelIdentity: j['modelIdentity'],
      adapterVersion: j['adapterVersion'],
      observations: [
        for (final o in j['observations'])
          CharacterObservation.fromJson(Map<String, dynamic>.from(o)),
      ],
      referentialGender: estimates,
    );
  }
}
