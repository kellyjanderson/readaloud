import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/english_pronunciation_profile.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/pronunciation_resource_layering_service.dart';
import 'package:read_aloud/src/services/voice_session_realization_service.dart';

void main() {
  group('VoiceSessionRealizationService', () {
    const resourceLayeringService = PronunciationResourceLayeringService();

    test(
      'realizes a bounded forward window from the requested start segment',
      () {
        final document = DocumentImportService().importPastedText('''
Sentence one. Sentence two. Sentence three. Sentence four.

Sentence five. Sentence six. Sentence seven. Sentence eight.

Sentence nine. Sentence ten. Sentence eleven. Sentence twelve.
''');
        final service = VoiceSessionRealizationService();
        final startSegment = document.speechDocument.segments.first;

        final realization = service.realize(
          VoiceSessionRealizationInput(
            speechDocument: document.speechDocument,
            baseAnnotations: document.baseSpeechAnnotations,
            basePronunciationArtifacts: document.basePronunciationArtifacts,
            startSegmentId: startSegment.segmentId,
            voiceId: 'af_bella',
            engineId: 'kokoro',
            rate: 1.0,
            narrationState: NarrationState.initial(),
          ),
        );

        expect(realization.startSegmentId, startSegment.segmentId);
        expect(realization.ttsArtifactSet.segments, isNotEmpty);
        expect(
          realization.ttsArtifactSet.segments.first.segmentId,
          startSegment.segmentId,
        );
        expect(
          realization.ttsArtifactSet.segments.length,
          lessThan(document.speechDocument.segments.length),
        );
      },
    );

    test('user pronunciation overrides outrank cached document artifacts', () {
      final document = DocumentImportService().importPastedText(
        'Elliot launched 3 missions.',
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;
      final elliotArtifact = document.basePronunciationArtifacts.artifacts
          .firstWhere((artifact) => artifact.normalizedSurfaceText == 'elliot');

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial().copyWith(
            localPronunciationChoices: {elliotArtifact.artifactId: 'EL-ee-uht'},
          ),
        ),
      );

      final realizedArtifact = realization.artifacts.firstWhere(
        (artifact) => artifact.artifactId == elliotArtifact.artifactId,
      );
      expect(realizedArtifact.resolutionClass, 'context_resolved');
      expect(
        realizedArtifact.selectedRepresentation?.representationValue,
        'EL-ee-uht',
      );
    });

    test('for resolves through the app lexicon instead of a context rule', () {
      final document = DocumentImportService().importPastedText(
        'I waited for them.',
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;
      final forBaseArtifact = document.basePronunciationArtifacts.artifacts
          .firstWhere((artifact) => artifact.normalizedSurfaceText == 'for');

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final forArtifact = realization.artifacts.firstWhere(
        (artifact) => artifact.artifactId == forBaseArtifact.artifactId,
      );
      expect(forArtifact.resolutionClass, 'direct_resolved');
      expect(
        forArtifact.selectedRepresentation?.representationType,
        'normalized_spoken_text',
      );
      expect(
        forArtifact.selectedRepresentation?.representationValue,
        'four',
      );
    });

    test('electrocytes resolves through the app lexicon to a direct phoneme', () {
      final document = DocumentImportService().importPastedText(
        'Those are electrocytes.',
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;
      final electrocytesBaseArtifact = document.basePronunciationArtifacts
          .artifacts
          .firstWhere(
            (artifact) => artifact.normalizedSurfaceText == 'electrocytes',
          );

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final electrocytesArtifact = realization.artifacts.firstWhere(
        (artifact) => artifact.artifactId == electrocytesBaseArtifact.artifactId,
      );
      expect(electrocytesArtifact.resolutionClass, 'direct_resolved');
      expect(
        electrocytesArtifact.selectedRepresentation?.representationType,
        'phoneme_string',
      );
      expect(
        electrocytesArtifact.selectedRepresentation?.representationValue,
        'ɪlˈɛktɹəsaɪts',
      );
    });

    test('realizes comma-separated cardinal numbers to spoken text', () {
      final document = DocumentImportService().importPastedText(
        'Love / About 1,000 words.',
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final numberArtifact = realization.artifacts.firstWhere(
        (artifact) => artifact.segmentId == startSegment.segmentId,
        orElse: () =>
            throw StateError('Expected a number pronunciation artifact.'),
      );

      expect(
        numberArtifact.selectedRepresentation?.representationValue,
        'one thousand',
      );
      expect(
        numberArtifact.diagnosticCodes,
        contains('pronunciation.resolved.number_cardinal'),
      );
    });

    test('realizes noun possessives with english s-allomorph behavior', () {
      final document = DocumentImportService().importPastedText(
        "John's hand met Elliot's shoulder.",
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final possessiveArtifacts = realization.artifacts
          .where(
            (artifact) => artifact.diagnosticCodes.contains(
              'pronunciation.resolved.possessive_allomorph',
            ),
          )
          .toList(growable: false);

      expect(
        possessiveArtifacts.map(
          (artifact) => artifact.selectedRepresentation?.representationType,
        ),
        everyElement('explicit_suffix_phoneme'),
      );
      expect(
        possessiveArtifacts.map(
          (artifact) => artifact.selectedRepresentation?.representationValue,
        ),
        everyElement('z'),
      );
    });

    test('realizes common noun possessives while preserving contractions', () {
      final document = DocumentImportService().importPastedText(
        "Someone's jacket brushed the wall, but it's still hanging there.",
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final possessiveArtifacts = realization.artifacts
          .where(
            (artifact) => artifact.diagnosticCodes.contains(
              'pronunciation.resolved.possessive_allomorph',
            ),
          )
          .toList(growable: false);

      expect(
        possessiveArtifacts.map(
          (artifact) => artifact.selectedRepresentation?.representationType,
        ),
        everyElement('explicit_suffix_phoneme'),
      );
      expect(
        possessiveArtifacts.map(
          (artifact) => artifact.selectedRepresentation?.representationValue,
        ),
        contains('z'),
      );
      expect(
        realization.artifacts.any(
          (artifact) =>
              artifact.diagnosticCodes.contains(
                'pronunciation.resolved.possessive_allomorph',
              ) &&
              artifact.selectedRepresentation?.representationValue == 'its',
        ),
        isFalse,
      );
    });

    test('applies the possessive rule generally across noun types', () {
      final document = DocumentImportService().importPastedText(
        "Jenny's hand met the dog's paw near John's shoulder, and its shadow moved.",
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;
      final baseArtifactsById = {
        for (final artifact in document.basePronunciationArtifacts.artifacts)
          artifact.artifactId: artifact,
      };

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final resolvedPossessives = realization.artifacts
          .where(
            (artifact) =>
                baseArtifactsById[artifact.artifactId] != null &&
                artifact.diagnosticCodes.contains(
                  'pronunciation.resolved.possessive_allomorph',
                ),
          )
          .toList(growable: false);

      expect(resolvedPossessives, hasLength(3));
      expect(
        resolvedPossessives.map(
          (artifact) => artifact.selectedRepresentation?.representationValue,
        ),
        everyElement('z'),
      );
      expect(
        realization.artifacts.any(
          (artifact) =>
              baseArtifactsById[artifact.artifactId]?.normalizedSurfaceText ==
                  'it' &&
              artifact.diagnosticCodes.contains(
                'pronunciation.resolved.possessive_allomorph',
              ),
        ),
        isFalse,
      );
    });

    test('realizes english possessive allomorph classes systematically', () {
      final document = DocumentImportService().importPastedText(
        "The cat's toy sat by the bus's wheel near John's desk.",
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final possessiveArtifacts = realization.artifacts
          .where(
            (artifact) => artifact.diagnosticCodes.contains(
              'pronunciation.resolved.possessive_allomorph',
            ),
          )
          .toList(growable: false);

      expect(
        possessiveArtifacts.map(
          (artifact) => artifact.selectedRepresentation?.representationValue,
        ),
        contains('z'),
      );
      expect(
        possessiveArtifacts.map(
          (artifact) => artifact.selectedRepresentation?.representationValue,
        ),
        contains('ɪz'),
      );
    });

    test('realizes explicit suffix phoneme overrides directly', () {
      final document = DocumentImportService().importPastedText(
        "John'|z| hand.",
      );
      final service = VoiceSessionRealizationService();
      final startSegment = document.speechDocument.segments.first;

      final realization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: startSegment.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );

      final explicitArtifact = realization.artifacts.firstWhere(
        (artifact) => artifact.diagnosticCodes.contains(
          'pronunciation.explicit_suffix_override',
        ),
      );

      expect(
        explicitArtifact.selectedRepresentation?.representationType,
        'explicit_suffix_phoneme',
      );
      expect(
        explicitArtifact.selectedRepresentation?.representationValue,
        'z',
      );
    });

    test(
      'preserves the selected pronunciation profile on realization output',
      () {
        final document = DocumentImportService().importPastedText(
          'Elliot said hello.',
        );
        final service = VoiceSessionRealizationService();
        final profile = EnglishPronunciationProfileRegistry.enGbCore;
        final realization = service.realize(
          VoiceSessionRealizationInput(
            speechDocument: document.speechDocument,
            baseAnnotations: document.baseSpeechAnnotations,
            basePronunciationArtifacts: document.basePronunciationArtifacts,
            startSegmentId: document.speechDocument.segments.first.segmentId,
            voiceId: 'bf_emma',
            engineId: 'kokoro',
            rate: 1.0,
            narrationState: NarrationState.initial(),
            selectedProfile: profile,
            mergedPronunciationResources: resourceLayeringService.merge(
              PronunciationResourceLayeringInput(profile: profile),
            ),
          ),
        );

        expect(realization.selectedProfileId, 'en-gb-core');
        expect(realization.ttsArtifactSet.selectedProfileId, 'en-gb-core');
      },
    );

    test(
      'carries realized boundary and emphasis intent into the session envelope',
      () {
        final document = DocumentImportService().importPastedText(
          '"JUST STOP FIGHTING!" she shouted.',
        );
        final service = VoiceSessionRealizationService();

        final realization = service.realize(
          VoiceSessionRealizationInput(
            speechDocument: document.speechDocument,
            baseAnnotations: document.baseSpeechAnnotations,
            basePronunciationArtifacts: document.basePronunciationArtifacts,
            startSegmentId: document.speechDocument.segments.first.segmentId,
            voiceId: 'af_bella',
            engineId: 'kokoro',
            rate: 1.0,
            narrationState: NarrationState.initial(
              recentRate: 1.0,
            ).copyWith(recentEmphasisDensity: 0.2),
          ),
        );

        expect(realization.boundaryIntents, isNotEmpty);
        expect(
          realization.boundaryIntents.any(
            (intent) =>
                intent.sourceKind == 'pause_candidate' &&
                intent.engineTreatment == 'approximated',
          ),
          isTrue,
        );
        expect(realization.emphasisIntents, isNotEmpty);
        expect(
          realization.emphasisIntents.every(
            (intent) => intent.engineTreatment == 'approximated',
          ),
          isTrue,
        );
        expect(
          realization.ttsArtifactSet.segments.first.boundaryIntents,
          isNotEmpty,
        );
        expect(
          realization.ttsArtifactSet.segments.first.emphasisIntents,
          isNotEmpty,
        );
      },
    );

    test('changes realization identity when the selected profile changes', () {
      final document = DocumentImportService().importPastedText(
        'Elliot said hello.',
      );
      final service = VoiceSessionRealizationService();
      final usProfile = EnglishPronunciationProfileRegistry.enUsCore;
      final gbProfile = EnglishPronunciationProfileRegistry.enGbCore;

      final usRealization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
          selectedProfile: usProfile,
          mergedPronunciationResources: resourceLayeringService.merge(
            PronunciationResourceLayeringInput(profile: usProfile),
          ),
        ),
      );
      final gbRealization = service.realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
          selectedProfile: gbProfile,
          mergedPronunciationResources: resourceLayeringService.merge(
            PronunciationResourceLayeringInput(profile: gbProfile),
          ),
        ),
      );

      expect(usRealization.realizationId, isNot(gbRealization.realizationId));
    });

    test(
      'realization identity depends on continuity state, not session id',
      () {
        final document = DocumentImportService().importPastedText(
          'One sentence. Two sentence.',
        );
        final service = VoiceSessionRealizationService();
        final baseState = NarrationState.initial(recentRate: 1.0).copyWith(
          currentSectionMode: 'prose',
          discourseMode: 'narration',
          recentBoundaryClass: BreakClass.paragraph.name,
          continuationPending: true,
          recentEmphasisDensity: 0.3,
          quoteMode: 'narration',
        );

        final firstRealization = service.realize(
          VoiceSessionRealizationInput(
            speechDocument: document.speechDocument,
            baseAnnotations: document.baseSpeechAnnotations,
            basePronunciationArtifacts: document.basePronunciationArtifacts,
            startSegmentId: document.speechDocument.segments.first.segmentId,
            voiceId: 'af_bella',
            engineId: 'kokoro',
            rate: 1.0,
            narrationState: baseState.copyWith(sessionId: 'session-a'),
          ),
        );
        final secondRealization = service.realize(
          VoiceSessionRealizationInput(
            speechDocument: document.speechDocument,
            baseAnnotations: document.baseSpeechAnnotations,
            basePronunciationArtifacts: document.basePronunciationArtifacts,
            startSegmentId: document.speechDocument.segments.first.segmentId,
            voiceId: 'af_bella',
            engineId: 'kokoro',
            rate: 1.0,
            narrationState: baseState.copyWith(sessionId: 'session-b'),
          ),
        );
        final changedContinuityRealization = service.realize(
          VoiceSessionRealizationInput(
            speechDocument: document.speechDocument,
            baseAnnotations: document.baseSpeechAnnotations,
            basePronunciationArtifacts: document.basePronunciationArtifacts,
            startSegmentId: document.speechDocument.segments.first.segmentId,
            voiceId: 'af_bella',
            engineId: 'kokoro',
            rate: 1.0,
            narrationState: baseState.copyWith(
              sessionId: 'session-c',
              recentEmphasisDensity: 0.9,
            ),
          ),
        );

        expect(firstRealization.realizationId, secondRealization.realizationId);
        expect(
          firstRealization.realizationId,
          isNot(changedContinuityRealization.realizationId),
        );
      },
    );
  });
}
