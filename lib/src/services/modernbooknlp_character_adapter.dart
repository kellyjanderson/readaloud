import 'dart:convert';
import 'dart:isolate';
import '../models/character_linguistic_evidence.dart';
import '../models/character.dart';
import '../models/character_cast_registry.dart';
import 'character_cast_registry_service.dart';
import 'document_analysis_record.dart';
import 'modernbooknlp_provider.dart';
import 'modernbooknlp_window.dart';

/// Top-level isolate entry keeps the controller's callbacks, completers and
/// cancellation closures out of Dart's closure capture context.
Future<CharacterAnalysisDelta> projectModernBookNlpCharacters(
  ModernBookNlpRequest request,
  Map<String, dynamic> result,
  CharacterCastRegistry registry,
  ModernBookNlpWindow window, {
  bool authoritativeQuotes = false,
}) => Isolate.run(
  () => modernBookNlpCharacterDelta(
    request: request,
    result: result,
    registry: registry,
    turns: window.turns,
    sourceSlices: window.slices,
    authoritativeQuotes: authoritativeQuotes,
    targetSegmentIds: window.targetSegmentIds,
    protectedSpanIds: window.protectedSpanIds,
  ),
);

Future<(CharacterAnalysisDelta, Set<String>)> projectChapterCharacters(
  ModernBookNlpRequest request,
  Map<String, dynamic> result,
  CharacterCastRegistry registry,
  ModernBookNlpWindow window,
) => Isolate.run(() {
  final delta = modernBookNlpCharacterDelta(
    request: request,
    result: result,
    registry: registry,
    turns: window.turns,
    sourceSlices: window.slices,
    authoritativeQuotes: true,
    targetSegmentIds: window.targetSegmentIds,
    protectedSpanIds: window.protectedSpanIds,
  );
  final blockedQuotes = <String>{};
  for (final ref in delta.dialogues) {
    if (ref.quoteAuthority &&
        (window.authoredWords[ref.segmentId]?.any(
              (words) => words.$1 < ref.endWord && ref.startWord < words.$2,
            ) ??
            false)) {
      blockedQuotes.add(ref.dialogueSpanId);
    }
  }
  final speakers = {
    ...window.authoredSpeakers,
    for (final ref in delta.dialogues)
      if (ref.quoteAuthority &&
          ref.castId != null &&
          !blockedQuotes.contains(ref.dialogueSpanId))
        ref.castId!,
  };
  return (delta, speakers);
});

