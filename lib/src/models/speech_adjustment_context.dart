/// Content intent and engine adaptations have deliberately different scopes.
/// Missing context never grants permission to apply an adaptation.
enum SpeechAdjustmentScope { unresolved, content, engineModel }

enum SpeechAdjustmentDomain {
  pronunciation,
  delivery,
  inflection,
  emphasis,
  boundary,
}

class SpeechAdjustmentContext {
  const SpeechAdjustmentContext.unresolved()
    : scope = SpeechAdjustmentScope.unresolved,
      reference = '',
      revision = '';

  const SpeechAdjustmentContext.content(this.reference)
    : scope = SpeechAdjustmentScope.content,
      revision = '';

  const SpeechAdjustmentContext.engineModel(this.reference, this.revision)
    : scope = SpeechAdjustmentScope.engineModel;

  final SpeechAdjustmentScope scope;
  final String reference;
  final String revision;

  Map<String, Object?> toMap() => {
    'scope': scope.name,
    'reference': reference,
    'revision': revision,
  };

  factory SpeechAdjustmentContext.fromMap(Map<String, Object?> map) {
    final reference = map['reference'];
    final revision = map['revision'];
    if (reference is! String || revision is! String) {
      throw const FormatException('Invalid speech adjustment context');
    }
    return switch (map['scope']) {
      'unresolved' when reference.isEmpty && revision.isEmpty =>
        const SpeechAdjustmentContext.unresolved(),
      'content' when reference.isNotEmpty && revision.isEmpty =>
        SpeechAdjustmentContext.content(reference),
      'engineModel' when reference.isNotEmpty && revision.isNotEmpty =>
        SpeechAdjustmentContext.engineModel(reference, revision),
      _ => throw const FormatException('Invalid speech adjustment scope'),
    };
  }
}

/// An exact policy target. Model variants/revisions never inherit another
/// target's adaptations; additional targets must be listed deliberately.
class SpeechModelContext {
  const SpeechModelContext({
    required this.engineId,
    required this.modelId,
    required this.modelRevision,
    required this.capabilityVersion,
  });
  final String engineId;
  final String modelId;
  final String modelRevision;
  final String capabilityVersion;

  bool matches(SpeechModelContext other) =>
      engineId.isNotEmpty &&
      modelId.isNotEmpty &&
      modelRevision.isNotEmpty &&
      capabilityVersion.isNotEmpty &&
      engineId == other.engineId &&
      modelId == other.modelId &&
      modelRevision == other.modelRevision &&
      capabilityVersion == other.capabilityVersion;

  Map<String, Object?> toMap() => {
    'engineId': engineId,
    'modelId': modelId,
    'modelRevision': modelRevision,
    'capabilityVersion': capabilityVersion,
  };
}

class SpeechAdjustmentDefinition {
  const SpeechAdjustmentDefinition({
    required this.id,
    required this.revision,
    required this.domain,
    required this.sourceReference,
    required this.rationale,
    required this.origin,
    required this.targets,
    required this.payloadType,
    required this.payloadValue,
  });
  final String id;
  final String revision;
  final SpeechAdjustmentDomain domain;
  final String sourceReference;
  final String rationale;
  final SpeechModelContext origin;
  final List<SpeechModelContext> targets;
  final String payloadType;
  final String payloadValue;
}
