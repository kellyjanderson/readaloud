import '../models/character.dart';
import '../models/character_cast_registry.dart';
import '../models/voice_profile.dart';

/// Shared by durable work records and radoc; legacy entries remain readable.
Map<String, Object?> encodeCharacter(CastEntry e) => {
  'castId': e.castId,
  'roleKind': e.roleKind.name,
  'displayLabel': e.displayLabel,
  'confidence': e.confidence,
  'provenance': e.provenance.name,
  'observedAliases': e.observedAliases,
  'attributionIds': e.attributionIds,
  'characterState': e.characterState.toJson(),
  'identityProfile': e.identityProfile == null
      ? null
      : {
          'genderIdentityLabel': _snake(
            e.identityProfile!.genderIdentityLabel.name,
          ),
          'genderConfidence': e.identityProfile!.genderConfidence,
          'genderSource': _snake(e.identityProfile!.genderSource.name),
          'pronounProfile': {
            'counts': e.identityProfile!.pronounProfile.counts,
          },
          'conflictFlag': e.identityProfile!.conflictFlag,
          'countedSegmentIds': e.identityProfile!.countedSegmentIds,
          'evidenceSpans': e.identityProfile!.evidenceSpans
              .map(
                (s) => {
                  'segmentId': s.segmentId,
                  'startUtf16': s.startUtf16,
                  'endUtf16': s.endUtf16,
                  'text': s.text,
                  'source': _snake(s.source.name),
                  'genderIdentityLabel': s.genderIdentityLabel == null
                      ? null
                      : _snake(s.genderIdentityLabel!.name),
                },
              )
              .toList(),
        },
  'inferredGender': e.inferredGender?.name,
  'inferredGenderConfidence': e.inferredGenderConfidence,
};

String _snake(String s) =>
    s.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
String _camel(String s) =>
    s.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
CastEntry decodeCharacter(Map<String, dynamic> x) {
  final p = x['identityProfile'] as Map?;
  return CastEntry(
    castId: x['castId'],
    roleKind: CastEntryRoleKind.values.byName(x['roleKind']),
    displayLabel: x['displayLabel'],
    confidence: (x['confidence'] as num).toDouble(),
    provenance: CastEntryProvenance.values.byName(x['provenance']),
    observedAliases: List<String>.from(x['observedAliases']),
    attributionIds: List<String>.from(x['attributionIds']),
    characterState: x['characterState'] == null
        ? null
        : CharacterState.fromJson(
            Map<String, dynamic>.from(x['characterState']),
          ),
    inferredGender: x['inferredGender'] == null
        ? null
        : VoiceGender.values.byName(x['inferredGender']),
    inferredGenderConfidence: (x['inferredGenderConfidence'] as num?)
        ?.toDouble(),
    identityProfile: p == null
        ? null
        : CharacterIdentityProfile(
            genderIdentityLabel: CharacterGenderIdentityLabel.values.byName(
              _camel(p['genderIdentityLabel']),
            ),
            genderConfidence: (p['genderConfidence'] as num).toDouble(),
            genderSource: CharacterGenderEvidenceSource.values.byName(
              _camel(p['genderSource']),
            ),
            pronounProfile: CharacterPronounProfile(
              counts: Map<String, int>.from(p['pronounProfile']['counts']),
            ),
            conflictFlag: p['conflictFlag'],
            countedSegmentIds: List<String>.from(p['countedSegmentIds'] ?? []),
            evidenceSpans: (p['evidenceSpans'] as List)
                .map(
                  (s) => CharacterIdentityEvidenceSpan(
                    segmentId: s['segmentId'],
                    startUtf16: s['startUtf16'],
                    endUtf16: s['endUtf16'],
                    text: s['text'],
                    source: CharacterGenderEvidenceSource.values.byName(
                      _camel(s['source'] ?? 'unknown'),
                    ),
                    genderIdentityLabel: s['genderIdentityLabel'] == null
                        ? null
                        : CharacterGenderIdentityLabel.values.byName(
                            _camel(s['genderIdentityLabel']),
                          ),
                  ),
                )
                .toList(),
          ),
  );
}
