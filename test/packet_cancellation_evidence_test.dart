import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';

import '../tools/radoc_first_load_smoke.dart';

SpokenChunkRecord record({
  String documentId = 'document',
  String chunkId = 'first-scene',
  int startWord = 0,
  int endWord = 1,
  Duration duration = Duration.zero,
  bool completed = false,
}) => SpokenChunkRecord(
  chunkId: chunkId,
  documentId: documentId,
  segmentIds: const ['first-segment'],
  startWordIndex: startWord,
  endWordIndex: endWord,
  wordCount: endWord - startWord,
  audioDuration: duration,
  playbackOffset: Duration.zero,
  voiceId: 'voice',
  rate: 1,
  completed: completed,
);

bool unknown(List<SpokenChunkRecord> records, {int word = 1}) =>
    hasUnknownActiveSpokenScene(
      records,
      documentId: 'document',
      currentWordIndex: word,
    );

void main() {
  test('native first-packet heard boundary is not a final scene boundary', () {
    // Observed native case: a 51-word parent has heard coverage [0, 1),
    // currentWordIndex=1, and no final duration. A strict word<end test loses
    // positive packet ownership even though the producer is still unfinished.
    final firstPacket = record();
    expect(unknown([firstPacket]), isTrue);
    expect(unknown([firstPacket], word: 0), isTrue);
    expect(unknown([firstPacket], word: 2), isFalse);
    expect(unknown([firstPacket], word: -1), isFalse);
  });

  test('final publication and completed records cannot qualify', () {
    expect(unknown([record(duration: const Duration(seconds: 4))]), isFalse);
    expect(unknown([record(completed: true)]), isFalse);
    expect(unknown([]), isFalse);
  });

  test('older unknown scene cannot substitute for active scene ownership', () {
    final old = record();
    expect(unknown([record(documentId: 'another-document')]), isFalse);
    expect(
      unknown([
        old,
        record(
          chunkId: 'new-scene',
          startWord: 1,
          endWord: 2,
          duration: const Duration(seconds: 2),
        ),
      ]),
      isFalse,
    );
    expect(
      unknown([old, record(chunkId: 'new-scene', startWord: 3, endWord: 4)]),
      isFalse,
    );
  });
}
