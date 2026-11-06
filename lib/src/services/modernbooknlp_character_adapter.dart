import 'dart:convert';
import 'dart:isolate';
import '../models/character_linguistic_evidence.dart';
import '../models/character.dart';
import '../models/character_cast_registry.dart';
import 'document_analysis_record.dart';
import 'modernbooknlp_provider.dart';
import 'modernbooknlp_window.dart';

/// Top-level isolate entry keeps the controller's callbacks, completers and
/// cancellation closures out of Dart's closure capture context.
Future<CharacterAnalysisDelta> projectModernBookNlpCharacters(
  ModernBookNlpRequest request,
  Map<String, dynamic> result,
  CharacterCastRegistry registry,
  ModernBookNlpWindow window,
) => Isolate.run(
  () => modernBookNlpCharacterDelta(
    request: request,
    result: result,
    registry: registry,
    turns: window.turns,
    sourceSlices: window.slices,
  ),
);

/// Exact coordinate bindings supplied by the preparation owner. This adapter
/// neither finds nor rewrites dialogue boundaries. A mismatched boundary remains
/// unknown for evaluation rather than being guessed into a different turn.
class ModernBookNlpTurnBinding {
  const ModernBookNlpTurnBinding({
    required this.startUtf16,
    required this.endUtf16,
    required this.dialogue,
  });
  final int startUtf16, endUtf16;
  final CharacterDialogueReference dialogue;
}

