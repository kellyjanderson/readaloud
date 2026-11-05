import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/speech_adjustment_context.dart';
import 'package:read_aloud/src/models/engine_capability.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/kokoro_pronunciation_translation_service.dart';
import 'package:read_aloud/src/services/reader_document_codec.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';
import 'package:read_aloud/src/services/voice_session_realization_service.dart';

void main() {
  test(
    'same engine with another model or revision cannot inherit a recipe',
    () {
      final document = DocumentImportService().importPastedText(
        'I waited for them.',
      );
      for (final profile in [
        const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
          modelId: 'other',
        ),
        const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
          modelRevision: '2.0',
        ),
        const EngineCapabilityRegistry().lookup(
          engineId: 'kokoro',
          capabilityVersion: 'v2',
        ),
      ]) {
        final result = _translate(document, 'kokoro', capability: profile);
        expect(result.speakText, 'I waited for them.');
        expect(
          result.pronunciationArtifacts
              .singleWhere((artifact) => artifact.adjustmentDecision != null)
              .adjustmentDecision!['reason'],
          'context_mismatch',
        );
      }
    },
  );

  test(
    'legacy range-prefixed recipe migrates without broadening its scope',
    () {
      final document = DocumentImportService().importPastedText(
        'I waited for them.',
      );
      final data =
          jsonDecode(
                const ReaderDocumentSerializationService()
                    .serializeToJsonString(document),
              )
              as Map<String, dynamic>;
      final artifacts = data['basePronunciationArtifacts']['artifacts'] as List;
      final representation =
          artifacts.firstWhere(
                (a) => a['normalizedSurfaceText'] == 'for',
              )['representations'][0]
              as Map;
      representation.remove('context');
      representation['representationId'] = 'range7:lex_for_spoken';
      final restored = decodeReaderDocument(jsonEncode(data));
      final context = restored.basePronunciationArtifacts.artifacts
          .firstWhere((a) => a.normalizedSurfaceText == 'for')
          .representations
          .single
          .context;
      expect(context.scope, SpeechAdjustmentScope.engineModel);
      expect(
        _translate(restored, 'fish_drama3').speakText,
        'I waited for them.',
      );
      expect(_translate(restored, 'kokoro').speakText, 'I waited four them.');

      // Unknown historical engine-specific overrides cannot acquire a global
      // scope merely because their saved context is absent.
      artifacts.firstWhere(
        (a) => a['normalizedSurfaceText'] == 'for',
      )['source'] = 'userOverride';
      representation['representationId'] = 'unknown-engine-rule';
      final unknown = decodeReaderDocument(jsonEncode(data));
      expect(_translate(unknown, 'kokoro').speakText, 'I waited for them.');
      expect(
        _translate(unknown, 'fish_drama3').speakText,
        'I waited for them.',
      );
    },
  );

  for (final engine in <String>[
    'kokoro',
    'fish_drama3',
    'fish_drama3_8bit',
    'fish_drama3_4bit',
    'qwen3_tts_base_1_7b',
    'qwen3_tts_1_7b',
    'voxtral_4b',
    'moss_tts_8b',
  ]) {
    for (final reopen in <bool>[false, true]) {
      test('$engine scopes legacy for workaround (reopen=$reopen)', () {
        const text = 'I waited for four friends, for better or worse.';
        var document = DocumentImportService().importPastedText(text);
        if (reopen) {
          document = decodeReaderDocument(
            const ReaderDocumentSerializationService().serializeToJsonString(
              document,
            ),
          );
        }
        // Existing prepared books retain this legacy app annotation. They
        // must not need reimporting or deletion to get correct engine text.
        final artifacts = document.basePronunciationArtifacts.artifacts
            .where((artifact) => artifact.normalizedSurfaceText == 'for')
            .toList();
        expect(artifacts, hasLength(2));
        for (final artifact in artifacts) {
          expect(
            artifact.representations.single.representationId,
            'lex_for_spoken',
          );
          expect(artifact.representations.single.representationValue, 'four');
        }

        final result = _translate(document, engine);
        expect(
          result.speakText,
          engine == 'kokoro'
              ? 'I waited four four friends, four better or worse.'
              : text,
        );
        for (final artifact in artifacts) {
          expect(
            result.pronunciationArtifacts
                .singleWhere(
                  (translated) => translated.artifactId == artifact.artifactId,
                )
                .translationOutcome,
            engine == 'kokoro'
                ? KokoroPronunciationTranslationOutcome.approximated
                : KokoroPronunciationTranslationOutcome.deferred,
          );
        }
      });
    }
  }

  test('Fish preserves explicit for overrides, including four', () {
    final document = DocumentImportService().importPastedText(
      'I waited for them.',
    );
    final artifact = document.basePronunciationArtifacts.artifacts.singleWhere(
      (artifact) => artifact.normalizedSurfaceText == 'for',
    );
    for (final replacement in <String>['four', 'fur']) {
      final result = _translate(
        document,
        'fish_drama3',
        state: NarrationState.initial().copyWith(
          localPronunciationChoices: {artifact.artifactId: replacement},
        ),
      );
      expect(result.speakText, 'I waited $replacement them.');
      expect(
        result.pronunciationArtifacts
            .singleWhere(
              (translated) => translated.artifactId == artifact.artifactId,
            )
            .translationOutcome,
        KokoroPronunciationTranslationOutcome.approximated,
      );
    }
  });

  test('Fish retains other supported spoken-text expansions', () {
    final document = DocumentImportService().importPastedText(
      'An epub for them.',
    );
    expect(_translate(document, 'fish_drama3').speakText, 'An E pub for them.');
  });

  test('Fish retains original case and punctuation around for', () {
    final document = DocumentImportService().importPastedText(
      'For them, for now.',
    );
    expect(_translate(document, 'fish_drama3').speakText, 'For them, for now.');
  });
}

KokoroTranslatedChunk _translate(
  ReaderDocument document,
  String engine, {
  NarrationState? state,
  EngineCapabilityProfile? capability,
}) {
  final realization = const VoiceSessionRealizationService().realize(
    VoiceSessionRealizationInput(
      speechDocument: document.speechDocument,
      baseAnnotations: document.baseSpeechAnnotations,
      basePronunciationArtifacts: document.basePronunciationArtifacts,
      startSegmentId: document.speechDocument.segments.first.segmentId,
      voiceId: engine == 'kokoro' ? 'af_bella' : 'library_fishadrian',
      engineId: engine,
      rate: 1,
      narrationState: state ?? NarrationState.initial(),
    ),
  );
  return const KokoroPronunciationTranslationService().translate(
    chunkId: 'scope-test',
    segments: realization.ttsArtifactSet.segments,
    capabilityProfile:
        capability ??
        const EngineCapabilityRegistry().lookup(
          engineId: engine,
          platformFamily: 'macos',
        ),
  );
}
