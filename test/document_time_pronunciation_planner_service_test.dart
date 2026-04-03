import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/english_pronunciation_profile.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/document_time_pronunciation_planner_service.dart';
import 'package:read_aloud/src/services/english_suffix_allomorph_module.dart';
import 'package:read_aloud/src/services/pronunciation_resource_layering_service.dart';

void main() {
  test('document-time planner scopes artifacts to the selected profile', () {
    final document = DocumentImportService().importPastedText(
      "John's API stayed visible.",
    );
    final profile = EnglishPronunciationProfileRegistry.enGbCore;
    final mergedResources = const PronunciationResourceLayeringService().merge(
      PronunciationResourceLayeringInput(profile: profile),
    );

    final replanned = const DocumentTimePronunciationPlannerService().plan(
      DocumentTimePronunciationPlannerInput(
        speechDocument: document.speechDocument,
        baseAnnotations: document.baseSpeechAnnotations,
        positionMap: document.positionMap,
        normalizationVersion: document.speechDocument.normalizationVersion,
        selectedProfile: profile,
        mergedPronunciationResources: mergedResources,
        enabledDocumentTimeRuleModules: const <EnglishSuffixAllomorphModule>[
          EnglishSuffixAllomorphModule(),
        ],
        diagnostics: document.diagnostics,
      ),
    );

    expect(replanned.pronunciationProfileId, 'en-gb-core');
    expect(
      replanned.artifacts.any(
        (artifact) =>
            artifact.diagnosticCodes.contains(
              'pronunciation.resolved.possessive_allomorph',
            ),
      ),
      isTrue,
    );
  });

  test('document-time planner creates explicit suffix override artifacts', () {
    final document = DocumentImportService().importPastedText(
      "John'|z| hand. John|s| hand. John|es| hand.",
    );

    final explicitArtifacts = document.basePronunciationArtifacts.artifacts
        .where(
          (artifact) => artifact.diagnosticCodes.contains(
            'pronunciation.explicit_suffix_override',
          ),
        )
        .toList(growable: false);

    expect(explicitArtifacts, hasLength(3));
    expect(
      explicitArtifacts.map(
        (artifact) => artifact.representations.first.representationValue,
      ),
      <String>['z', 's', 'ɪz'],
    );
    expect(
      explicitArtifacts.map((artifact) => artifact.normalizedSurfaceText),
      everyElement('john'),
    );
  });

  test('document-time planner resolves weapon bow context to boh', () {
    final document = DocumentImportService().importPastedText(
      'She carried a bow and arrow. He packed a bow with arrows.',
    );

    final bowArtifacts = document.basePronunciationArtifacts.artifacts
        .where((artifact) => artifact.normalizedSurfaceText == 'bow')
        .toList(growable: false);

    expect(bowArtifacts, hasLength(2));
    expect(
      bowArtifacts.map(
        (artifact) => artifact.representations.first.representationType,
      ),
      everyElement('phoneme_string'),
    );
    expect(
      bowArtifacts.map(
        (artifact) => artifact.representations.first.representationValue,
      ),
      everyElement('bˈoʊ'),
    );
    expect(
      bowArtifacts.expand((artifact) => artifact.diagnosticCodes),
      contains('pronunciation.resolved.heteronym.weapon_bow'),
    );
  });
}