/// An existing dialogue bound to exact preparation coordinates.
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
  bool authoritativeQuotes = false,
  Set<String>? targetSegmentIds,
  Set<String> protectedSpanIds = const {},
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
  final files = result['linguisticArtifacts']?['files'] as Map?;
  final tokens = files == null
      ? const <String, (int, int)>{}
      : _artifactTokens(files, request.text);
  final projected = _entities(result, files, tokens, request.text);
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
  final slicesBySegment = {
    for (final slice in sourceSlices) slice.segment.segmentId: slice,
  };
  final quotedSource = _sourceQuotationContents(request.text);
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
    var explicitGender = const GenderEvidence.empty();
    for (final mention in entity.mentions) {
      if (mention.kind != CharacterObservationKind.proper ||
          quotedSource.any(
            (span) => span.$1 <= mention.start && mention.end <= span.$2,
          )) {
        continue;
      }
      final at = observation(mention);
      final slice = slicesBySegment[at.segmentId];
      if (slice == null) continue;
      explicitGender = explicitGender.merge(
        const CharacterCastRegistryService().explicitIdentityForMention(
          slice.segment,
          at.startUtf16,
          at.text,
        ),
      );
    }
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
              .copyWith(
                explicitGender:
                    (old?.explicitGender ?? const GenderEvidence.empty()).merge(
                      explicitGender,
                    ),
                implicitGender: implicit,
                linguisticEvidence: history,
              ),
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
    if (protectedSpanIds.contains(turn.dialogue.dialogueSpanId)) continue;
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
  if (authoritativeQuotes) {
    references.addAll(
      _projectQuotes(
        request,
        result,
        sourceSlices,
        targetSegmentIds,
        projected,
        _quoteMentions(files, tokens),
        mapped,
        observation,
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

List<CharacterDialogueReference> _projectQuotes(
  ModernBookNlpRequest request,
  Map<String, dynamic> result,
  List<ModernBookNlpSourceSlice> slices,
  Set<String>? targetSegmentIds,
  List<_Entity> entities,
  Map<(int, int), (int, int)> rawMentions,
  Map<String, String?> castByEntity,
  CharacterObservation Function(_Mention) observation,
) {
  if (slices.isEmpty) return const [];
  var previousEnd = 0;
  for (final slice in slices) {
    final text = slice.segment.normalizedText;
    final end = slice.offset + slice.end - slice.start;
    if (slice.start < 0 ||
        slice.end < slice.start ||
        slice.end > text.length ||
        slice.offset < previousEnd ||
        end > request.text.length ||
        text.substring(slice.start, slice.end) !=
            request.text.substring(slice.offset, end)) {
      throw const FormatException('Invalid quote source binding');
    }
    previousEnd = end;
  }
  final entitiesById = {for (final entity in entities) entity.id: entity};
  final sourceQuotations = _sourceQuotationContents(request.text);
  final quotes = <(int, int), Set<String?>>{};
  for (final quote in result['quotes'] as List) {
    final bounds = (quote['startUtf16'] as int, quote['endUtf16'] as int);
    // A provider label by itself cannot move narration to a character voice.
    // Match the complete source quotation, even when token coordinates leave
    // off its surrounding punctuation.
    if (!sourceQuotations.contains(
      _quotationContentBounds(request.text, bounds.$1, bounds.$2),
    )) {
      continue;
    }
    (quotes[bounds] ??= {}).add(quote['entityId'] as String?);
  }
  final locations = quotes.keys.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  var maxPriorEnd = 0;
  final references = <CharacterDialogueReference>[];
  for (var i = 0; i < locations.length; i++) {
    final location = locations[i];
    final (start, end) = location;
    final overlaps =
        start < maxPriorEnd ||
        (i + 1 < locations.length && locations[i + 1].$1 < end);
    if (end > maxPriorEnd) maxPriorEnd = end;
    if (overlaps) continue;
    final parts = _quoteWords(
      request.text,
      start,
      end,
      slices,
      targetSegmentIds,
    );
    if (parts.isEmpty) continue;

    final speakerIds = quotes[location]!;
    final speakerId = speakerIds.length == 1 ? speakerIds.single : null;
    String? castId = castByEntity[speakerId];
    CharacterObservation? speakerMention;
    final mention = rawMentions[location];
    if (castId != null && mention != null) {
      final matching = entitiesById[speakerId]?.mentions.where(
        (m) =>
            m.start == mention.$1 &&
            m.end == mention.$2 &&
            (m.kind == CharacterObservationKind.proper ||
                m.kind == CharacterObservationKind.nominal ||
                m.kind == CharacterObservationKind.pronoun),
      );
      final linked = matching?.firstOrNull;
      if (linked == null || (linked.start < end && start < linked.end)) {
        castId = null;
      } else {
        speakerMention = observation(linked);
      }
    }
    final handoff = _leadingSpeakerAfterApproach(
      request.text,
      start,
      end,
      entities,
      castByEntity,
      currentCastId: castId,
    );
    if (handoff != null) {
      castId = handoff.$1;
      speakerMention = observation(handoff.$2);
    }
    if (handoff == null && i + 1 < locations.length) {
      final resumedSpeaker = _resumedFirstPersonSpeaker(
        request.text,
        location,
        locations[i + 1],
        entitiesById[speakerId],
        quotes[locations[i + 1]]!,
        entitiesById,
      );
      final resumedCast = castByEntity[resumedSpeaker?.$1];
      if (resumedSpeaker != null && resumedCast != null) {
        castId = resumedCast;
        speakerMention = observation(resumedSpeaker.$2);
      }
    }
    final spanId =
        'nlp_quote_${DocumentAnalysisRecord.digest(jsonEncode([
          request.sourceRevision,
          for (final (slice, first, last) in parts) [slice.segment.segmentId, first, last],
        ])).substring(0, 24)}';
    for (final (slice, first, last) in parts) {
      references.add(
        CharacterDialogueReference(
          attributionId: spanId,
          dialogueSpanId: spanId,
          segmentId: slice.segment.segmentId,
          startWord: first,
          endWord: last,
          castId: castId,
          quoteAuthority: true,
          speakerMention: speakerMention,
        ),
      );
    }
  }
  return references;
}

