import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/document_voice_attribution.dart';
import 'package:read_aloud/src/services/cast_aware_speech_route_service.dart';

void main() {
  group('CastAwareSpeechRouteService', () {
    const routeService = CastAwareSpeechRouteService();

    test(
      'routes document-owned narration and dialogue ownership to different voices',
      () {
        final routes = routeService.build(
          CastAwareSpeechRouteInput(
            documentVoiceAttribution: DocumentVoiceAttributionSet(
              documentId: 'doc_route_0',
              attributionVersion: 'doc-voice-v1',
              ranges: <DocumentVoiceAttributionRange>[
                DocumentVoiceAttributionRange(
                  rangeId: 'range_0',
                  segmentIds: const <String>['s_0'],
                  startSegmentId: 's_0',
                  endSegmentId: 's_0',
                  startWordIndex: 0,
                  endWordIndex: 4,
                  castId: 'cast_narrator',
                  kind: DocumentVoiceAttributionKind.narration,
                ),
                DocumentVoiceAttributionRange(
                  rangeId: 'range_1',
                  segmentIds: const <String>['s_1'],
                  startSegmentId: 's_1',
                  endSegmentId: 's_1',
                  startWordIndex: 4,
                  endWordIndex: 6,
                  castId: 'cast_character_jennifer',
                  kind: DocumentVoiceAttributionKind.attributedDialogue,
                  dialogueSpanId: 'dlg_s_1',
                ),
                DocumentVoiceAttributionRange(
                  rangeId: 'range_2',
                  segmentIds: const <String>['s_2'],
                  startSegmentId: 's_2',
                  endSegmentId: 's_2',
                  startWordIndex: 6,
                  endWordIndex: 9,
                  castId: 'cast_narrator',
                  kind: DocumentVoiceAttributionKind.narration,
                ),
              ],
            ),
            castVoiceAssignments: CastVoiceAssignmentSet(
              documentId: 'doc_route_0',
              assignmentVersion: 'assign-v1',
              assignments: <CastVoiceAssignment>[
                CastVoiceAssignment(
                  castId: 'cast_narrator',
                  effectiveVoiceId: 'af_bella',
                  decisionKind: VoiceAssignmentDecisionKind.automatic,
                ),
                CastVoiceAssignment(
                  castId: 'cast_character_jennifer',
                  effectiveVoiceId: 'bf_emma',
                  decisionKind: VoiceAssignmentDecisionKind.automatic,
                ),
              ],
            ),
          ),
        );

        expect(routes.ranges, hasLength(3));
        expect(routes.ranges[0].castId, 'cast_narrator');
        expect(routes.ranges[1].castId, 'cast_character_jennifer');
        expect(routes.ranges[1].voiceId, 'bf_emma');
        expect(routes.ranges[1].dialogueSpanId, 'dlg_s_1');
        expect(routes.ranges[2].castId, 'cast_narrator');
      },
    );

    test('merges adjacent narrator ranges with identical voice routing', () {
      final routes = routeService.build(
        CastAwareSpeechRouteInput(
          documentVoiceAttribution: DocumentVoiceAttributionSet(
            documentId: 'doc_route_1',
            attributionVersion: 'doc-voice-v1',
            ranges: <DocumentVoiceAttributionRange>[
              DocumentVoiceAttributionRange(
                rangeId: 'range_0',
                segmentIds: const <String>['s_0'],
                startSegmentId: 's_0',
                endSegmentId: 's_0',
                startWordIndex: 0,
                endWordIndex: 1,
                castId: 'cast_narrator',
                kind: DocumentVoiceAttributionKind.narration,
              ),
              DocumentVoiceAttributionRange(
                rangeId: 'range_1',
                segmentIds: const <String>['s_1'],
                startSegmentId: 's_1',
                endSegmentId: 's_1',
                startWordIndex: 1,
                endWordIndex: 2,
                castId: 'cast_narrator',
                kind: DocumentVoiceAttributionKind.narration,
              ),
            ],
          ),
          castVoiceAssignments: CastVoiceAssignmentSet(
            documentId: 'doc_route_1',
            assignmentVersion: 'assign-v1',
            assignments: <CastVoiceAssignment>[
              CastVoiceAssignment(
                castId: 'cast_narrator',
                effectiveVoiceId: 'af_bella',
                decisionKind: VoiceAssignmentDecisionKind.automatic,
              ),
            ],
          ),
        ),
      );

      expect(routes.ranges, hasLength(1));
      expect(routes.ranges.single.segmentIds, <String>['s_0', 's_1']);
    });

    test('falls back to narrator voice for unattributed dialogue ownership', () {
      final routes = routeService.build(
        CastAwareSpeechRouteInput(
          documentVoiceAttribution: DocumentVoiceAttributionSet(
            documentId: 'doc_route_2',
            attributionVersion: 'doc-voice-v1',
            ranges: <DocumentVoiceAttributionRange>[
              DocumentVoiceAttributionRange(
                rangeId: 'range_0',
                segmentIds: const <String>['s_0'],
                startSegmentId: 's_0',
                endSegmentId: 's_0',
                startWordIndex: 0,
                endWordIndex: 2,
                castId: 'cast_narrator',
                kind: DocumentVoiceAttributionKind.unattributedDialogue,
                dialogueSpanId: 'dlg_s_0',
              ),
            ],
          ),
          castVoiceAssignments: CastVoiceAssignmentSet(
            documentId: 'doc_route_2',
            assignmentVersion: 'assign-v1',
            assignments: <CastVoiceAssignment>[
              CastVoiceAssignment(
                castId: 'cast_narrator',
                effectiveVoiceId: 'af_bella',
                decisionKind: VoiceAssignmentDecisionKind.automatic,
              ),
            ],
          ),
        ),
      );

      expect(routes.ranges, hasLength(1));
      expect(routes.ranges.single.castId, 'cast_narrator');
      expect(routes.ranges.single.voiceId, 'af_bella');
      expect(routes.ranges.single.dialogueSpanId, 'dlg_s_0');
    });
  });
}
