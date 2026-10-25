import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/models/narration_state.dart';
import 'package:read_aloud/src/models/voice_session_realization.dart';
import 'package:read_aloud/src/services/speech_planning_supervisor.dart';

void main() {
  final doc = ReaderDocument.sample();
  SpeechPlanningContext context() => SpeechPlanningContext(
    realization: VoiceSessionRealizationInput(
      speechDocument: doc.speechDocument,
      baseAnnotations: doc.baseSpeechAnnotations,
      basePronunciationArtifacts: doc.basePronunciationArtifacts,
      startSegmentId: doc.speechDocument.segments.first.segmentId,
      voiceId: 'af_bella',
      engineId: 'kokoro',
      rate: 1,
      narrationState: NarrationState.initial(),
    ),
    engineVersion: '2',
  );
  test(
    'one-chunk windows cover document contiguously with complete realization',
    () async {
      final owner = SpeechPlanningSupervisor();
      var next = doc.speechDocument.segments.first.segmentId;
      var end = 0;
      do {
        final result = await owner.plan(
          context(),
          startSegmentId: next,
          maxChunks: 1,
        );
        expect(result.plan.chunks, hasLength(1));
        final chunk = result.plan.chunks.single;
        expect(chunk.startWordIndex, end);
        end = chunk.endWordIndex;
        expect(
          result.realization.ttsArtifactSet.segments.map((s) => s.segmentId),
          containsAll(chunk.segmentIds),
        );
        final following = result.plan.nextSegmentId;
        if (following == null) break;
        next = following;
      } while (true);
      expect(end, doc.wordCount);
      await owner.shutdown();
    },
  );
  test(
    'latest planning request settles cancelled predecessor and shutdown rejects work',
    () async {
      final owner = SpeechPlanningSupervisor();
      final old = owner.plan(context());
      final cancelled = expectLater(old, throwsA(isA<PlanningCancelled>()));
      final latest = owner.plan(context(), maxChunks: 1);
      await cancelled;
      expect((await latest).plan.chunks, hasLength(1));
      await owner.shutdown();
      await expectLater(
        owner.plan(context()),
        throwsA(isA<PlanningCancelled>()),
      );
    },
  );
}