CharacterAnalysisDelta modernBookNlpCharacterDelta({
  required ModernBookNlpRequest request,
  required Map<String, dynamic> result,
  required CharacterCastRegistry registry,
  required List<ModernBookNlpTurnBinding> turns,
  List<ModernBookNlpSourceSlice> sourceSlices = const [],
}) {
  validateModernBookNlpResult(result, request.text);
  for (final key in [
    'requestId',
    'ownerId',
    'workId',
    'sourceRevision',
    'analysisRevision',
    'sequence',
  ]) {
    if (result[key] != request.toJson()[key]) {
      throw FormatException('Stale provider $key');
    }
  }
  if (result['providerVersion'] != modernBookNlpRevision ||
      result['modelIdentity'] != modernBookNlpModelIdentity ||
      result['adapterVersion'] != modernBookNlpAdapterVersion ||
      result['schema'] != 1 ||
      result['providerId'] != 'modernbooknlp-joint') {
    throw const FormatException('Missing pinned model provenance');
  }
  // Provider-local IDs are scoped to this immutable record. Overlap anchors and
  // unambiguous aliases link windows; collisions never pick the first character.
  final recordKey = DocumentAnalysisRecord.requestKey(request);
  final projected = _entities(result, request.text);
  bool isMention(CharacterObservationKind k) =>
      k == CharacterObservationKind.proper ||
      k == CharacterObservationKind.nominal ||
      k == CharacterObservationKind.pronoun;
  final localNames = <String, Set<String>>{};
  for (final e in projected) {
    for (final m in e.mentions.where(
      (m) => m.kind == CharacterObservationKind.proper,
    )) {
      (localNames[request.text.substring(m.start, m.end).toLowerCase()] ??= {})
          .add(e.id);
    }
  }
  final named = <String, Set<String>>{};
  final correctedAliases = <String, Set<String>>{};
  final anchors = <String, Set<String>>{};
  for (final character in registry.characterEntries) {
    for (final correction
        in character.characterState.aliasCorrections.entries.where(
          (e) => e.value,
        )) {
      (correctedAliases[correction.key] ??= {}).add(character.castId);
    }
    for (final name in [
      character.displayLabel,
      ...character.observedAliases,
      ...character.characterState.aliasCorrections.entries
          .where((e) => e.value)
          .map((e) => e.key),
    ]) {
      final key = name.trim().toLowerCase();
      if (character.characterState.aliasCorrections[key] == false) continue;
      (named[key] ??= {}).add(character.castId);
    }
    for (final evidence in character.characterState.linguisticEvidence) {
      if (evidence.sourceRevision != request.sourceRevision) continue;
      for (final o in evidence.observations.where(
        (o) =>
            o.kind == CharacterObservationKind.proper ||
            o.kind == CharacterObservationKind.nominal ||
            o.kind == CharacterObservationKind.pronoun,
      )) {
        if (o.kind == CharacterObservationKind.proper &&
            character.characterState.aliasCorrections[o.text.toLowerCase()] ==
                false) {
          continue;
        }
        (anchors[o.anchor] ??= {}).add(character.castId);
      }
    }
  }
  CharacterObservation observation(_Mention m) {
    final slice = sourceSlices
        .where(
          (s) => m.start >= s.offset && m.end <= s.offset + s.end - s.start,
        )
        .firstOrNull;
    return CharacterObservation(
      kind: m.kind,
      segmentId: slice?.segment.segmentId ?? 'analysis:$recordKey',
      startUtf16: slice == null
          ? m.start
          : m.start - slice.offset + slice.start,
      endUtf16: slice == null ? m.end : m.end - slice.offset + slice.start,
      text: request.text.substring(m.start, m.end),
    );
  }

  final mapped = <String, String?>{};
  final entries = {for (final e in registry.entries) e.castId: e};
  for (final entity in projected) {
    final candidates = <String>{};
    final observations = entity.mentions.map(observation).toList();
    final proper = observations
        .where((o) => o.kind == CharacterObservationKind.proper)
        .toList();
    final nominal = observations
        .where((o) => o.kind == CharacterObservationKind.nominal)
        .toList();
    for (final mention in observations) {
      if (!isMention(mention.kind)) continue;
      candidates.addAll(anchors[mention.anchor] ?? {});
      if (mention.kind == CharacterObservationKind.proper) {
        final alias = mention.text.trim().toLowerCase();
        if ((localNames[alias]?.length ?? 0) <= 1) {
          candidates.addAll(named[alias] ?? {});
        }
      }
    }
    final explicit = <String>{
      for (final o in proper) ...?correctedAliases[o.text.toLowerCase()],
    };
    final rejected = candidates
        .where(
          (id) => proper.any(
            (o) =>
                entries[id]?.characterState.aliasCorrections[o.text
                    .toLowerCase()] ==
                false,
          ),
        )
        .toSet();
    if (explicit.isNotEmpty) {
      candidates
        ..clear()
        ..addAll(explicit);
    } else if (rejected.isNotEmpty) {
      candidates.removeAll(rejected);
      if (candidates.isEmpty) {
        mapped[entity.id] = null;
        continue;
      }
    }
    // Pronoun-only clusters and disputed associations stay unknown. A lone
    // proper/nominal mention is sufficient; .book's frequency filter is not.
    if (candidates.length > 1 ||
        (candidates.isEmpty && proper.isEmpty && nominal.isEmpty)) {
      mapped[entity.id] = null;
      continue;
    }
    final first = proper.firstOrNull ?? nominal.firstOrNull;
    final id =
        candidates.firstOrNull ??
        'cast_nlp_${DocumentAnalysisRecord.digest('${request.workId}/${request.sourceRevision}/${first!.anchor}').substring(0, 24)}';
    final old = entries[id];
    if (proper.any(
      (o) =>
          old?.characterState.aliasCorrections[o.text.toLowerCase()] == false,
    )) {
      mapped[entity.id] = null;
      continue;
    }
    final aliases = {
      ...?old?.observedAliases,
      for (final o in proper)
        if (old?.characterState.aliasCorrections[o.text.toLowerCase()] != false)
          o.text,
    };
    final evidence = CharacterLinguisticEvidence(
      recordKey: recordKey,
      sourceRevision: request.sourceRevision,
      localEntityId: entity.id,
      providerVersion: modernBookNlpRevision,
      modelIdentity: modernBookNlpModelIdentity,
      adapterVersion: modernBookNlpAdapterVersion,
      observations: observations,
      referentialGender: entity.gender,
    );
    final history = <String, CharacterLinguisticEvidence>{
      for (final e
          in old?.characterState.linguisticEvidence ??
              <CharacterLinguisticEvidence>[])
        e.key: e,
      evidence.key: evidence,
    }.values.toList();
    final pronouns = <String, CharacterObservation>{};
    for (final e in history.where(
      (e) => e.sourceRevision == request.sourceRevision,
    )) {
      for (final o in e.observations.where(
        (o) => o.kind == CharacterObservationKind.pronoun,
      )) {
        pronouns[o.anchor] = o;
      }
    }
    final counts = <String, int>{};
    for (final o in pronouns.values) {
      counts.update(o.text.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
    }
    final female = [
      'she',
      'her',
      'hers',
    ].fold(0, (n, p) => n + (counts[p] ?? 0));
    final male = ['he', 'him', 'his'].fold(0, (n, p) => n + (counts[p] ?? 0));
    final gender = female > 0 && male == 0
        ? CharacterGenderIdentityLabel.female
        : male > 0 && female == 0
        ? CharacterGenderIdentityLabel.male
        : CharacterGenderIdentityLabel.unknown;
    final spans = [
      for (final o in pronouns.values)
        CharacterIdentityEvidenceSpan(
          segmentId: o.segmentId,
          startUtf16: o.startUtf16,
          endUtf16: o.endUtf16,
          text: o.text,
          source: CharacterGenderEvidenceSource.pronoun,
          genderIdentityLabel:
              ['she', 'her', 'hers'].contains(o.text.toLowerCase())
              ? CharacterGenderIdentityLabel.female
              : ['he', 'him', 'his'].contains(o.text.toLowerCase())
              ? CharacterGenderIdentityLabel.male
              : null,
        ),
    ];
    final implicit = GenderEvidence(
      value: gender,
      conflict: female > 0 && male > 0,
      observations: spans,
    );
    final profile = CharacterIdentityProfile(
      genderIdentityLabel: gender,
      // Evidence agreement, not calibrated model probability.
      genderConfidence: gender == CharacterGenderIdentityLabel.unknown ? 0 : 1,
      genderSource: CharacterGenderEvidenceSource.pronoun,
      pronounProfile: CharacterPronounProfile(counts: counts),
      conflictFlag: implicit.conflict,
      evidenceSpans: spans,
    );
    entries[id] = CastEntry(
      castId: id,
      roleKind: CastEntryRoleKind.character,
      displayLabel: old?.displayLabel ?? first!.text,
      confidence: old?.confidence ?? 0,
      provenance: CastEntryProvenance.providerOutput,
      observedAliases: aliases.toList(),
      attributionIds: old?.attributionIds ?? [],
      identityProfile: profile,
      characterState:
          (old?.characterState ?? CharacterState(workId: request.workId))
              .copyWith(implicitGender: implicit, linguisticEvidence: history),
    );
    mapped[entity.id] = id;
  }
  final reconciled = CharacterCastRegistry(
    documentId: registry.documentId,
    registryVersion: 'modernbooknlp-character-v1',
    entries: entries.values.toList(),
    castIdRedirects: registry.castIdRedirects,
  );
  final references = <CharacterDialogueReference>[];
  for (final turn in turns) {
    if (turn.startUtf16 < 0 ||
        turn.endUtf16 <= turn.startUtf16 ||
        turn.endUtf16 > request.text.length) {
      throw const FormatException('Turn binding outside window');
    }
    final matching = (result['quotes'] as List)
        .where(
          (q) =>
              q['startUtf16'] == turn.startUtf16 &&
              q['endUtf16'] == turn.endUtf16,
        )
        .toList();
    final old = turn.dialogue;
    references.add(
      CharacterDialogueReference(
        attributionId: old.attributionId,
        dialogueSpanId: old.dialogueSpanId,
        segmentId: old.segmentId,
        startWord: old.startWord,
        endWord: old.endWord,
        castId: matching.length == 1
            ? mapped[matching.single['entityId']]
            : null,
        sourceMatched: matching.length == 1,
      ),
    );
  }
  return CharacterAnalysisDelta(
    workId: request.workId,
    sourceRevision: request.sourceRevision,
    analysisRevision: request.analysisRevision,
    sequence: request.sequence,
    providerId: 'modernbooknlp-joint',
    providerVersion: modernBookNlpRevision,
    modelId: result['modelIdentity'] as String,
    registry: reconciled,
    dialogues: references,
  );
}

class _Mention {
  const _Mention(this.start, this.end, this.kind);
  final int start, end;
  final CharacterObservationKind kind;
}

class _Entity {
  _Entity(this.id);
  final String id;
  final List<_Mention> mentions = [];
  final Map<String, double> gender = {};
}

/// Decode the pinned upstream, unquoted TSV dialect. This is an adapter for
/// supplied artifacts, not another entity/coreference/descriptor extractor.
List<_Entity> _entities(Map<String, dynamic> result, String text) {
  final files = result['linguisticArtifacts']?['files'] as Map?;
  if (files == null) {
    return [
      for (final e in result['entities'] as List)
        _Entity(e['entityId'])
          ..mentions.addAll([
            for (final m in e['mentions'])
              _Mention(
                m['startUtf16'],
                m['endUtf16'],
                m['proper'] == true
                    ? CharacterObservationKind.proper
                    : CharacterObservationKind.pronoun,
              ),
          ]),
    ];
  }
  List<Map<String, String>> rows(String name) {
    final lines = const LineSplitter().convert(files[name] as String);
    if (lines.isEmpty) throw FormatException('Missing $name header');
    final header = lines.first.split('\t');
    return [
      for (final line in lines.skip(1).where((s) => s.isNotEmpty))
        (() {
          final cells = line.split('\t');
          if (cells.length != header.length) {
            throw FormatException('Malformed $name row');
          }
          return Map<String, String>.fromIterables(header, cells);
        })(),
    ];
  }

  final offsets = <int>[0];
  for (final rune in text.runes) {
    offsets.add(offsets.last + (rune > 0xffff ? 2 : 1));
  }
  int offset(String? raw) {
    final n = int.tryParse(raw ?? '');
    if (n == null || n < 0 || n >= offsets.length) {
      throw const FormatException('Invalid token offset');
    }
    return offsets[n];
  }

  final tokens = <String, (int, int)>{};
  for (final t in rows('tokens')) {
    final a = offset(t['byte_onset']), b = offset(t['byte_offset']);
    if (b <= a ||
        text.substring(a, b) != t['word'] ||
        tokens.containsKey(t['token_ID_within_document'])) {
      throw const FormatException('Token/source mismatch');
    }
    tokens[t['token_ID_within_document']!] = (a, b);
  }
  if (tokens.length > 4096) throw const FormatException('Too many tokens');
  final entities = <String, _Entity>{};
  final nonPeople = <String>{}, people = <String>{};
  for (final row in rows('entities')) {
    final id = row['COREF']!;
    if (row['prop'] != 'PRON') {
      (row['cat'] == 'PER' ? people : nonPeople).add(id);
    }
    if (row['cat'] != 'PER') continue;
    final a = tokens[row['start_token']], b = tokens[row['end_token']];
    if (a == null ||
        b == null ||
        b.$2 <= a.$1 ||
        text.substring(a.$1, b.$2).replaceAll(RegExp(r'\s+'), '') !=
            row['text']?.replaceAll(RegExp(r'\s+'), '')) {
      throw const FormatException('Entity/source mismatch');
    }
    final key = id == '-1' ? '-1:${a.$1}' : id;
    (entities[key] ??= _Entity(key)).mentions.add(
      _Mention(a.$1, b.$2, switch (row['prop']) {
        'PROP' => CharacterObservationKind.proper,
        'NOM' => CharacterObservationKind.nominal,
        'PRON' => CharacterObservationKind.pronoun,
        _ => throw const FormatException('Invalid mention kind'),
      }),
    );
  }
  for (final id in nonPeople.difference(people)) {
    entities.remove(id);
  }
  for (final raw in jsonDecode(files['book'] as String)['characters'] as List) {
    final e = entities['${raw['id']}'];
    if (e == null) continue;
    final g = raw['g'];
    if (g is Map && g['inference'] is Map) {
      for (final entry in (g['inference'] as Map).entries) {
        final v = (entry.value as num).toDouble();
        if (!v.isFinite || v < 0 || v > 1) {
          throw const FormatException('Invalid gender estimate');
        }
        e.gender[entry.key as String] = v;
      }
    }
    for (final entry in {
      'agent': CharacterObservationKind.agent,
      'patient': CharacterObservationKind.patient,
      'mod': CharacterObservationKind.modifier,
      'poss': CharacterObservationKind.possession,
    }.entries) {
      for (final item in raw[entry.key] ?? const []) {
        final token = tokens['${item['i']}'];
        if (token == null) throw const FormatException('Invalid syntax token');
        e.mentions.add(_Mention(token.$1, token.$2, entry.value));
      }
    }
  }
  return entities.values.toList();
}
