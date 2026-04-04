import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/position_map.dart';
import 'package:read_aloud/src/models/spoken_selection.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/spoken_selection_mapper_service.dart';
import 'package:read_aloud/src/services/tts_engine.dart';

void main() {
  group('SpokenSelectionMapperService', () {
    const mapper = SpokenSelectionMapperService();
    final document = DocumentImportService().importPastedText(
      'Alpha beta. Gamma delta.',
    );

    test('derives word-level spoken selection from progress', () {
      final selection = mapper.map(
        SpokenSelectionMapperInput(
          displayDocument: document.displayDocument,
          speechDocument: document.speechDocument,
          positionMap: document.positionMap,
          progress: TtsProgressUpdate(
            startOffset: 6,
            endOffset: 10,
            word: 'beta',
            documentId: document.displayDocument.documentId,
            chunkId: 'chunk-1',
            segmentId: document.speechDocument.segments.first.segmentId,
            wordStartIndex: 1,
            wordEndIndex: 2,
            voiceId: 'af_bella',
            rate: 1.0,
            routeId: 'route_narration',
            castId: 'cast_narrator',
          ),
        ),
      );

      expect(selection.precision, SpokenSelectionPrecision.word);
      expect(selection.displayBlockId, document.displayDocument.blocks.first.blockId);
      expect(selection.displayStart, 6);
      expect(selection.displayEnd, 11);
      expect(selection.routeId, 'route_narration');
      expect(selection.castId, 'cast_narrator');
    });

    test('falls back to segment-level selection when word range is missing', () {
      final selection = mapper.map(
        SpokenSelectionMapperInput(
          displayDocument: document.displayDocument,
          speechDocument: document.speechDocument,
          positionMap: document.positionMap,
          progress: TtsProgressUpdate(
            startOffset: 0,
            endOffset: 11,
            word: 'beta',
            documentId: document.displayDocument.documentId,
            chunkId: 'chunk-1',
            segmentId: document.speechDocument.segments.first.segmentId,
            voiceId: 'af_bella',
            rate: 1.0,
          ),
        ),
      );

      expect(selection.precision, SpokenSelectionPrecision.segment);
      expect(selection.displayStart, 0);
      expect(selection.displayEnd, 11);
    });

    test('falls back to block-level selection without a position-map entry', () {
      final selection = mapper.map(
        SpokenSelectionMapperInput(
          displayDocument: document.displayDocument,
          speechDocument: document.speechDocument,
          positionMap: const PositionMap(
            documentId: 'doc-empty',
            mappingVersion: 'v1',
            entries: <PositionMapEntry>[],
          ),
          progress: TtsProgressUpdate(
            startOffset: 0,
            endOffset: 11,
            word: 'beta',
            documentId: document.displayDocument.documentId,
            chunkId: 'chunk-1',
            segmentId: document.speechDocument.segments.first.segmentId,
            voiceId: 'af_bella',
            rate: 1.0,
          ),
        ),
      );

      expect(selection.precision, SpokenSelectionPrecision.block);
      expect(selection.displayBlockId, document.displayDocument.blocks.first.blockId);
      expect(
        selection.displayEnd,
        document.displayDocument.blocks.first.plainText.length,
      );
    });
  });
}
