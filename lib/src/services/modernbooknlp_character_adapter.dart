import '../models/character.dart';
import '../models/character_cast_registry.dart';
import 'modernbooknlp_provider.dart';

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
      result['adapterVersion'] != 'readaloud-cpu-1' ||
      result['schema'] != 1 ||
      result['providerId'] != 'modernbooknlp-joint') {
    throw const FormatException('Missing pinned model provenance');
  }
  // Provider-local coreference IDs never become work-wide character IDs. Only
  // unambiguous exact named aliases of already-known characters are admitted.
  final named = <String, Set<String>>{};
  for (final character in registry.characterEntries) {
    for (final name in [character.displayLabel, ...character.observedAliases]) {
      (named[name] ??= {}).add(character.castId);
    }
  }
  final mapped = <String, String?>{};
  for (final entity in result['entities'] as List) {
    final candidates = <String>{};
    for (final mention in entity['mentions'] as List) {
      if (mention['proper'] == true) {
        candidates.addAll(named[mention['text']] ?? {});
      }
    }
    mapped[entity['entityId'] as String] = candidates.length == 1
        ? candidates.single
        : null;
  }
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
    registry: registry,
    dialogues: references,
  );
}
