import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/engine_capability.dart';
import 'package:read_aloud/src/models/pronunciation_artifact.dart';
import 'package:read_aloud/src/models/tts_artifact.dart';
import 'package:read_aloud/src/services/english_pronunciation_dictionary_service.dart';
import 'package:read_aloud/src/services/kokoro_pronunciation_translation_service.dart';

void main() {
  group('KokoroPronunciationTranslationService', () {
    const service = KokoroPronunciationTranslationService();

    setUp(() {
      EnglishPronunciationDictionaryService.instance.resetForTesting();
    });

    tearDown(() {
      EnglishPronunciationDictionaryService.instance.resetForTesting();
    });

    test('applies normalized spoken text replacements as approximations', () {
      final result = service.translate(
        chunkId: 'chunk-1',
        segments: <TtsArtifactSegment>[
          TtsArtifactSegment(
            segmentId: 'segment-1',
            speakText: "Elliot retorted sharply.",
            pronunciationArtifacts: const <RealizedPronunciationArtifact>[
              RealizedPronunciationArtifact(
                artifactId: 'artifact-1',
                segmentId: 'segment-1',
                startWord: 0,
                endWord: 1,
                resolutionClass: 'direct_resolved',
                translationIntent: 'normalized_spoken_text',
                selectedRepresentation: PronunciationRepresentation(
                  representationId: 'rep-1',
                  representationType: 'normalized_spoken_text',
                  representationValue: 'Ellie-ot',
                  priority: 1,
                ),
                diagnosticCodes: <String>['pronunciation.resolved.lexicon'],
              ),
            ],
          ),
        ],
      );

      expect(result.speakText, 'Ellie-ot retorted sharply.');
      expect(result.missingFallbackWordCount, 2);
      expect(result.capabilityProfileId, startsWith('kokoro:'));
      expect(
        result.pronunciationArtifacts.single.translationOutcome,
        KokoroPronunciationTranslationOutcome.approximated,
      );
    });

    test(
      'uses direct phoneme payloads when capability profile supports them',
      () {
        final capabilityProfile = const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
          platformFamily: 'macos',
        );
        final result = service.translate(
          chunkId: 'chunk-2',
          capabilityProfile: capabilityProfile,
          segments: <TtsArtifactSegment>[
            TtsArtifactSegment(
              segmentId: 'segment-2',
              speakText: 'for Elliot exclaimed',
              pronunciationArtifacts: const <RealizedPronunciationArtifact>[
                RealizedPronunciationArtifact(
                  artifactId: 'artifact-phoneme',
                  segmentId: 'segment-2',
                  startWord: 1,
                  endWord: 2,
                  resolutionClass: 'direct_resolved',
                  translationIntent: 'phoneme_string',
                  selectedRepresentation: PronunciationRepresentation(
                    representationId: 'rep-phoneme',
                    representationType: 'phoneme_string',
                    representationValue: 'ˈɛliət',
                    priority: 1,
                  ),
                  diagnosticCodes: <String>['pronunciation.resolved.lexicon'],
                ),
                RealizedPronunciationArtifact(
                  artifactId: 'artifact-unresolved',
                  segmentId: 'segment-2',
                  startWord: 2,
                  endWord: 3,
                  resolutionClass: 'unresolved',
                  translationIntent: 'engine_default',
                  diagnosticCodes: <String>[
                    'pronunciation.unresolved.voice_session',
                  ],
                ),
              ],
            ),
          ],
        );

        expect(result.speakText, 'for Elliot exclaimed');
        expect(result.missingFallbackWordCount, 1);
        expect(
          result.pronunciationArtifacts.map(
            (artifact) => artifact.translationOutcome,
          ),
          <KokoroPronunciationTranslationOutcome>[
            KokoroPronunciationTranslationOutcome.direct,
            KokoroPronunciationTranslationOutcome.deferred,
          ],
        );
        expect(
          result.payloadUnits,
          contains(
            isA<KokoroEnginePayloadUnit>()
                .having(
                  (unit) => unit.kind,
                  'kind',
                  KokoroEnginePayloadUnitKind.phonemeString,
                )
                .having((unit) => unit.value, 'value', 'ˈɛliət'),
          ),
        );
        expect(
          result.pronunciationArtifacts.map((artifact) => artifact.artifactId),
          <String>['artifact-phoneme', 'artifact-unresolved'],
        );
      },
    );

    test('uses engine-level allomorph payloads for possessive s-class endings', () {
      final capabilityProfile = const EngineCapabilityRegistry().lookup(
        engineId: 'kokoro',
        platformFamily: 'macos',
      );
      final result = service.translate(
        chunkId: 'chunk-3',
        capabilityProfile: capabilityProfile,
        segments: <TtsArtifactSegment>[
          TtsArtifactSegment(
            segmentId: 'segment-3',
            speakText: "John's idea",
            pronunciationArtifacts: const <RealizedPronunciationArtifact>[
              RealizedPronunciationArtifact(
                artifactId: 'artifact-possessive',
                segmentId: 'segment-3',
                startWord: 0,
                endWord: 1,
                resolutionClass: 'direct_resolved',
                translationIntent: 'normalized_spoken_text',
                selectedRepresentation: PronunciationRepresentation(
                  representationId: 'rep-possessive',
                  representationType: 'normalized_spoken_text',
                  representationValue: 'Johnz',
                  priority: 1,
                ),
                diagnosticCodes: <String>[
                  'pronunciation.resolved.possessive_allomorph',
                ],
              ),
            ],
          ),
        ],
      );

      expect(
        result.pronunciationArtifacts.single.translationOutcome,
        KokoroPronunciationTranslationOutcome.direct,
      );
      expect(
        result.payloadUnits,
        contains(
          isA<KokoroEnginePayloadUnit>()
              .having(
                (unit) => unit.kind,
                'kind',
                KokoroEnginePayloadUnitKind.englishSClassAllomorph,
              )
              .having((unit) => unit.value, 'value', "John's"),
        ),
      );
    });

    test(
      'prefers explicit suffix payloads for possessives when that representation is selected',
      () {
        final capabilityProfile = const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
          platformFamily: 'macos',
        );
        final result = service.translate(
          chunkId: 'chunk-4',
          capabilityProfile: capabilityProfile,
          segments: <TtsArtifactSegment>[
            TtsArtifactSegment(
              segmentId: 'segment-4',
              speakText: "John's idea",
              pronunciationArtifacts: const <RealizedPronunciationArtifact>[
                RealizedPronunciationArtifact(
                  artifactId: 'artifact-possessive-suffix',
                  segmentId: 'segment-4',
                  startWord: 0,
                  endWord: 1,
                  resolutionClass: 'context_resolved',
                  translationIntent: 'explicit_suffix_phoneme',
                  selectedRepresentation: PronunciationRepresentation(
                    representationId: 'rep-possessive-suffix',
                    representationType: 'explicit_suffix_phoneme',
                    representationValue: 'z',
                    priority: 110,
                  ),
                  diagnosticCodes: <String>[
                    'pronunciation.resolved.possessive_allomorph',
                  ],
                ),
              ],
            ),
          ],
        );

        expect(
          result.pronunciationArtifacts.single.translationOutcome,
          KokoroPronunciationTranslationOutcome.direct,
        );
        expect(
          result.payloadUnits,
          contains(
            isA<KokoroEnginePayloadUnit>()
                .having(
                  (unit) => unit.kind,
                  'kind',
                  KokoroEnginePayloadUnitKind.explicitSuffixPhoneme,
                )
                .having(
                  (unit) => unit.value,
                  'value',
                  contains('"baseSurfaceText":"John"'),
                )
                .having(
                  (unit) => unit.value,
                  'value',
                  contains('"suffixPhoneme":"z"'),
                ),
          ),
        );
      },
    );

    test('builds direct payloads for explicit suffix phoneme overrides', () {
      final capabilityProfile = const EngineCapabilityRegistry().lookup(
        engineId: 'kokoro',
        platformFamily: 'macos',
      );
      final result = service.translate(
        chunkId: 'chunk-5',
        capabilityProfile: capabilityProfile,
        segments: <TtsArtifactSegment>[
          TtsArtifactSegment(
            segmentId: 'segment-5',
            speakText: "John'|z| hand.",
            pronunciationArtifacts: const <RealizedPronunciationArtifact>[
              RealizedPronunciationArtifact(
                artifactId: 'artifact-explicit-suffix',
                segmentId: 'segment-5',
                startWord: 0,
                endWord: 1,
                resolutionClass: 'direct_resolved',
                translationIntent: 'explicit_suffix_phoneme',
                selectedRepresentation: PronunciationRepresentation(
                  representationId: 'rep-explicit-suffix',
                  representationType: 'explicit_suffix_phoneme',
                  representationValue: 'z',
                  priority: 120,
                ),
                diagnosticCodes: <String>[
                  'pronunciation.explicit_suffix_override',
                ],
              ),
            ],
          ),
        ],
      );

      expect(
        result.pronunciationArtifacts.single.translationOutcome,
        KokoroPronunciationTranslationOutcome.direct,
      );
      expect(
        result.payloadUnits,
        contains(
          isA<KokoroEnginePayloadUnit>()
              .having(
                (unit) => unit.kind,
                'kind',
                KokoroEnginePayloadUnitKind.explicitSuffixPhoneme,
              )
              .having(
                (unit) => unit.value,
                'value',
                contains('"baseSurfaceText":"John"'),
              )
              .having(
                (unit) => unit.value,
                'value',
                contains('"suffixPhoneme":"z"'),
              ),
        ),
      );
    });

    test(
      'uses CMUdict backstop for irregular lexical forms and contractions',
      () {
        EnglishPronunciationDictionaryService.instance.replaceEntriesForTesting(
          <String, String>{
            "can't": 'kˈænt',
            "it's": 'ˈɪts',
            "they're": 'ðˈɛɹ',
          },
        );

        final capabilityProfile = const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
          platformFamily: 'macos',
        );
        final result = service.translate(
          chunkId: 'chunk-6',
          capabilityProfile: capabilityProfile,
          segments: const <TtsArtifactSegment>[
            TtsArtifactSegment(
              segmentId: 'segment-6',
              speakText: "It's clear they’re fine and can't stay.",
              pronunciationArtifacts: <RealizedPronunciationArtifact>[],
            ),
          ],
        );

        final backstopArtifacts = result.pronunciationArtifacts
            .where(
              (artifact) => artifact.diagnosticCodes.contains(
                'pronunciation.resolved.cmudict_backstop',
              ),
            )
            .toList(growable: false);

        expect(backstopArtifacts, hasLength(3));
        expect(
          backstopArtifacts.map((artifact) => artifact.artifactId),
          containsAll(<String>["dict_it's", "dict_they're", "dict_can't"]),
        );
        expect(
          result.payloadUnits
              .where(
                (unit) =>
                    unit.kind == KokoroEnginePayloadUnitKind.phonemeString,
              )
              .map((unit) => unit.value),
          containsAll(<String>['ˈɪts', 'ðˈɛɹ', 'kˈænt']),
        );
      },
    );

    test(
      'still dictionary-backstops for while leaving the remaining function-word skip list intact',
      () {
        EnglishPronunciationDictionaryService.instance.replaceEntriesForTesting(
          <String, String>{
            'for': 'fɔɹ',
            'the': 'ðə',
            'to': 'tu',
          },
        );

        final capabilityProfile = const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
          platformFamily: 'macos',
        );
        final result = service.translate(
          chunkId: 'chunk-7',
          capabilityProfile: capabilityProfile,
          segments: const <TtsArtifactSegment>[
            TtsArtifactSegment(
              segmentId: 'segment-7',
              speakText: 'for the road to town',
              pronunciationArtifacts: <RealizedPronunciationArtifact>[],
            ),
          ],
        );

        final backstopArtifacts = result.pronunciationArtifacts
            .where(
              (artifact) => artifact.diagnosticCodes.contains(
                'pronunciation.resolved.cmudict_backstop',
              ),
            )
            .toList(growable: false);
        expect(backstopArtifacts, hasLength(1));
        expect(backstopArtifacts.single.artifactId, 'dict_for');
        expect(
          result.payloadUnits.where(
            (unit) => unit.kind == KokoroEnginePayloadUnitKind.phonemeString,
          ),
          hasLength(1),
        );
        expect(
          result.payloadUnits
              .where(
                (unit) =>
                    unit.kind == KokoroEnginePayloadUnitKind.phonemeString,
              )
              .single
              .value,
          'fɔɹ',
        );
      },
    );
  });
}