final _nonPunctuation = RegExp(r'[^\p{P}\s]', unicode: true);
final _nonWhitespace = RegExp(r'\S');
final _quotationMark = RegExp('["\'“”‘’«»]');
final _wordBeforeMark = RegExp(r'[\p{L}\p{N}]$', unicode: true);
final _wordAfterMark = RegExp(r'^[\p{L}\p{N}]', unicode: true);
final _invitationToFollow = RegExp(
  r'''^\s*["'“‘«]?\s*(?:come(?=\s+with\s+me\b|\s*[,!.?])|follow\s+me\b|this\s+way\b)''',
  caseSensitive: false,
);
final _paragraphBeforeSpeech = RegExp(r'\n[ \t\r]*\n[ \t\r]*$');
final _paragraphAfterSpeech = RegExp(r'^[ \t\r]*\n[ \t\r]*\n');
final _approachBeforeSpeech = RegExp(
  r'(?:^|[.!?]\s+)([\p{L}]+)\s+[^.!?\n]{0,100}\b'
  r'(?:went|walked|stepped|crossed|hurried|moved)'
  r'(?:\s+(?:down|up|over|back)){0,2}\s+to\s+([\p{L}\p{M}’-]+)[.!]\s*$',
  unicode: true,
  caseSensitive: false,
);
final _followerAfterSpeech = RegExp(
  r'(?:^|[.!?]\s+)([\p{L}\p{M}’-]+)\s+followed\b',
  unicode: true,
  caseSensitive: false,
);

final _firstPersonContinuation = RegExp(
  r'^i\s+(want|need|hope)\b',
  caseSensitive: false,
);
final _waitForBreath = RegExp(
  r'(?:^|[.!?]\s+)([\p{L}\p{M}’-]+)\s+waited for [\p{L}\p{M}’ -]+ to take a breath\.\s*$',
  unicode: true,
  caseSensitive: false,
);
final _reportingVerb = RegExp(
  r'\b(?:said|asked|replied|answered|whispered|shouted|murmured|called|added|continued)\b',
  caseSensitive: false,
);

/// Join first-person continuations within a paragraph when the apparent
/// speaker is the opening subject of the intervening action, and the next
/// quote corroborates a named speaker waiting for the interruption to pass.
(String, _Mention)? _resumedFirstPersonSpeaker(
  String text,
  (int, int) quote,
  (int, int) nextQuote,
  _Entity? apparentSpeaker,
  Set<String?> nextSpeakerIds,
  Map<String, _Entity> entities,
) {
  final (start, end) = quote;
  final (nextStart, nextEnd) = nextQuote;
  if (apparentSpeaker == null ||
      nextSpeakerIds.length != 1 ||
      nextStart < end ||
      nextStart - end > 240) {
    return null;
  }
  final nextSpeaker = entities[nextSpeakerIds.single];
  if (nextSpeaker == null || nextSpeaker.id == apparentSpeaker.id) return null;
  final firstContent = _quotationContentBounds(text, start, end);
  final nextContent = _quotationContentBounds(text, nextStart, nextEnd);
  if (firstContent == null || nextContent == null) return null;
  final opening = _firstPersonContinuation.firstMatch(
    text.substring(firstContent.$1, firstContent.$2),
  );
  if (opening == null ||
      opening[1]!.toLowerCase() !=
          _firstPersonContinuation
              .firstMatch(text.substring(nextContent.$1, nextContent.$2))?[1]
              ?.toLowerCase()) {
    return null;
  }
  final bridge = text.substring(end, nextStart);
  final action = _nonPunctuation.firstMatch(bridge);
  if (RegExp(r'\n[ \t\r]*\n').hasMatch(bridge) ||
      _reportingVerb.hasMatch(bridge) ||
      action == null) {
    return null;
  }
  if (!apparentSpeaker.mentions.any(
    (mention) =>
        mention.kind == CharacterObservationKind.nominal &&
        mention.start == end + action.start,
  )) {
    return null;
  }
  final wait = _waitForBreath.firstMatch(bridge);
  if (wait == null) return null;
  final name = wait[1]!;
  final nameStart = end + wait.start + wait[0]!.indexOf(name);
  final namedMention = nextSpeaker.mentions
      .where(
        (mention) =>
            mention.kind == CharacterObservationKind.proper &&
            mention.start == nameStart &&
            mention.end == nameStart + name.length,
      )
      .firstOrNull;
  return namedMention == null ? null : (nextSpeaker.id, namedMention);
}

