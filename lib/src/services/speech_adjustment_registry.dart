import '../models/speech_adjustment_context.dart';

const kokoroV1ModelContext = SpeechModelContext(
  engineId: 'kokoro',
  modelId: 'kokoro-v1.0.onnx',
  modelRevision: '1.0',
  capabilityVersion: 'v1',
);

const kokoroForAdjustmentContext = SpeechAdjustmentContext.engineModel(
  'kokoro.for-respelling',
  '1',
);

const fishDrama3ModelContext = SpeechModelContext(
  engineId: 'fish_drama3',
  modelId: 'mlx-community/fish-audio-drama-3-bf16',
  modelRevision: '8c5496f9af370bb9342ab98130b27b5389d1b1cb',
  capabilityVersion: 'v1',
);

/// Engine recipes live here, separately from canonical document intent.
/// A new model, precision, revision or policy gets no inherited permission.
const speechAdjustments = <SpeechAdjustmentDefinition>[
  SpeechAdjustmentDefinition(
    id: 'fish-drama3.whispered',
    revision: '1',
    domain: SpeechAdjustmentDomain.delivery,
    sourceReference:
        'https://github.com/Blaizzy/mlx-audio/blob/v0.6.3/mlx_audio/tts/models/fish_drama3/drama3.py',
    rationale:
        'Lower explicit whole-turn whisper intent to the native inline cue. '
        'Keep acoustic acceptance separate from adapter support.',
    origin: fishDrama3ModelContext,
    targets: [fishDrama3ModelContext],
    payloadType: 'inline_delivery_cue',
    payloadValue: '[whispers]',
  ),
  SpeechAdjustmentDefinition(
    id: 'kokoro.for-respelling',
    revision: '1',
    domain: SpeechAdjustmentDomain.pronunciation,
    sourceReference: 'https://github.com/kellyjanderson/readaloud/issues/120',
    rationale:
        'Retain the legacy Kokoro for/four workaround only in its '
        'original declared model context; perceptual benefit is unqualified.',
    origin: kokoroV1ModelContext,
    targets: [kokoroV1ModelContext],
    payloadType: 'normalized_spoken_text',
    payloadValue: 'four',
  ),
];

class SpeechAdjustmentDecision {
  const SpeechAdjustmentDecision({
    required this.allowed,
    required this.reason,
    required this.context,
    required this.target,
    this.definition,
  });
  final bool allowed;
  final String reason;
  final SpeechAdjustmentContext context;
  final SpeechModelContext target;
  final SpeechAdjustmentDefinition? definition;

  Map<String, Object?> toMap() => {
    'context': context.toMap(),
    'target': target.toMap(),
    'allowed': allowed,
    'reason': reason,
    if (definition != null) 'sourceReference': definition!.sourceReference,
    if (definition != null) 'origin': definition!.origin.toMap(),
  };
}

class SpeechAdjustmentRegistry {
  const SpeechAdjustmentRegistry({this.definitions = speechAdjustments});
  final List<SpeechAdjustmentDefinition> definitions;

  SpeechAdjustmentDecision resolve({
    required SpeechAdjustmentContext context,
    required SpeechModelContext target,
    required SpeechAdjustmentDomain domain,
    required String payloadType,
    required String payloadValue,
  }) {
    SpeechAdjustmentDecision decision(
      String reason, {
      bool allowed = false,
      SpeechAdjustmentDefinition? definition,
    }) => SpeechAdjustmentDecision(
      allowed: allowed,
      reason: reason,
      context: context,
      target: target,
      definition: definition,
    );
    if (context.scope == SpeechAdjustmentScope.content &&
        context.reference.isNotEmpty) {
      return decision('content_intent', allowed: true);
    }
    if (context.scope != SpeechAdjustmentScope.engineModel) {
      return decision('missing_context');
    }
    final matches = definitions
        .where(
          (definition) =>
              definition.id == context.reference &&
              definition.revision == context.revision,
        )
        .toList();
    if (matches.length != 1) return decision('unknown_or_ambiguous_adjustment');
    final definition = matches.single;
    if (definition.sourceReference.isEmpty ||
        definition.rationale.isEmpty ||
        !definition.origin.matches(definition.origin) ||
        definition.targets.isEmpty) {
      return decision('incomplete_definition', definition: definition);
    }
    if (definition.domain != domain ||
        definition.payloadType != payloadType ||
        definition.payloadValue != payloadValue) {
      return decision('payload_mismatch', definition: definition);
    }
    if (!definition.targets.any((candidate) => candidate.matches(target))) {
      return decision('context_mismatch', definition: definition);
    }
    return decision('matched', allowed: true, definition: definition);
  }
}
