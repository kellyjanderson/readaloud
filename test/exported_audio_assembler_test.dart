import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/exported_audio_assembler.dart';

void main() {
  test(
    'assembles ordered chunk wav files into one export with sidecar',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'read-aloud-export-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final chunkA = File('${tempDir.path}/chunk_a.wav');
      final chunkB = File('${tempDir.path}/chunk_b.wav');
      await chunkA.writeAsBytes(_buildWav(<int>[100, 200, 300]));
      await chunkB.writeAsBytes(_buildWav(<int>[400, 500]));

      final assembler = const ExportedAudioAssembler();
      final result = await assembler.assemble(
        ExportedAudioAssemblyRequest(
          outputPath: '${tempDir.path}/export.wav',
          engineId: 'kokoro',
          engineVersion: '2',
          documentId: 'doc-1',
          documentTitle: 'Document One',
          sourceDescription: 'Test import',
          voiceId: 'af_bella',
          rate: 1.0,
          normalizationVersion: 'norm-v1',
          chunks: <ExportedAudioChunk>[
            ExportedAudioChunk(
              chunkId: 'chunk-a',
              cacheKey: 'cache-a',
              audioPath: chunkA.path,
              duration: const Duration(milliseconds: 300),
              segmentIds: const <String>['segment-a'],
              startWordIndex: 0,
              endWordIndex: 3,
              voiceId: 'af_bella',
              routeId: 'route_narrator_open',
              castId: 'cast_narrator',
              capabilityProfileId: 'kokoro:macos:v1',
              boundaryMetadata: const ExportedBoundaryMetadata(
                boundaryClass: 'sentence',
                correctionApplied: true,
                leadingSilenceBefore: Duration(milliseconds: 120),
                leadingSilenceAfter: Duration(milliseconds: 40),
                trailingSilenceBefore: Duration(milliseconds: 60),
                trailingSilenceAfter: Duration(milliseconds: 60),
                joinSilenceBefore: Duration(milliseconds: 120),
                joinSilenceAfter: Duration(milliseconds: 40),
                isInitialChunk: true,
                isResumedChunk: false,
              ),
              pronunciationArtifacts: const <ExportedPronunciationArtifact>[
                ExportedPronunciationArtifact(
                  artifactId: 'art-a',
                  segmentId: 'segment-a',
                  startWord: 0,
                  endWord: 1,
                  resolutionClass: 'direct_resolved',
                  translationIntent: 'phoneme_string',
                  translationOutcome: 'deferred',
                  representationType: 'phoneme_string',
                  representationValue: 'ˈɛliət',
                  diagnosticCodes: <String>['pronunciation.resolved.lexicon'],
                ),
              ],
            ),
            ExportedAudioChunk(
              chunkId: 'chunk-b',
              cacheKey: 'cache-b',
              audioPath: chunkB.path,
              duration: const Duration(milliseconds: 200),
              segmentIds: const <String>['segment-b'],
              startWordIndex: 3,
              endWordIndex: 5,
              voiceId: 'bf_emma',
              routeId: 'route_dialogue_jennifer',
              castId: 'cast_character_jennifer',
              dialogueSpanId: 'dlg_s_1',
              missingFallbackWordCount: 2,
            ),
          ],
        ),
      );

      final outputFile = File(result.outputPath);
      final sidecarFile = File(result.sidecarPath);
      expect(await outputFile.exists(), isTrue);
      expect(await sidecarFile.exists(), isTrue);
      expect(result.chunkCount, 2);
      expect(result.duration, const Duration(milliseconds: 500));

      final sidecar = jsonDecode(await sidecarFile.readAsString()) as Map;
      expect(sidecar['voiceId'], 'af_bella');
      expect(sidecar['chunkCount'], 2);
      expect((sidecar['chunks'] as List).length, 2);
      expect(
        (sidecar['pronunciationSummary'] as Map)['totalPronunciationArtifacts'],
        1,
      );
      expect(
        (sidecar['pronunciationSummary'] as Map)['deferredEngineTranslations'],
        1,
      );
      expect(
        (sidecar['pronunciationSummary']
            as Map)['missingArtifactFallbackWords'],
        2,
      );
      final firstChunk = (sidecar['chunks'] as List).first as Map;
      expect(firstChunk['voiceId'], 'af_bella');
      expect(firstChunk['routeId'], 'route_narrator_open');
      expect(firstChunk['castId'], 'cast_narrator');
      expect(firstChunk['capabilityProfileId'], 'kokoro:macos:v1');
      expect(firstChunk['missingFallbackWordCount'], 0);
      final boundaryMetadata = firstChunk['boundaryMetadata'] as Map;
      expect(boundaryMetadata['boundaryClass'], 'sentence');
      expect(boundaryMetadata['correctionApplied'], isTrue);
      expect(boundaryMetadata['leadingSilenceAfterMs'], 40);
      expect(boundaryMetadata['isInitialChunk'], isTrue);
      final firstArtifact =
          (firstChunk['pronunciationArtifacts'] as List).first as Map;
      expect(firstArtifact['translationOutcome'], 'deferred');
      final secondChunk = (sidecar['chunks'] as List).last as Map;
      expect(secondChunk['voiceId'], 'bf_emma');
      expect(secondChunk['dialogueSpanId'], 'dlg_s_1');
      expect(await outputFile.length(), greaterThan(44));
    },
  );
}

Uint8List _buildWav(List<int> samples) {
  final pcm = Int16List.fromList(samples);
  final output = BytesBuilder(copy: false);

  void writeAscii(String text) => output.add(ascii.encode(text));
  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  writeAscii('RIFF');
  writeUint32(36 + pcm.lengthInBytes);
  writeAscii('WAVE');
  writeAscii('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(1);
  writeUint32(24000);
  writeUint32(24000 * 2);
  writeUint16(2);
  writeUint16(16);
  writeAscii('data');
  writeUint32(pcm.lengthInBytes);
  output.add(pcm.buffer.asUint8List());

  return output.takeBytes();
}
