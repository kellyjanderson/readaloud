// Native app smoke: real UI, controller, inference and audio player.
// Build with FLUTTER_TARGET=tools/mlx_playback_smoke.dart; args: ENGINE RECEIPT.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/app.dart';
import 'package:read_aloud/src/controllers/reader_controller.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';
import 'package:read_aloud/src/models/spoken_chunk_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmokeController extends ReaderController {
  SmokeController(KokoroTtsEngine engine)
    : super(ttsEngine: engine, enablePlatformIntakeChannels: false);
  Future<void>? _initialization;
  @override
  Future<void> initialize() => _initialization ??= super.initialize();
  @override
  Future<bool> restoreLastOpenedDocument() async => false;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // This native test must not overwrite the user's saved reader preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  if (args.length != 2) exit(2);
  final player = AudioPlayer(useLazyPreparation: false);
  final bits =
      int.tryParse(
        Platform.environment['READALOUD_SMOKE_QUANTIZATION_BITS'] ?? '0',
      ) ??
      0;
  final engine = KokoroTtsEngine(
    player: player,
    engineId: args[0],
    mlxQuantizationBits: bits,
    mlxModelPath: Platform.environment['READALOUD_MLX_TTS_MODEL_PATH'],
    mlxPythonPath: Platform.environment['READALOUD_MLX_PYTHON'],
  );
  final controller = SmokeController(engine);
  final paths = <String>{};
  final subscription = player.sequenceStream.listen((sequence) {
    for (final source in sequence) {
      if (source is UriAudioSource && source.uri.scheme == 'file') {
        paths.add(source.uri.toFilePath());
      }
    }
  });
  final watch = Stopwatch()..start();
  final receipt = <String, Object?>{
    'engine': args[0],
    'bits': bits,
    'passed': false,
  };
  int? preparationCompleteMs;
  void observePreparation() {
    if (controller.preparedRanges.isNotEmpty &&
        controller.isPreparationComplete &&
        preparationCompleteMs == null) {
      preparationCompleteMs = watch.elapsedMilliseconds;
    }
  }

  controller.addListener(observePreparation);
  var passed = false;
  runApp(ReadAloudApp(controller: controller));
  try {
    await controller.initialize();
    receipt['startupError'] = controller.startupError;
    final multiVoice =
        Platform.environment['READALOUD_SMOKE_MULTI_VOICE'] == '1';
    if (multiVoice) await controller.setMultiVoiceEnabled(true);
    receipt['multiVoice'] = multiVoice;
    final selectedVoice = Platform.environment['READALOUD_SMOKE_VOICE_ID'];
    if (selectedVoice != null) {
      if (!controller.voices.any((voice) => voice.id == selectedVoice)) {
        throw StateError(
          'Requested smoke voice is absent: $selectedVoice; '
          'startup=${controller.startupError}; voices=${controller.voices.map((v) => v.id).toList()}',
        );
      }
      await controller.selectVoiceById(selectedVoice);
    }
    receipt['selectedVoice'] = controller.selectedVoice?.id;
    receipt['voiceCount'] = controller.voices.length;
    receipt['voiceIds'] = controller.voices.map((v) => v.id).toList();
    if (args[0].startsWith('fish_drama3') && controller.voices.length < 5) {
      throw StateError('Fewer than five selectable voices per character.');
    }
    final documentPath = Platform.environment['READALOUD_SMOKE_DOCUMENT_PATH'];
    final requireCompleteDocument =
        Platform.environment['READALOUD_SMOKE_REQUIRE_COMPLETE_DOCUMENT'] ==
        '1';
    receipt['requireCompleteDocument'] = requireCompleteDocument;
    if (documentPath != null) {
      await controller.importFilePaths([documentPath]);
    } else {
      await controller.importPastedText(
        Platform.environment['READALOUD_SMOKE_TEXT'] ??
            'The little red boat crossed the quiet lake. '
                'Anna waved from the shore. "Come back soon," she called. '
                '"I will," Ben replied. The sun shone on the water.',
      );
    }
    receipt['documentWords'] = controller.document.wordCount;
    receipt['characters'] = controller.document.characterCastRegistry.entries
        .map((entry) => entry.castId)
        .toList();
    final initialCast = {
      for (final entry in controller.characterCastRegistry.characterEntries)
        entry.castId: {
          'gender': entry.inferredGender?.name,
          'voice': controller.castVoiceAssignments
              ?.forCastId(entry.castId)
              ?.effectiveVoiceId,
        },
    };
    receipt['initialCast'] = initialCast;
    unawaited(controller.startPlayback());
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    var advanced = false;
    while (DateTime.now().isBefore(deadline)) {
      if (controller.startupError != null ||
          (controller.statusMessage?.contains('Speech resources unavailable') ??
              false) ||
          controller.playbackState == ReaderPlaybackPrimaryState.failed ||
          (controller.statusMessage?.contains('failed') ?? false)) {
        throw StateError(
          controller.startupError ??
              controller.statusMessage ??
              'Playback failed',
        );
      }
      if (player.playing && player.position.inMilliseconds >= 500) {
        advanced = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!advanced) {
      throw StateError(
        'Native playback did not advance: ${controller.statusMessage}',
      );
    }
    receipt['positionMs'] = player.position.inMilliseconds;
    receipt['elapsedMs'] = watch.elapsedMilliseconds;
    receipt['preparedRanges'] = controller.preparedRanges.length;
    receipt['preparedWords'] = controller.preparedRanges.fold<int>(
      0,
      (sum, range) => sum + range.fragment.wordCount,
    );
    final soakSeconds =
        int.tryParse(
          Platform.environment['READALOUD_SMOKE_PLAY_SECONDS'] ?? '0',
        ) ??
        0;
    final soakEnd = watch.elapsedMilliseconds + soakSeconds * 1000;
    var lastPosition = player.position;
    var lastIndex = player.currentIndex;
    var lastAdvance = watch.elapsedMilliseconds;
    var maxStallMs = 0;
    while (watch.elapsedMilliseconds < soakEnd) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (player.position != lastPosition || player.currentIndex != lastIndex) {
        lastPosition = player.position;
        lastIndex = player.currentIndex;
        lastAdvance = watch.elapsedMilliseconds;
      } else {
        maxStallMs = math.max(
          maxStallMs,
          watch.elapsedMilliseconds - lastAdvance,
        );
      }
      if (controller.statusMessage?.contains('failed') ?? false) {
        throw StateError('${controller.statusMessage}');
      }
    }
    receipt['soakSeconds'] = soakSeconds;
    receipt['playbackState'] = controller.playbackState.name;
    receipt['cast'] = controller.characterCastRegistry.characterEntries.map((
      entry,
    ) {
      final assignment = controller.castVoiceAssignments?.forCastId(
        entry.castId,
      );
      final voice = controller.voices
          .where((voice) => voice.id == assignment?.effectiveVoiceId)
          .firstOrNull;
      return {
        'castId': entry.castId,
        'genderEvidence': entry.inferredGender?.name,
        'voiceId': voice?.id,
        'voiceGender': voice?.gender?.name,
        'decision': assignment?.decisionKind.name,
      };
    }).toList();
    receipt['spokenChunks'] = controller.spokenChunkRecords
        .map(
          (chunk) => {
            'castId': chunk.castId,
            'voiceId': chunk.voiceId,
            'startWord': chunk.startWordIndex,
            'endWord': chunk.endWordIndex,
            'completed': chunk.completed,
            'audioDurationMs': chunk.audioDuration.inMilliseconds,
          },
        )
        .toList();
    if (multiVoice) {
      final mismatches = (receipt['cast']! as List).where(
        (entry) =>
            entry['genderEvidence'] != null &&
            entry['genderEvidence'] != 'neutral' &&
            entry['genderEvidence'] != entry['voiceGender'],
      );
      if (mismatches.isNotEmpty) {
        throw StateError('Automatic voice gender mismatch: $mismatches');
      }
      for (final entry in (receipt['cast']! as List)) {
        final before = initialCast[entry['castId']];
        if (before != null &&
            before['gender'] != null &&
            before['gender'] == entry['genderEvidence'] &&
            before['voice'] != entry['voiceId']) {
          throw StateError(
            'Unchanged character evidence reassigned its voice: ${entry['castId']}',
          );
        }
      }
    }
    receipt['preparationCompleteMs'] = preparationCompleteMs;
    receipt['preparationStages'] = controller.preparationProgress.map(
      (stage, value) => MapEntry(stage.name, {
        'state': value.state.name,
        'completed': value.completed,
        'total': value.total,
        'error': value.error,
      }),
    );
    receipt['documentPreparationComplete'] = controller.isPreparationComplete;
    // Long documents intentionally stop at the bounded prepared-range window.
    // Full-document timing is a separate, explicitly requested probe contract.
    if (requireCompleteDocument && preparationCompleteMs == null) {
      throw StateError(
        'Preparation did not finish: ${controller.statusMessage}',
      );
    }
    if (requireCompleteDocument &&
        (preparationCompleteMs == null || preparationCompleteMs! > 5000)) {
      throw StateError(
        'Small document preparation exceeded five seconds: $preparationCompleteMs ms',
      );
    }
    receipt['maxNativeStallMs'] = maxStallMs;
    if (paths.isEmpty) throw StateError('No native audio source');
    // just_audio consumes the canonical PCM16 WAV emitted by the pipeline.
    var peak = 0;
    final sampleRates = <int>{};
    for (final path in paths) {
      if (!await File(path).exists()) continue;
      final bytes = await File(path).readAsBytes();
      final data = ByteData.sublistView(bytes);
      sampleRates.add(data.getUint32(24, Endian.little));
      var offset = 12;
      while (offset + 8 <= bytes.length) {
        final size = data.getUint32(offset + 4, Endian.little);
        final tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        if (tag == 'data') {
          for (
            var i = offset + 8;
            i + 1 < math.min(bytes.length, offset + 8 + size);
            i += 2
          ) {
            peak = math.max(peak, data.getInt16(i, Endian.little).abs());
          }
          break;
        }
        offset += 8 + size + (size % 2);
      }
    }
    if (peak < 100) {
      throw StateError('Emitted audio is silent or nearly silent: peak=$peak');
    }
    receipt.addAll({
      'passed': true,
      'peakPcm16': peak,
      'audioPaths': paths.toList(),
      'sampleRates': sampleRates.toList(),
    });
    if (args[0].startsWith('fish_drama3') && !sampleRates.contains(44100)) {
      throw StateError('Drama did not reach playback at native 44.1 kHz.');
    }
    if (soakSeconds > 0 && maxStallMs > 1000) {
      throw StateError('Native playback stalled for $maxStallMs ms');
    }
    passed = true;
  } catch (error, stack) {
    receipt.addAll({'passed': false, 'error': '$error', 'stack': '$stack'});
  } finally {
    receipt['audioPaths'] = paths.toList();
    receipt['tracePath'] = controller.ttsDebugTraceLogPath;
    await controller.pausePlayback();
    await engine.shutdownResources();
    await controller.shutdownPreparation();
    await subscription.cancel();
    controller.removeListener(observePreparation);
    controller.dispose();
    final file = File(args[1]);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
    );
    exit(passed ? 0 : 1);
  }
}
