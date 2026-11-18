import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/cast_voice_assignment.dart';
import 'package:read_aloud/src/models/character.dart';
import 'package:read_aloud/src/models/character_linguistic_evidence.dart';
import 'package:read_aloud/src/models/document_voice_attribution.dart';
import 'package:read_aloud/src/models/reader_document.dart';
import 'package:read_aloud/src/services/cast_aware_speech_route_service.dart';
import 'package:read_aloud/src/services/character_route_refinement.dart';
import 'package:read_aloud/src/services/document_analysis_record.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/modernbooknlp_character_adapter.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';
import 'package:read_aloud/src/services/modernbooknlp_window.dart';

void main() {
  test('missed dialogue routes exact words to the reported speaker', () async {
    final document = DocumentImportService().importPastedText(
      'Mara watched Lee. She said, ‘Tell Lee,’ then waved.',
    );
    final window = ModernBookNlpWindow.at(document, wordIndex: 0)!;
    expect(
      document.documentVoiceAttribution.ranges.map((r) => r.kind),
      everyElement(DocumentVoiceAttributionKind.narration),
    );
    final request = _request(window);
    final result = _result(
      request,
      mentions: {
        'mara': [('Mara', true), ('She', false)],
        'lee': [('Lee', true)],
      },
      quotes: [("'Tell Lee,'", 'mara')],
    );

    final delta = await projectModernBookNlpCharacters(
      request,
      result,
      document.characterCastRegistry,
      window,
      authoritativeQuotes: true,
    );
    final mara = delta.registry.characterEntries.singleWhere(
      (entry) => entry.displayLabel == 'Mara',
    );
    final ranges = _refine(document, delta.dialogues);
    _expectExactCover(document, ranges);
    expect(
      ranges.map(
        (range) => (range.startWordIndex, range.endWordIndex, range.castId),
      ),
      [(0, 5, 'cast_narrator'), (5, 7, mara.castId), (7, 9, 'cast_narrator')],
    );
    final routed = const CastAwareSpeechRouteService().build(
      CastAwareSpeechRouteInput(
        documentVoiceAttribution: DocumentVoiceAttributionSet(
          documentId: document.speechDocument.documentId,
          attributionVersion: 'test',
          ranges: ranges,
        ),
        castVoiceAssignments: CastVoiceAssignmentSet(
          documentId: document.speechDocument.documentId,
          assignmentVersion: 'test',
          assignments: [
            CastVoiceAssignment(
              castId: 'cast_narrator',
              effectiveVoiceId: 'narrator',
              decisionKind: VoiceAssignmentDecisionKind.automatic,
            ),
            CastVoiceAssignment(
              castId: mara.castId,
              effectiveVoiceId: 'mara',
              decisionKind: VoiceAssignmentDecisionKind.automatic,
            ),
          ],
        ),
      ),
    );
    expect(routed.ranges.map((r) => r.voiceId), [
      'narrator',
      'mara',
      'narrator',
    ]);
    expect(routed.ranges.map((r) => r.routeId).toSet(), hasLength(3));
  });

  test(
    'authored routes survive even a provider quote crossing their boundary',
    () {
      final document = DocumentImportService().importPastedText(
        '"Wait," Ada said. "Ready," Bruno replied.',
      );
      final window = ModernBookNlpWindow.at(document, wordIndex: 0)!;
      final original = document.documentVoiceAttribution.ranges;
      final firstDialogue = original.firstWhere(
        (r) => r.dialogueSpanId != null,
      );
      final request = _request(window);
      final result = _result(
        request,
        mentions: {
          'ada': [('Ada', true)],
          'bruno': [('Bruno', true)],
        },
        quotes: [
          (
            window.text.substring(
              0,
              window.text.indexOf('said') + 'said'.length,
            ),
            'bruno',
          ),
          ('"Ready,"', 'bruno'),
        ],
      );
      final delta = _project(document, window, result);
      final ranges = _refine(
        document,
        delta.dialogues,
        protected: {firstDialogue.dialogueSpanId!},
      );
      _expectExactCover(document, ranges);
      expect(ranges.first, same(firstDialogue));
      expect(
        ranges.where(
          (r) => r.dialogueSpanId?.startsWith('nlp_quote_') ?? false,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'split-word evidence leaves narration intact and ambiguous speakers stay unknown',
    () {
      final document = DocumentImportService().importPastedText(
        'Mara and Lee listened. She said, ‘Hold steady,’ and turned.',
      );
      final window = ModernBookNlpWindow.at(document, wordIndex: 0)!;
      final request = _request(window);
      final mentions = {
        'mara': [('Mara', true)],
        'lee': [('Lee', true)],
        'she': [('She', false)],
      };
      for (final quotes in [
        [('old steady', 'mara')],
        [('Hold steady', 'mara'), ('Hold steady', 'lee')],
        [('Hold steady', 'she')],
      ]) {
        final delta = _project(
          document,
          window,
          _result(request, mentions: mentions, quotes: quotes),
        );
        final ranges = _refine(document, delta.dialogues);
        _expectExactCover(document, ranges);
        final dialogue = ranges
            .where(
              (range) => range.kind != DocumentVoiceAttributionKind.narration,
            )
            .toList();
        if (quotes.first.$1 == 'old steady') {
          expect(dialogue, isEmpty);
        } else {
          expect(
            dialogue.single.kind,
            DocumentVoiceAttributionKind.unattributedDialogue,
          );
        }
      }
    },
  );

  test(
    'a complete quote can cross source slices but cannot publish contextual slices',
    () {
      final document = DocumentImportService().importPastedText(
        'Ada waited.\n\n“First sentence\n\nsecond sentence.”\n\nThen narration resumed.',
      );
      final window = ModernBookNlpWindow.at(document, wordIndex: 0)!;
      final request = _request(window);
      final quote = window.text.substring(
        window.text.indexOf('"'),
        window.text.lastIndexOf('"') + 1,
      );
      final result = _result(
        request,
        mentions: {
          'ada': [('Ada', true)],
        },
        quotes: [(quote, 'ada')],
      );
      final projected = _project(document, window, result);
      final authority = projected.dialogues
          .where((r) => r.quoteAuthority)
          .toList();
      expect(authority.map((r) => r.segmentId).toSet().length, greaterThan(1));
      expect(authority.map((r) => r.dialogueSpanId).toSet(), hasLength(1));
      final ranges = _refine(document, projected.dialogues);
      _expectExactCover(document, ranges);
      expect(
        ranges
            .singleWhere(
              (r) => r.dialogueSpanId == authority.first.dialogueSpanId,
            )
            .segmentIds,
        authority.map((r) => r.segmentId),
      );
      final onlyOneSlice = modernBookNlpCharacterDelta(
        request: request,
        result: result,
        registry: document.characterCastRegistry,
        turns: window.turns,
        sourceSlices: window.slices,
        targetSegmentIds: {authority.first.segmentId},
        authoritativeQuotes: true,
      );
      expect(onlyOneSlice.dialogues.where((r) => r.quoteAuthority), isEmpty);
    },
  );

  test('retained raw provider evidence keeps the speaker mention separate', () {
    final document = DocumentImportService().importPastedText(
      File('test/fixtures/rc2_prose/text/rain.txt').readAsStringSync(),
    );
    final window = ModernBookNlpWindow.at(document, wordIndex: 0)!;
    final record = DocumentAnalysisRecord.fromJson(
      jsonDecode(
        File('test/fixtures/modernbooknlp/rain-record.json').readAsStringSync(),
      ),
    );
    final result = record.forRequest(
      _request(window, sourceRevision: record.sourceRevision),
    );
    final delta = _project(document, window, result);
    final authority = delta.dialogues.where((r) => r.quoteAuthority).toList();
    expect(authority.map((r) => r.dialogueSpanId).toSet(), hasLength(11));
    expect(
      authority.where((r) => r.speakerMention?.text == 'Leon'),
      isNotEmpty,
    );
    expect(
      authority.where(
        (r) => r.speakerMention?.kind == CharacterObservationKind.proper,
      ),
      isNotEmpty,
    );
    _expectExactCover(document, _refine(document, delta.dialogues));

    // Moving a normalized speaker link to a different real entity leaves the
    // source quote intact and makes its speaker unresolved.
    final quotes = result['quotes'] as List;
    expect(authority.first.castId, isNotNull);
    quotes.first['entityId'] = quotes[1]['entityId'];
    final disagreement = _project(document, window, result);
    final firstQuote = disagreement.dialogues.firstWhere(
      (r) => r.quoteAuthority,
    );
    expect(firstQuote.dialogueSpanId, authority.first.dialogueSpanId);
    expect(firstQuote.castId, isNull);
  });

  test(
    'quote boundaries correct a bound heuristic turn and restore reporting words to narration',
    () {
      final document = DocumentImportService().importPastedText(
        'Mara said, “Go now, Lee!”',
      );
      final window = ModernBookNlpWindow.at(document, wordIndex: 0)!;
      final request = _request(window);
      final delta = _project(
        document,
        window,
        _result(
          request,
          mentions: {
            'mara': [('Mara', true)],
            'lee': [('Lee', true)],
          },
          quotes: [('"Go now, Lee!"', 'mara')],
        ),
      );
      final segments = document.speechDocument.segments;
      final segmentIds = segments.map((segment) => segment.segmentId).toList();
      final heuristic = DocumentVoiceAttributionSet(
        documentId: document.speechDocument.documentId,
        attributionVersion: 'test',
        ranges: [
          DocumentVoiceAttributionRange(
            rangeId: 'heuristic',
            segmentIds: segmentIds,
            startSegmentId: segmentIds.first,
            endSegmentId: segmentIds.last,
            startWordIndex: 0,
            endWordIndex: document.wordCount,
            castId: 'wrong_cast',
            kind: DocumentVoiceAttributionKind.attributedDialogue,
            dialogueSpanId: 'old_quote',
          ),
        ],
      );
      final routes = refineCharacterRoutes(heuristic, [
        ...delta.dialogues,
        for (final segment in segments)
          CharacterDialogueReference(
            attributionId: 'old',
            dialogueSpanId: 'old_quote',
            segmentId: segment.segmentId,
            startWord: 0,
            endWord: segment.wordCount,
            sourceMatched: false,
          ),
      ], speechDocument: document.speechDocument).ranges;
      final mara = delta.registry.characterEntries.singleWhere(
        (entry) => entry.displayLabel == 'Mara',
      );
      _expectExactCover(document, routes);
      expect(routes.map((r) => r.castId), ['cast_narrator', mara.castId]);
      expect(routes.first.endWordIndex, 2);
    },
  );
}

CharacterAnalysisDelta _project(
  ReaderDocument document,
  ModernBookNlpWindow window,
  Map<String, dynamic> result,
) => modernBookNlpCharacterDelta(
  request: _request(window, sourceRevision: result['sourceRevision'] as String),
  result: result,
  registry: document.characterCastRegistry,
  turns: window.turns,
  sourceSlices: window.slices,
  authoritativeQuotes: true,
);

ModernBookNlpRequest _request(
  ModernBookNlpWindow window, {
  String sourceRevision = 'source',
}) => ModernBookNlpRequest(
  requestId: 'request',
  ownerId: 'owner',
  workId: 'work',
  sourceRevision: sourceRevision,
  analysisRevision: 1,
  sequence: 1,
  text: window.text,
  windowPolicy: 'paragraph-context-v2',
);

Map<String, dynamic> _result(
  ModernBookNlpRequest request, {
  required Map<String, List<(String, bool)>> mentions,
  required List<(String, String?)> quotes,
}) {
  Map<String, int> bounds(String value) {
    final start = request.text.indexOf(value);
    expect(start, greaterThanOrEqualTo(0));
    return {'startUtf16': start, 'endUtf16': start + value.length};
  }

  return {
    ...request.toJson(),
    'providerId': 'modernbooknlp-joint',
    'providerVersion': modernBookNlpRevision,
    'modelIdentity': modernBookNlpModelIdentity,
    'adapterVersion': modernBookNlpAdapterVersion,
    'entities': [
      for (final entry in mentions.entries)
        {
          'entityId': entry.key,
          'mentions': [
            for (final (text, proper) in entry.value)
              {...bounds(text), 'text': text, 'proper': proper},
          ],
        },
    ],
    'quotes': [
      for (final (text, entity) in quotes)
        {...bounds(text), 'entityId': entity, 'confidence': null},
    ],
  };
}

List<DocumentVoiceAttributionRange> _refine(
  ReaderDocument document,
  Iterable<CharacterDialogueReference> evidence, {
  Set<String> protected = const {},
}) => refineCharacterRoutes(
  document.documentVoiceAttribution,
  evidence,
  speechDocument: document.speechDocument,
  protectedSpanIds: protected,
).ranges;

void _expectExactCover(
  ReaderDocument document,
  List<DocumentVoiceAttributionRange> ranges,
) {
  var word = 0;
  for (final range in ranges) {
    expect(range.startWordIndex, word);
    expect(range.endWordIndex, greaterThan(word));
    word = range.endWordIndex;
  }
  expect(word, document.wordCount);
}
