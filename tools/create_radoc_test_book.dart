// Fixture transport only: preserve an existing exported scene's actual WAV and
// native turn evidence. No synthesis or inference occurs in this builder.
// READALOUD_S6_FIXTURE_SOURCE/EXPORT/OUTPUT; run with tools/flutter test this file.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/radoc_audio_manifest.dart';
import 'package:read_aloud/src/services/audio_artifact_store.dart';
import 'package:read_aloud/src/services/document_import_service.dart';
import 'package:read_aloud/src/services/radoc_audio_package.dart';
import 'package:read_aloud/src/services/reader_document_serialization_service.dart';

void main() {
  test('package previously emitted scene without model access', () async {
    final source = Platform.environment['READALOUD_S6_FIXTURE_SOURCE']!;
    final exported = Platform.environment['READALOUD_S6_FIXTURE_EXPORT']!;
    final output = Platform.environment['READALOUD_S6_FIXTURE_OUTPUT']!;
    final document = DocumentImportService().importPastedText(
      await File(source).readAsString(),
    );
    final evidence =
        jsonDecode(await File(exported).readAsString()) as Map<String, dynamic>;
    final chunk = (evidence['chunks'] as List).single as Map<String, dynamic>;
    expect(chunk['startWordIndex'], 0);
    expect(chunk['endWordIndex'], document.wordCount);
    final temp = await Directory.systemTemp.createTemp('radoc-fixture-');
    final package = RadocAudioPackage();
    try {
      final prepared = await const ReaderDocumentSerializationService()
          .writeToFile(
            document: document,
            outputPath: '${temp.path}/source.json',
          );
      final wav = File(evidence['outputPath'] as String);
      final format = AudioArtifactStore.validateWav(await wav.readAsBytes());
      final turns = chunk['sceneTurns'] as List;
      final voiceIds = turns.map((t) => (t as Map)['voice'] as String).toSet();
      final dependencies = <String, dynamic>{
        'legacyExportCacheKey': chunk['cacheKey'],
        'text': document.speakableText,
        'engineId': evidence['engineId'],
        'engineVersion': evidence['engineVersion'],
        'rate': evidence['rate'],
        'capturedTurns': turns,
      };
      await package.export(
        destination: File(output),
        manifest: RadocAudioManifest(
          documentId: document.displayDocument.documentId,
          sourceId: document.normalizedImportResult.sourceFingerprint,
          preparationComplete: true,
          totalWords: document.wordCount,
          preparedRanges: [
            RadocPreparedRange(
              member: 'prepared/1.json',
              startWord: 0,
              endWord: document.wordCount,
            ),
          ],
          analysisMembers: [],
          scenes: [
            RadocAudioScene(
              sceneId: 'accepted-scene',
              startWord: 0,
              endWord: document.wordCount,
              audioMember: 'audio/scene.wav',
              dependencyDigest: artifactIdentity(dependencies),
              dependencies: dependencies,
              provenance: {
                'text': document.speakableText,
                'startOffset': 0,
                'sceneTurns': turns,
                'legacyExport': true,
                'rawBoundaryEvidence': 'unavailable',
              },
              sampleRate: format.sampleRate,
              channels: 1,
              frameCount: format.frames,
            ),
          ],
          intent: {
            'defaultVoiceId': evidence['voiceId'],
            'multiVoice': true,
            'rate': evidence['rate'],
            'engineId': evidence['engineId'],
            'voices': [
              for (final id in voiceIds)
                {'id': id, 'label': id, 'locale': 'en-US'},
            ],
          },
        ),
        members: {'prepared/1.json': prepared, 'audio/scene.wav': wav},
      );
    } finally {
      await package.dispose();
      await temp.delete(recursive: true);
    }
  });
}