/// An invitation between an approach and a follow action belongs to the
/// person approached. Require the same source-linked mover on both sides.
(String, _Mention)? _leadingSpeakerAfterApproach(
  String text,
  int start,
  int end,
  List<_Entity> entities,
  Map<String, String?> castByEntity, {
  required String? currentCastId,
}) {
  if (!_invitationToFollow.hasMatch(text.substring(start, end))) return null;
  final prefixStart = (start - 220).clamp(0, start);
  final prefix = text.substring(prefixStart, start);
  if (!_paragraphBeforeSpeech.hasMatch(prefix)) return null;
  final approach = _approachBeforeSpeech.firstMatch(prefix);
  if (approach == null) return null;
  final suffix = text.substring(end, (end + 200).clamp(end, text.length));
  if (!_paragraphAfterSpeech.hasMatch(suffix)) return null;
  final nextQuote = _quotationMark.firstMatch(suffix);
  final observedAction = suffix.substring(0, nextQuote?.start ?? suffix.length);
  final follow = _followerAfterSpeech.firstMatch(observedAction.trimLeft());
  if (follow == null) return null;

  (String, _Mention)? linkedAt(int offset, String name) {
    final matches = [
      for (final entity in entities)
        for (final mention in entity.mentions)
          if (mention.start == offset &&
              mention.end == offset + name.length &&
              castByEntity[entity.id] != null)
            (castByEntity[entity.id]!, mention),
    ];
    return matches.length == 1 ? matches.single : null;
  }

  final moverName = approach[1]!;
  final recipientName = approach[2]!;
  final qualifier = approach[0]!;
  final mover = linkedAt(
    prefixStart + approach.start + qualifier.indexOf(moverName),
    moverName,
  );
  final recipient = linkedAt(
    prefixStart + approach.start + qualifier.lastIndexOf(recipientName),
    recipientName,
  );
  final followerName = follow[1]!;
  final actionStart =
      end + observedAction.length - observedAction.trimLeft().length;
  final follower = linkedAt(
    actionStart + follow.start + follow[0]!.indexOf(followerName),
    followerName,
  );
  if (mover == null ||
      recipient == null ||
      recipient.$2.kind != CharacterObservationKind.proper ||
      mover.$1 != follower?.$1 ||
      mover.$1 == recipient.$1 ||
      (currentCastId != null &&
          currentCastId != mover.$1 &&
          currentCastId != recipient.$1)) {
    return null;
  }
  return recipient;
}

(int, int)? _quotationContentBounds(String text, int start, int end) {
  final content = _nonPunctuation.allMatches(text.substring(start, end));
  final first = content.firstOrNull;
  return first == null ? null : (start + first.start, start + content.last.end);
}

Set<(int, int)> _sourceQuotationContents(String text) {
  final spans = <(int, int)>{};
  const closing = {'"': '"', "'": "'", '“': '”', '‘': '’', '«': '»'};
  const singles = {"'", '‘', '’'};
  String? expected;
  int? contentStart;
  for (final match in _quotationMark.allMatches(text)) {
    final mark = match.group(0)!;
    final at = match.start;
    if (singles.contains(mark)) {
      final before = text.substring(at > 2 ? at - 2 : 0, at);
      final after = text.substring(at + 1, (at + 3).clamp(0, text.length));
      if (_wordBeforeMark.hasMatch(before) &&
          (_wordAfterMark.hasMatch(after) || expected == null)) {
        continue;
      }
    }
    if (expected == null) {
      expected = closing[mark];
      if (expected != null) contentStart = at + 1;
      continue;
    }
    if (mark != expected) continue;
    // A new paragraph may repeat an opening mark during continued speech.
    var before = at - 1;
    while (before >= 0 && ' \t\r'.contains(text[before])) {
      before--;
    }
    if (before >= 0 && text[before] == '\n' && closing[mark] == mark) {
      continue;
    }
    final span = _quotationContentBounds(text, contentStart!, at);
    if (span != null) spans.add(span);
    expected = null;
    contentStart = null;
  }
  return spans;
}

