import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/base_speech_annotation_inference_service.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/instrumented_document_artifact_codec.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/voice_session_realization_service.dart';

void main() {
  final imported = DocumentImportService().importPastedText('Are you there?');
  final segment = imported.speechDocument.segments.first;
  SpeechAnnotation intent({
    bool delivery = true,
    double confidence = .65,
    SpeechAnnotationSource source =
        SpeechAnnotationSource.explicitSourceMetadata,
    int? end,
  }) => SpeechAnnotation(
    annotationId: delivery ? 'explicit_delivery' : 'explicit_inflection',
    segmentId: segment.segmentId,
    kind: delivery
        ? SpeechAnnotationKind.deliveryIntent
        : SpeechAnnotationKind.inflectionIntent,
    startWord: 0,
    endWord: end ?? segment.wordCount,
    confidence: confidence,
    source: source,
    deliveryIntent: delivery ? DeliveryIntent.whispered : null,
    inflectionIntent: delivery ? null : InflectionIntent.rising,
  );
  BaseSpeechAnnotationSet annotations(List<SpeechAnnotation> intents) =>
      const BaseSpeechAnnotationInferenceService().infer(
        speechDocument: imported.speechDocument,
        displayDocument: imported.displayDocument,
        explicitIntents: intents,
      );
  ReaderDocument document(BaseSpeechAnnotationSet set) =>
      ReaderDocument.fromNormalized(
        title: imported.title,
        type: imported.type,
        normalizedImportResult: imported.normalizedImportResult,
        baseSpeechAnnotations: set,
        dialogueAttributions: imported.dialogueAttributions,
        characterCastRegistry: imported.characterCastRegistry,
        documentVoiceAttribution: imported.documentVoiceAttribution,
        sourceDescription: imported.sourceDescription,
        basePronunciationArtifacts: imported.basePronunciationArtifacts,
      );

  test('prose punctuation and speech tags never invent performance intent', () {
    final prose = DocumentImportService().importPastedText(
      '"WHY?!" Mara whispered angrily.',
    );
    expect(
      prose.baseSpeechAnnotations.annotations.where(
        (a) => a.isPerformanceIntent,
      ),
      isEmpty,
    );
  });

  test(
    'explicit intents preserve independent evidence and finite uncertainty',
    () {
      final set = annotations([
        intent(),
        intent(delivery: false, confidence: .8),
      ]);
      expect(set.annotations.where((a) => a.isPerformanceIntent).length, 2);
      expect(set.annotations.last.confidence, .8);
      expect(intent(source: SpeechAnnotationSource.userOverride).confidence, 1);
      expect(() => intent(confidence: double.nan), throwsArgumentError);
      expect(() => intent(confidence: double.infinity), throwsArgumentError);
      expect(
        () =>
            intent(source: SpeechAnnotationSource.ruleBasedLinguisticInference),
        throwsArgumentError,
      );
      expect(() => intent(end: 0), throwsArgumentError);
      expect(
        () => annotations([intent(end: segment.wordCount + 1)]),
        throwsArgumentError,
      );
      expect(() => annotations([intent(), intent()]), throwsArgumentError);
      expect(
        () => SpeechAnnotation(
          annotationId: 'bad',
          segmentId: segment.segmentId,
          kind: SpeechAnnotationKind.deliveryIntent,
          startWord: 0,
          endWord: 1,
          confidence: .5,
          source: SpeechAnnotationSource.explicitSourceMetadata,
          inflectionIntent: InflectionIntent.falling,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'v2 round trip preserves both intents, v1 stays unchanged, snapshot is frozen',
    () {
      const codec = InstrumentedDocumentArtifactCodec();
      final doc = document(annotations([intent(), intent(delivery: false)]));
      final assignments = doc.characterCastRegistry.entries
          .map(
            (entry) => CastVoiceAssignment(
              castId: entry.castId,
              effectiveVoiceId: 'af_bella',
              decisionKind: VoiceAssignmentDecisionKind.automatic,
              automaticVoiceId: 'af_bella',
            ),
          )
          .toList();

      final envelope =
          jsonDecode(
                codec.encode(
                  document: doc,
                  documentRevision: 1,
                  castVoiceAssignments: CastVoiceAssignmentSet(
                    documentId: doc.normalizedImportResult.documentId,
                    assignmentVersion: 'test',
                    assignments: assignments,
                  ),
                  preparedVoiceReferences: assignments
                      .map(
                        (assignment) => ResolvedPreparedVoiceReference(
                          assignment: assignment,
                          documentRevision: 1,
                          resource: PreparedVoiceBinding(
                            voiceId: 'af_bella',
                            voiceDigest: 'voice',
                            modelDigest: 'model',
                            engineVersion: 'kokoro',
                            pronunciationProfileId: 'en-us-core',
                            bindingRevision: 1,
                            documentId: doc.normalizedImportResult.documentId,
                          ),
                        ),
                      )
                      .toList(),
                ),
              )
              as Map<String, dynamic>;

      final encoded = jsonEncode(envelope);
      final snapshot = codec.decode(encoded);
      expect(jsonDecode(codec.reencode(snapshot)), envelope);
      final prepared = snapshot.data['preparedDocument'] as Map;
      final raw =
          (prepared['baseSpeechAnnotations'] as Map)['annotations'] as List;
      final performance = raw
          .where(
            (a) => a['deliveryIntent'] != null || a['inflectionIntent'] != null,
          )
          .toList();
      expect(performance.length, 2);
      expect(performance.first['deliveryIntent'], 'whispered');
      expect(performance.last['inflectionIntent'], 'rising');
      expect(performance.first['confidence'], .65);
      expect(performance.first['source'], 'explicitSourceMetadata');
      expect(
        () => performance.first['confidence'] = .9,
        throwsUnsupportedError,
      );
      expect(() => raw.add({}), throwsUnsupportedError);
      expect(
        const ReaderDocumentSerializationService().serializeToJsonString(doc),
        const ReaderDocumentSerializationService().serializeToJsonString(
          imported,
        ),
      );
      for (final invalid in <Map<String, Object?>>[
        {'source': 'ruleBasedLinguisticInference'},
        {'confidence': 1.1},
        {'startWord': -1},
        {'endWord': 999},
        {'segmentId': 'missing'},
        {'inflectionIntent': 'rising'},
      ]) {
        final changed = jsonDecode(encoded) as Map<String, dynamic>;
        final list =
            changed['preparedDocument']['baseSpeechAnnotations']['annotations']
                as List;
        (list.firstWhere((a) => a['kind'] == 'deliveryIntent') as Map).addAll(
          invalid,
        );
        expect(() => codec.decode(jsonEncode(changed)), throwsFormatException);
      }
      for (final invalid in ['invented', '', null]) {
        final changed = jsonDecode(encoded) as Map<String, dynamic>;
        final list =
            changed['preparedDocument']['baseSpeechAnnotations']['annotations']
                as List;
        (list.firstWhere((a) => a['kind'] == 'deliveryIntent')
                as Map)['deliveryIntent'] =
            invalid;
        expect(() => codec.decode(jsonEncode(changed)), throwsFormatException);
      }
    },
  );

  test(
    'realization retains both requests with explicit unsupported fallback',
    () {
      VoiceSessionRealization realize(
        BaseSpeechAnnotationSet set, {
        String engine = 'kokoro',
      }) => const VoiceSessionRealizationService().realize(
        VoiceSessionRealizationInput(
          speechDocument: imported.speechDocument,
          baseAnnotations: set,
          basePronunciationArtifacts: imported.basePronunciationArtifacts,
          startSegmentId: segment.segmentId,
          voiceId: 'af_bella',
          engineId: engine,
          rate: 1,
          narrationState: NarrationState.initial(),
        ),
      );
      final set = annotations([intent(), intent(delivery: false)]);
      final result = realize(set);
      expect(result.performanceIntents.length, 2);
      for (final realized in result.performanceIntents) {
        expect(realized.engineTreatment, 'unsupported');
        expect(realized.fallback, 'engine_default');
        expect(realized.annotation.confidence, .65);
      }
      expect(
        result.ttsArtifactSet.segments.first.speakText,
        segment.normalizedText,
      );
      expect(result.ttsArtifactSet.segments.first.performanceIntents.length, 2);
      expect(
        result.ttsArtifactSet.segments.first.diagnosticCodes,
        contains('deliveryIntent.unsupported'),
      );
      expect(
        realize(
          set,
          engine: 'unknown',
        ).performanceIntents.first.engineTreatment,
        'unsupported',
      );
      expect(realize(annotations([])).performanceIntents, isEmpty);
      expect(
        realize(annotations([intent(confidence: .4)])).realizationId,
        isNot(result.realizationId),
      );
      expect(() => result.performanceIntents.clear(), throwsUnsupportedError);
    },
  );
}
