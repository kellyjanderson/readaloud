import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/english_pronunciation_profile.dart';
import 'package:read_aloud/src/models/pronunciation_artifact.dart';
import 'package:read_aloud/src/services/pronunciation_resource_layering_service.dart';

void main() {
  group('PronunciationResourceLayeringService', () {
    const service = PronunciationResourceLayeringService();

    test('merges layers deterministically and tracks the winning layer', () {
      final merged = service.merge(
        PronunciationResourceLayeringInput(
          profile: EnglishPronunciationProfileRegistry.enUsCore,
          sourceMetadataResources: const <String, List<PronunciationRepresentation>>{
            'elliot': <PronunciationRepresentation>[
              PronunciationRepresentation(
                representationId: 'src_elliot',
                representationType: 'normalized_spoken_text',
                representationValue: 'EL-ee-ut',
                priority: 300,
              ),
            ],
          },
          userOverrideResources: const <String, List<PronunciationRepresentation>>{
            'elliot': <PronunciationRepresentation>[
              PronunciationRepresentation(
                representationId: 'user_elliot',
                representationType: 'normalized_spoken_text',
                representationValue: 'EL-ee-oht',
                priority: 900,
              ),
            ],
          },
        ),
      );

      expect(
        merged['elliot']?.single.representationValue,
        'EL-ee-oht',
      );
      expect(merged.winningLayerIdFor('elliot'), 'user-override');
      expect(
        merged.winningLayerKindFor('elliot'),
        PronunciationResourceLayerKind.userOverride,
      );
    });
  });
}
