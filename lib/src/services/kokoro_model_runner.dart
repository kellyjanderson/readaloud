import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class KokoroModelRunner {
  KokoroModelRunner({required this.modelPath}) : _onnxRuntime = OnnxRuntime();

  final String modelPath;
  final OnnxRuntime _onnxRuntime;

  OrtSession? _session;

  Future<void> initialize() async {
    _session ??= await _onnxRuntime.createSession(modelPath);
  }

  Future<List<num>> runInference({
    required List<int> tokens,
    required Float32List voice,
    required double speed,
  }) async {
    final session = _session;
    if (session == null) {
      throw StateError('Kokoro model runner is not initialized.');
    }

    final paddedTokens = <int>[0, ...tokens, 0];
    final inputNames = session.inputNames;
    if (inputNames.length < 3) {
      throw StateError(
        'Kokoro model is missing required inputs for text, voice, and speed.',
      );
    }

    final inputs = <String, OrtValue>{};
    if (inputNames.contains('input_ids')) {
      inputs['input_ids'] = await OrtValue.fromList(
        Int64List.fromList(paddedTokens),
        <int>[1, paddedTokens.length],
      );
      inputs['style'] = await OrtValue.fromList(voice.toList(), <int>[
        1,
        voice.length,
      ]);
      inputs['speed'] = await OrtValue.fromList(
        <double>[speed],
        const <int>[1],
      );
    } else {
      inputs[inputNames[0]] = await OrtValue.fromList(
        Int64List.fromList(paddedTokens),
        <int>[1, paddedTokens.length],
      );
      inputs[inputNames[1]] = await OrtValue.fromList(voice.toList(), <int>[
        1,
        voice.length,
      ]);
      inputs[inputNames[2]] = await OrtValue.fromList(
        <double>[speed],
        const <int>[1],
      );
    }

    final outputs = await session.run(inputs);
    if (outputs.isEmpty) {
      throw StateError('Kokoro returned no audio output.');
    }

    final outputName = session.outputNames.first;
    final outputValue = outputs[outputName];
    if (outputValue == null) {
      throw StateError('Kokoro output tensor is missing.');
    }

    final rawValues = await outputValue.asList();
    return Float32List.fromList(
      rawValues.map((value) => (value as num).toDouble()).toList(),
    );
  }

  Future<void> dispose() async {
    // flutter_onnxruntime 1.6.3 is currently unstable on macOS when closing
    // sessions from this worker-driven path. Let process teardown reclaim the
    // session there rather than aborting the app in native plugin code.
    if (!Platform.isMacOS) {
      await _session?.close();
    }
    _session = null;
  }
}
