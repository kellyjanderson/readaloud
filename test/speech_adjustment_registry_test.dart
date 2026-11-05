import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_adjustment_context.dart';
import 'package:read_aloud/src/services/speech_adjustment_registry.dart';
import 'package:read_aloud/src/services/legacy_pronunciation_context.dart';

void main() {
  test('legacy linguistic IDs do not grant scope to changed payloads', () {
    final record = <String, dynamic>{
      'representationId': 'range2:rule_number_4',
      'representationType': 'normalized_spoken_text',
      'representationValue': 'four',
    };
    expect(
      legacyPronunciationContext(record, 'ruleBasedInference').scope,
      SpeechAdjustmentScope.content,
    );
    record['representationValue'] = 'model-specific-tag';
    expect(
      legacyPronunciationContext(record, 'ruleBasedInference').scope,
      SpeechAdjustmentScope.unresolved,
    );
  });
  const original = SpeechModelContext(
    engineId: 'engine',
    modelId: 'model',
    modelRevision: 'revision',
    capabilityVersion: 'policy',
  );
  for (final domain in SpeechAdjustmentDomain.values) {
    test('${domain.name} requires an exact explicitly permitted context', () {
      final definition = SpeechAdjustmentDefinition(
        id: 'recipe',
        revision: '1',
        domain: domain,
        sourceReference: 'test:decision',
        rationale: 'Scoped test recipe',
        origin: original,
        targets: const [original],
        payloadType: 'control',
        payloadValue: 'value',
      );
      final registry = SpeechAdjustmentRegistry(definitions: [definition]);
      SpeechAdjustmentDecision resolve(
        SpeechModelContext target, {
        SpeechAdjustmentContext context =
            const SpeechAdjustmentContext.engineModel('recipe', '1'),
        String payload = 'value',
      }) => registry.resolve(
        context: context,
        target: target,
        domain: domain,
        payloadType: 'control',
        payloadValue: payload,
      );

      expect(resolve(original).allowed, isTrue);
      for (final wrong in const [
        SpeechModelContext(
          engineId: 'other',
          modelId: 'model',
          modelRevision: 'revision',
          capabilityVersion: 'policy',
        ),
        SpeechModelContext(
          engineId: 'engine',
          modelId: 'other-model',
          modelRevision: 'revision',
          capabilityVersion: 'policy',
        ),
        SpeechModelContext(
          engineId: 'engine',
          modelId: 'model-4bit',
          modelRevision: 'revision',
          capabilityVersion: 'policy',
        ),
        SpeechModelContext(
          engineId: 'engine',
          modelId: 'model',
          modelRevision: 'new',
          capabilityVersion: 'policy',
        ),
        SpeechModelContext(
          engineId: 'engine',
          modelId: 'model',
          modelRevision: 'revision',
          capabilityVersion: 'new',
        ),
        SpeechModelContext(
          engineId: 'engine',
          modelId: '',
          modelRevision: '',
          capabilityVersion: 'policy',
        ),
      ]) {
        expect(resolve(wrong).allowed, isFalse);
        expect(resolve(wrong).reason, 'context_mismatch');
        expect(resolve(wrong).toMap()['origin'], original.toMap());
      }
      expect(
        resolve(
          original,
          context: const SpeechAdjustmentContext.unresolved(),
        ).allowed,
        isFalse,
      );
      expect(
        resolve(
          original,
          context: const SpeechAdjustmentContext.engineModel('recipe', '2'),
        ).allowed,
        isFalse,
      );
      expect(
        resolve(
          original,
          context: const SpeechAdjustmentContext.engineModel('missing', '1'),
        ).allowed,
        isFalse,
      );
      expect(
        resolve(original, payload: 'different').reason,
        'payload_mismatch',
      );
      expect(
        resolve(
          original,
          context: const SpeechAdjustmentContext.content(
            'document:explicit-intent',
          ),
        ).allowed,
        isTrue,
      );
      expect(
        SpeechAdjustmentRegistry(definitions: [definition, definition])
            .resolve(
              context: const SpeechAdjustmentContext.engineModel('recipe', '1'),
              target: original,
              domain: domain,
              payloadType: 'control',
              payloadValue: 'value',
            )
            .allowed,
        isFalse,
      );
    });
  }

  test(
    'context serialization preserves references and rejects ambiguous data',
    () {
      for (final context in const [
        SpeechAdjustmentContext.unresolved(),
        SpeechAdjustmentContext.content('document:intent'),
        SpeechAdjustmentContext.engineModel('adjustment', 'revision'),
      ]) {
        expect(
          SpeechAdjustmentContext.fromMap(context.toMap()).toMap(),
          context.toMap(),
        );
      }
      for (final malformed in <Map<String, Object?>>[
        {},
        {'scope': 'content', 'reference': '', 'revision': ''},
        {'scope': 'engineModel', 'reference': 'id', 'revision': ''},
        {'scope': 'all', 'reference': 'id', 'revision': '1'},
      ]) {
        expect(
          () => SpeechAdjustmentContext.fromMap(malformed),
          throwsFormatException,
        );
      }
    },
  );
}
