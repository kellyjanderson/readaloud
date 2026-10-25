import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
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

      final assembler = ExportedAudioAssembler();
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
      expect(
        (await outputFile.readAsBytes()).sublist(44),
        Int16List.fromList([100, 200, 300, 400, 500]).buffer.asUint8List(),
      );
      expect(result.duration, const Duration(microseconds: 208));

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
  test(
    'worker scans ancillary chunks and derives exact total frames',
    () async {
      final dir = await Directory.systemTemp.createTemp('export-frames');
      addTearDown(() => dir.delete(recursive: true));
      final source = _buildWav(List<int>.generate(25, (i) => i + 1));
      // An odd-length JUNK chunk (including its pad byte) before fmt/data.
      final withJunk = Uint8List.fromList([
        ...source.sublist(0, 12),
        ...ascii.encode('JUNK'),
        1,
        0,
        0,
        0,
        77,
        0,
        ...source.sublist(12),
      ]);
      ByteData.sublistView(
        withJunk,
      ).setUint32(4, withJunk.length - 8, Endian.little);
      final input = File('${dir.path}/in.wav');
      await input.writeAsBytes(withJunk);
      final workerNames = <String?>[];
      final assembler = ExportedAudioAssembler(
        onProgress: (event) => workerNames.add(event.workerName),
      );
      addTearDown(assembler.shutdown);
      final result = await assembler.assemble(
        _request(dir, [input.path, input.path]),
      );
      expect(result.duration, const Duration(microseconds: 2083));
      final wav = await File(result.outputPath).readAsBytes();
      expect(wav.length, 44 + 100);
      expect(
        ByteData.sublistView(wav).getUint32(4, Endian.little),
        wav.length - 8,
      );
      final metadata =
          jsonDecode(await File(result.sidecarPath).readAsString()) as Map;
      expect(metadata['frameCount'], 50);
      expect(metadata['durationMillis'], 2);
      expect((metadata['chunks'] as List).map((c) => c['frameCount']), [
        25,
        25,
      ]);
      expect(workerNames, isNotEmpty);
      expect(
        workerNames.every(
          (name) =>
              name != Isolate.current.debugName &&
              name!.startsWith('audio-export-'),
        ),
        isTrue,
      );
    },
  );

  test(
    'staged cancellation preserves previous output and drains temp files',
    () async {
      final dir = await Directory.systemTemp.createTemp('export-cancel');
      addTearDown(() => dir.delete(recursive: true));
      final input = File('${dir.path}/in.wav');
      await input.writeAsBytes(_buildWav([1, 2, 3]));
      final output = File('${dir.path}/out.wav');
      final sidecar = File('${dir.path}/out.json');
      await output.writeAsString('old audio');
      await sidecar.writeAsString('old sidecar');
      var staged = false;
      late ExportedAudioAssembler assembler;
      assembler = ExportedAudioAssembler(
        onProgress: (event) {
          if (event.stage == 'staged') {
            expect(output.readAsStringSync(), 'old audio');
            expect(sidecar.readAsStringSync(), 'old sidecar');
            assembler.cancel();
            staged = true;
          }
        },
      );
      addTearDown(assembler.shutdown);
      final assertion = expectLater(
        assembler.assemble(_request(dir, [input.path])),
        throwsA(isA<ExportAssemblyCancelled>()),
      );
      await assertion;
      expect(staged, isTrue);
      await assembler.shutdown();
      expect(await output.readAsString(), 'old audio');
      expect(await sidecar.readAsString(), 'old sidecar');
      expect(await _stagingDirectories(dir), isEmpty);
    },
  );

  test(
    'single admission, immediate shutdown cancellation and closed intake',
    () async {
      final dir = await Directory.systemTemp.createTemp('export-shutdown');
      addTearDown(() => dir.delete(recursive: true));
      final input = File('${dir.path}/in.wav');
      await input.writeAsBytes(_buildWav([1, 2, 3]));
      final assembler = ExportedAudioAssembler();
      final request = _request(dir, [input.path]);
      final first = expectLater(
        assembler.assemble(request),
        throwsA(isA<ExportAssemblyCancelled>()),
      );
      final rejected = expectLater(
        assembler.assemble(request),
        throwsStateError,
      );
      final drained = assembler.shutdown();
      await rejected;
      await drained;
      await first;
      await expectLater(assembler.assemble(request), throwsStateError);
      expect(await File(request.outputPath).exists(), isFalse);
      expect(await _stagingDirectories(dir), isEmpty);
    },
  );

  test(
    'cancelled request cannot interfere with next successful request',
    () async {
      final dir = await Directory.systemTemp.createTemp('export-retry');
      addTearDown(() => dir.delete(recursive: true));
      final input = File('${dir.path}/in.wav');
      await input.writeAsBytes(_buildWav([7, 8, 9]));
      late ExportedAudioAssembler assembler;
      assembler = ExportedAudioAssembler(
        onProgress: (event) {
          if (event.requestId == 1 && event.stage == 'staged') {
            assembler.cancel();
          }
        },
      );
      addTearDown(assembler.shutdown);
      await expectLater(
        assembler.assemble(_request(dir, [input.path])),
        throwsA(isA<ExportAssemblyCancelled>()),
      );
      final result = await assembler.assemble(_request(dir, [input.path]));
      expect(
        (await File(result.outputPath).readAsBytes()).sublist(44),
        Int16List.fromList([7, 8, 9]).buffer.asUint8List(),
      );
      expect(await _stagingDirectories(dir), isEmpty);
    },
  );

  test('invalid input fails without publishing output', () async {
    final dir = await Directory.systemTemp.createTemp('export-invalid');
    addTearDown(() => dir.delete(recursive: true));
    final input = File('${dir.path}/in.wav');
    final wav = _buildWav([1, 2]);
    await input.writeAsBytes(wav.sublist(0, wav.length - 1));
    final assembler = ExportedAudioAssembler();
    addTearDown(assembler.shutdown);
    await expectLater(
      assembler.assemble(_request(dir, [input.path])),
      throwsStateError,
    );
    expect(await File('${dir.path}/out.wav').exists(), isFalse);
    expect(await File('${dir.path}/out.json').exists(), isFalse);
    expect(await _stagingDirectories(dir), isEmpty);
  });

  test('sidecar publish failure restores previous WAV', () async {
    final dir = await Directory.systemTemp.createTemp('export-rollback');
    addTearDown(() => dir.delete(recursive: true));
    final input = File('${dir.path}/in.wav');
    await input.writeAsBytes(_buildWav([1, 2]));
    final output = File('${dir.path}/out.wav');
    await output.writeAsString('original');
    await Directory('${dir.path}/out.json').create();
    final assembler = ExportedAudioAssembler();
    addTearDown(assembler.shutdown);
    await expectLater(
      assembler.assemble(_request(dir, [input.path])),
      throwsStateError,
    );
    expect(await output.readAsString(), 'original');
    expect(await _stagingDirectories(dir), isEmpty);
  });

  test(
    'streams multiple blocks in source order and never overwrites input',
    () async {
      final dir = await Directory.systemTemp.createTemp('export-blocks');
      addTearDown(() => dir.delete(recursive: true));
      final samples = List<int>.generate(80000, (index) => index % 32000);
      final input = File('${dir.path}/in.wav');
      final original = _buildWav(samples);
      await input.writeAsBytes(original);
      final assembler = ExportedAudioAssembler();
      addTearDown(assembler.shutdown);
      final result = await assembler.assemble(
        _request(dir, [input.path, input.path]),
      );
      final pcm = (await File(result.outputPath).readAsBytes()).sublist(44);
      expect(pcm, [...original.sublist(44), ...original.sublist(44)]);
      expect(await input.readAsBytes(), original);
      await expectLater(
        assembler.assemble(_request(dir, [input.path], output: input.path)),
        throwsStateError,
      );
      final alias = Directory('${dir.path}/alias');
      await alias.create();
      await expectLater(
        assembler.assemble(
          _request(dir, [input.path], output: '${alias.path}/../in.wav'),
        ),
        throwsStateError,
      );
      expect(await input.readAsBytes(), original);
    },
  );
  test('deadline cancels staging and drains before allowing reuse', () async {
    final dir = await Directory.systemTemp.createTemp('export-deadline');
    addTearDown(() => dir.delete(recursive: true));
    final input = File('${dir.path}/in.wav');
    await input.writeAsBytes(_buildWav([1, 2]));
    final assembler = ExportedAudioAssembler(timeout: Duration.zero);
    await expectLater(
      assembler.assemble(_request(dir, [input.path])),
      throwsA(isA<TimeoutException>()),
    );
    await assembler.shutdown();
    expect(await File('${dir.path}/out.wav').exists(), isFalse);
    expect(await _stagingDirectories(dir), isEmpty);
  });

  test('mismatched formats reject the entire staged export', () async {
    final dir = await Directory.systemTemp.createTemp('export-formats');
    addTearDown(() => dir.delete(recursive: true));
    final first = File('${dir.path}/first.wav');
    final second = File('${dir.path}/second.wav');
    await first.writeAsBytes(_buildWav([1, 2]));
    final differentRate = _buildWav([3, 4]);
    final header = ByteData.sublistView(differentRate);
    header.setUint32(24, 48000, Endian.little);
    header.setUint32(28, 96000, Endian.little);
    await second.writeAsBytes(differentRate);
    final assembler = ExportedAudioAssembler();
    addTearDown(assembler.shutdown);
    await expectLater(
      assembler.assemble(_request(dir, [first.path, second.path])),
      throwsStateError,
    );
    expect(await File('${dir.path}/out.wav').exists(), isFalse);
    expect(await _stagingDirectories(dir), isEmpty);
  });
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

ExportedAudioAssemblyRequest _request(
  Directory directory,
  List<String> paths, {
  String? output,
}) => ExportedAudioAssemblyRequest(
  outputPath: output ?? '${directory.path}/out.wav',
  engineId: 'kokoro',
  engineVersion: 'test',
  documentId: 'doc',
  documentTitle: 'Title',
  sourceDescription: 'test',
  voiceId: 'af_bella',
  rate: 1,
  normalizationVersion: 'v1',
  chunks: [
    for (var index = 0; index < paths.length; index++)
      ExportedAudioChunk(
        chunkId: 'chunk-$index',
        cacheKey: 'key-$index',
        audioPath: paths[index],
        duration: const Duration(seconds: 99),
        segmentIds: ['s-$index'],
        startWordIndex: index,
        endWordIndex: index + 1,
        voiceId: 'af_bella',
      ),
  ],
);

Future<List<FileSystemEntity>> _stagingDirectories(Directory directory) async =>
    directory
        .list()
        .where((entry) => entry.path.contains('.readaloud-export-'))
        .toList();
