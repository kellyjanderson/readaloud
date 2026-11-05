import '../models/character.dart';
import '../models/character_cast_registry.dart';
import '../models/dialogue_attribution.dart';
import '../models/reader_document.dart';
import '../models/speech_annotation.dart';

/// Provider-neutral admission over the existing prepared-document types. The
/// document owns turn evidence; this bounded handoff owns no voices or workers.
class CharacterAnalysisAdapter {
  const CharacterAnalysisAdapter();

  CharacterAnalysisDelta discovery({
    required String workId,
    required String sourceRevision,
    required int analysisRevision,
    required int sequence,
    required CharacterCastRegistry registry,
  }) => CharacterAnalysisDelta(
    workId: workId,
    sourceRevision: sourceRevision,
    analysisRevision: analysisRevision,
    sequence: sequence,
    providerId: 'fast-discovery',
    providerVersion: registry.registryVersion,
    registry: registry,
  );

  CharacterAnalysisDelta refined({
    required String workId,
    required String sourceRevision,
    required int analysisRevision,
    required int sequence,
    required ReaderDocument document,
    String? modelId,
  }) {
    final registry = document.characterCastRegistry;
    final attributions = document.dialogueAttributions;
    final speech = document.speechDocument;
    if (registry.documentId != speech.documentId ||
        attributions.documentId != speech.documentId ||
        document.baseSpeechAnnotations.documentId != speech.documentId) {
      throw const FormatException('Attribution belongs to another document');
    }
    final segments = {for (final s in speech.segments) s.segmentId: s};
    final spans = <String, List<SpeechAnnotation>>{};
    for (final annotation in document.baseSpeechAnnotations.annotations) {
      if (annotation.kind != SpeechAnnotationKind.dialogueSpan) continue;
      final id = annotation.dialogueSpanId!;
      (spans[id] ??= []).add(annotation);
    }
    final entities = <String, Set<String>>{};
    for (final character in registry.characterEntries) {
      for (final id in character.attributionIds) {
        (entities[id] ??= {}).add(
          registry.forCastId(character.castId)?.castId ??
              (throw const FormatException('Missing canonical character')),
        );
      }
    }
    final dialogues = <CharacterDialogueReference>[];
    for (final outcome in attributions.outcomes) {
      final sourceSpans = spans[outcome.dialogueSpanId];
      if (sourceSpans == null || sourceSpans.isEmpty) {
        throw const FormatException('Dialogue has no source span');
      }
      String? castId;
      if (outcome.resolution ==
          DialogueAttributionResolution.attributedSpeaker) {
        final candidates = entities[outcome.attributionId] ?? const <String>{};
        if (candidates.length != 1) {
          throw const FormatException(
            'Dialogue requires one canonical character',
          );
        }
        castId = candidates.single;
      }
      for (final span in sourceSpans) {
        final segment = segments[span.segmentId];
        if (segment == null ||
            span.startWord < 0 ||
            span.endWord <= span.startWord ||
            span.endWord > segment.wordCount) {
          throw const FormatException(
            'Dialogue has invalid source coordinates',
          );
        }
        dialogues.add(
          CharacterDialogueReference(
            attributionId: outcome.attributionId,
            dialogueSpanId: outcome.dialogueSpanId,
            segmentId: span.segmentId,
            startWord: span.startWord,
            endWord: span.endWord,
            castId: castId,
          ),
        );
      }
    }
    if (attributions.outcomes.length != spans.length) {
      throw const FormatException(
        'Dialogue source span has no attribution outcome',
      );
    }
    return CharacterAnalysisDelta(
      workId: workId,
      sourceRevision: sourceRevision,
      analysisRevision: analysisRevision,
      sequence: sequence,
      providerId: attributions.providerId,
      providerVersion: attributions.providerVersion,
      modelId: modelId,
      registry: registry,
      dialogues: List.unmodifiable(dialogues),
    );
  }
}