List<(ModernBookNlpSourceSlice, int, int)> _quoteWords(
  String text,
  int start,
  int end,
  List<ModernBookNlpSourceSlice> slices,
  Set<String>? targetSegmentIds,
) {
  final parts = <(ModernBookNlpSourceSlice, int, int)>[];
  var covered = start;
  for (final slice in slices) {
    final sliceEnd = slice.offset + slice.end - slice.start;
    if (sliceEnd <= start) continue;
    if (slice.offset >= end) break;
    final from = start > slice.offset ? start : slice.offset;
    final to = end < sliceEnd ? end : sliceEnd;
    if (targetSegmentIds?.contains(slice.segment.segmentId) == false ||
        _nonWhitespace.hasMatch(text.substring(covered, from))) {
      return const [];
    }
    covered = to;
    final localStart = from - slice.offset + slice.start;
    final localEnd = to - slice.offset + slice.start;
    final source = slice.segment.normalizedText;
    int? first, last;
    for (final word in slice.segment.wordSpans) {
      if (word.endUtf16 <= localStart) continue;
      if (word.startUtf16 >= localEnd) break;
      final wordStart = word.startUtf16;
      final wordEnd = word.endUtf16;
      final overlap = source.substring(
        wordStart > localStart ? wordStart : localStart,
        wordEnd < localEnd ? wordEnd : localEnd,
      );
      if (!_nonPunctuation.hasMatch(overlap) &&
          _nonPunctuation.hasMatch(word.text)) {
        // A delimiter may share a whitespace token with adjacent narration.
        continue;
      }
      if ((wordStart < localStart &&
              _nonPunctuation.hasMatch(
                source.substring(wordStart, localStart),
              )) ||
          (wordEnd > localEnd &&
              _nonPunctuation.hasMatch(source.substring(localEnd, wordEnd)))) {
        return const [];
      }
      first ??= word.wordIndexWithinSegment;
      last = word.wordIndexWithinSegment + 1;
    }
    if (first != null) parts.add((slice, first, last!));
  }
  if (_nonWhitespace.hasMatch(text.substring(covered, end))) return const [];
  return parts;
}

/// The normalized projection carries the provider's winning speaker edge.
/// Keep its raw mention distinct from the quote and from other named mentions.
Map<(int, int), (int, int)> _quoteMentions(
  Map? files,
  Map<String, (int, int)> tokens,
) {
  if (files == null) return const {};
  final mentions = <(int, int), (int, int)>{};
  for (final quote in _artifactRows(files, 'quotes')) {
    if (quote['mention_start'] == null || quote['mention_end'] == null) {
      continue;
    }
    final first = tokens[quote['quote_start']];
    final last = tokens[quote['quote_end']];
    if (first == null || last == null) {
      throw const FormatException('Invalid raw quote token bounds');
    }
    final mentionStart = tokens[quote['mention_start']];
    final mentionEnd = tokens[quote['mention_end']];
    if (mentionStart != null && mentionEnd != null) {
      mentions[(first.$1, last.$2)] = (mentionStart.$1, mentionEnd.$2);
    }
  }
  return mentions;
}

List<Map<String, String>> _artifactRows(Map files, String name) {
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

Map<String, (int, int)> _artifactTokens(Map files, String text) {
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
  for (final t in _artifactRows(files, 'tokens')) {
    final a = offset(t['byte_onset']), b = offset(t['byte_offset']);
    if (b <= a ||
        text.substring(a, b) != t['word'] ||
        tokens.containsKey(t['token_ID_within_document'])) {
      throw const FormatException('Token/source mismatch');
    }
    tokens[t['token_ID_within_document']!] = (a, b);
  }
  if (tokens.length > 4096) throw const FormatException('Too many tokens');
  return tokens;
}

/// Decode the pinned upstream, unquoted TSV dialect. This is an adapter for
/// supplied artifacts, not another entity/coreference/descriptor extractor.
List<_Entity> _entities(
  Map<String, dynamic> result,
  Map? files,
  Map<String, (int, int)> tokens,
  String text,
) {
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
  final entities = <String, _Entity>{};
  final nonPeople = <String>{}, people = <String>{};
  for (final row in _artifactRows(files, 'entities')) {
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
