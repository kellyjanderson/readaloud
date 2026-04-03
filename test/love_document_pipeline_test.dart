import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/chunk_plan.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/chunk_planner_service.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/voice_session_realization_service.dart';

void main() {
  test(
    'Love test document preserves the shouted quote through chunk planning',
    () async {
      final importer = DocumentImportService();
      final file = File('project/testdocs/Love.txt');
      final bytes = await file.readAsBytes();
      final document = await importer.importBytes(
        fileName: 'Love.txt',
        bytes: bytes,
      );

      expect(document.speakableText, contains('JUST STOP FIGHTING'));
      expect(
        document.speechDocument.segments.any(
          (segment) => segment.normalizedText.contains('JUST STOP FIGHTING'),
        ),
        isTrue,
      );

      final planner = const ChunkPlannerService();
      final realization = const VoiceSessionRealizationService().realize(
        VoiceSessionRealizationInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          basePronunciationArtifacts: document.basePronunciationArtifacts,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          engineId: 'kokoro',
          rate: 1.0,
          narrationState: NarrationState.initial(),
        ),
      );
      final plan = planner.plan(
        ChunkPlannerInput(
          speechDocument: document.speechDocument,
          baseAnnotations: document.baseSpeechAnnotations,
          ttsArtifactSet: realization.ttsArtifactSet,
          startSegmentId: document.speechDocument.segments.first.segmentId,
          voiceId: 'af_bella',
          rate: 1.0,
          engineId: 'kokoro',
          engineVersion: '2',
        ),
      );

      expect(
        plan.chunks.any(
          (chunk) => chunk.speakText.contains('JUST STOP FIGHTING'),
        ),
        isTrue,
      );
    },
  );
}
