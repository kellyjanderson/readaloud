import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:crypto/crypto.dart';

import '../models/speech_annotation.dart';
import 'audio_artifact_store.dart';

class BoundaryCandidateMetadata {
  const BoundaryCandidateMetadata({
    required this.chunkId,
    required this.boundaryClass,
    required this.leadingSilence,
    required this.trailingSilence,
    required this.isInitialChunk,
    required this.isResumedChunk,
  });

  final String chunkId;
  final BreakClass boundaryClass;
  final Duration leadingSilence;
  final Duration trailingSilence;
  final bool isInitialChunk;
  final bool isResumedChunk;
}

class BoundaryCorrectionOutcome {
  const BoundaryCorrectionOutcome({
    required this.candidate,
    this.audioPath,
    required this.applied,
    required this.leadingSilenceBefore,
    required this.leadingSilenceAfter,
    required this.trailingSilenceBefore,
    required this.trailingSilenceAfter,
    required this.joinSilenceBefore,
    required this.joinSilenceAfter,
    required this.duration,
  });

  final BoundaryCandidateMetadata candidate;
  final String? audioPath;
  final bool applied;
  final Duration leadingSilenceBefore;
  final Duration leadingSilenceAfter;
  final Duration trailingSilenceBefore;
  final Duration trailingSilenceAfter;
  final Duration joinSilenceBefore;
  final Duration joinSilenceAfter;

  /// Duration of the retained PCM, after boundary correction.
  final Duration duration;
}

class SynthesisBoundaryPolicy {
  const SynthesisBoundaryPolicy();

  static const Duration pathologicalLeadingSilence = Duration(
    milliseconds: 180,
  );
  static const Duration initialOpeningCap = Duration(milliseconds: 120);
  static const Duration _minimumRetainedLeadingSilence = Duration(
    milliseconds: 20,
  );
  static const double _silenceAmplitudeThreshold = 0.008;

  Future<BoundaryCorrectionOutcome> correctWavFile({
    required String chunkId,
    required String wavFilePath,
    required BreakClass boundaryClass,
    required bool isInitialChunk,
    required bool isResumedChunk,
    Duration? previousTrailingSilence,
    String? previousArtifactIdentity,
  }) async {
    return correctWavFileSync(
      chunkId: chunkId,
      wavFilePath: wavFilePath,
      boundaryClass: boundaryClass,
      isInitialChunk: isInitialChunk,
      isResumedChunk: isResumedChunk,
      previousTrailingSilence: previousTrailingSilence,
      previousArtifactIdentity: previousArtifactIdentity,
    );
  }

  /// Publish a distinct immutable derivative; never trim a cached/queued input.
  BoundaryCorrectionOutcome correctWavFileSync({
    required String chunkId,
    required String wavFilePath,
    required BreakClass boundaryClass,
    required bool isInitialChunk,
    required bool isResumedChunk,
    Duration? previousTrailingSilence,
    String? previousArtifactIdentity,
  }) {
    final source = File(wavFilePath);
    final bytes = source.readAsBytesSync();
    AudioArtifactStore.validateWav(bytes);
    final sidecar = File(wavFilePath.replaceFirst(RegExp(r'\.wav$'), '.json'));
    final rawMetadata = sidecar.existsSync()
        ? Map<String, dynamic>.from(
            jsonDecode(sidecar.readAsStringSync()) as Map,
          )
        : <String, dynamic>{};
    final identity = artifactIdentity({
      'kind': 'boundary-v1',
      'rawPcm': sha256.convert(bytes).toString(),
      'rawIdentity': rawMetadata['artifactIdentity'],
      'policy': {
        'openingUs': initialOpeningCap.inMicroseconds,
        'pathologicalUs': pathologicalLeadingSilence.inMicroseconds,
        'minimumUs': _minimumRetainedLeadingSilence.inMicroseconds,
        'threshold': _silenceAmplitudeThreshold,
        'capsUs': {
          for (final c in BreakClass.values)
            c.name: _combinedJoinCap(c).inMicroseconds,
        },
      },
      'boundary': boundaryClass.name,
      'initial': isInitialChunk,
      'resumed': isResumedChunk,
      'previousTrailingUs': (isInitialChunk || isResumedChunk)
          ? null
          : previousTrailingSilence?.inMicroseconds,
      'previousArtifactIdentity': (isInitialChunk || isResumedChunk)
          ? null
          : previousArtifactIdentity,
    });
    final store = AudioArtifactStore(
      Directory('${source.parent.path}/boundary-derivatives'),
    );
    final hit = store.lookup(identity);
    AudioArtifact artifact;
    if (hit != null) {
      artifact = hit;
    } else {
      final stage = source.parent.createTempSync('.boundary-stage-');
      try {
        final copy = File('${stage.path}/audio.wav')..writeAsBytesSync(bytes);
        File(
          '${stage.path}/audio.json',
        ).writeAsStringSync(jsonEncode(rawMetadata));
        final corrected = _correctPrivateWavFileSync(
          chunkId: chunkId,
          wavFilePath: copy.path,
          boundaryClass: boundaryClass,
          isInitialChunk: isInitialChunk,
          isResumedChunk: isResumedChunk,
          previousTrailingSilence: previousTrailingSilence,
        );
        final metadata =
            jsonDecode(File('${stage.path}/audio.json').readAsStringSync())
                as Map<String, dynamic>;
        metadata['rawArtifactIdentity'] = rawMetadata['artifactIdentity'];
        metadata['previousArtifactIdentity'] = previousArtifactIdentity;
        metadata['durationMillis'] = corrected.duration.inMilliseconds;
        artifact = store.publish(
          identity: identity,
          wav: copy.readAsBytesSync(),
          metadata: metadata,
        );
      } finally {
        if (stage.existsSync()) stage.deleteSync(recursive: true);
      }
    }
    final m = artifact.metadata;
    Duration duration(String key) => Duration(milliseconds: m[key] as int);
    return BoundaryCorrectionOutcome(
      audioPath: artifact.audioPath,
      candidate: BoundaryCandidateMetadata(
        chunkId: chunkId,
        boundaryClass: boundaryClass,
        leadingSilence: duration('leadingSilenceBeforeMs'),
        trailingSilence: duration('trailingSilenceBeforeMs'),
        isInitialChunk: isInitialChunk,
        isResumedChunk: isResumedChunk,
      ),
      applied: m['boundaryCorrectionApplied'] as bool,
      leadingSilenceBefore: duration('leadingSilenceBeforeMs'),
      leadingSilenceAfter: duration('leadingSilenceAfterMs'),
      trailingSilenceBefore: duration('trailingSilenceBeforeMs'),
      trailingSilenceAfter: duration('trailingSilenceAfterMs'),
      joinSilenceBefore: duration('joinSilenceBeforeMs'),
      joinSilenceAfter: duration('joinSilenceAfterMs'),
      duration: artifact.duration,
    );
  }

  BoundaryCorrectionOutcome _correctPrivateWavFileSync({
    required String chunkId,
    required String wavFilePath,
    required BreakClass boundaryClass,
    required bool isInitialChunk,
    required bool isResumedChunk,
    Duration? previousTrailingSilence,
  }) {
    final wavFile = File(wavFilePath);
    if (!wavFile.existsSync()) {
      throw StateError('Boundary policy could not find $wavFilePath.');
    }

    final wavBytes = wavFile.readAsBytesSync();
    final emptyCandidate = BoundaryCandidateMetadata(
      chunkId: chunkId,
      boundaryClass: boundaryClass,
      leadingSilence: Duration.zero,
      trailingSilence: Duration.zero,
      isInitialChunk: isInitialChunk,
      isResumedChunk: isResumedChunk,
    );
    if (wavBytes.length <= 44) {
      return BoundaryCorrectionOutcome(
        candidate: emptyCandidate,
        applied: false,
        leadingSilenceBefore: Duration.zero,
        leadingSilenceAfter: Duration.zero,
        trailingSilenceBefore: Duration.zero,
        trailingSilenceAfter: Duration.zero,
        joinSilenceBefore: Duration.zero,
        joinSilenceAfter: Duration.zero,
        duration: Duration.zero,
      );
    }

    final header = Uint8List.fromList(wavBytes.sublist(0, 44));
    final pcm = Int16List.sublistView(wavBytes, 44);
    final leadingBefore = _silenceDuration(_leadingSilentSamples(pcm));
    final trailingBefore = _silenceDuration(_trailingSilentSamples(pcm));
    final candidate = BoundaryCandidateMetadata(
      chunkId: chunkId,
      boundaryClass: boundaryClass,
      leadingSilence: leadingBefore,
      trailingSilence: trailingBefore,
      isInitialChunk: isInitialChunk,
      isResumedChunk: isResumedChunk,
    );
    final previousTrailing = (isInitialChunk || isResumedChunk)
        ? Duration.zero
        : (previousTrailingSilence ?? Duration.zero);
    final joinBefore = previousTrailing + leadingBefore;
    final targetLeading = _targetLeadingSilence(
      boundaryClass: boundaryClass,
      currentLeading: leadingBefore,
      previousTrailing: previousTrailing,
      isInitialChunk: isInitialChunk,
      isResumedChunk: isResumedChunk,
    );
    final applied = targetLeading < leadingBefore;
    var retainedSampleCount = pcm.length;

    if (applied) {
      final samplesToTrim = _durationToSamples(
        leadingBefore - targetLeading,
      ).clamp(0, pcm.length);
      final trimmedPcm = Int16List.fromList(pcm.sublist(samplesToTrim));
      retainedSampleCount = trimmedPcm.length;
      // These internally generated WAVs use a canonical 44-byte PCM header.
      // Both RIFF and data sizes must describe the retained payload.
      final headerData = ByteData.sublistView(header);
      headerData.setUint32(4, 36 + trimmedPcm.lengthInBytes, Endian.little);
      headerData.setUint32(40, trimmedPcm.lengthInBytes, Endian.little);
      final rebuilt = BytesBuilder(copy: false)
        ..add(header)
        ..add(trimmedPcm.buffer.asUint8List());
      wavFile.writeAsBytesSync(rebuilt.takeBytes(), flush: true);
    }

    final leadingAfter = targetLeading;
    final trailingAfter = trailingBefore;
    final joinAfter = previousTrailing + leadingAfter;
    final outcome = BoundaryCorrectionOutcome(
      candidate: candidate,
      applied: applied,
      leadingSilenceBefore: leadingBefore,
      leadingSilenceAfter: leadingAfter,
      trailingSilenceBefore: trailingBefore,
      trailingSilenceAfter: trailingAfter,
      joinSilenceBefore: joinBefore,
      joinSilenceAfter: joinAfter,
      duration: _silenceDuration(retainedSampleCount),
    );
    _updateSidecarSync(
      wavFile,
      outcome,
      isInitialChunk,
      isResumedChunk,
      duration: outcome.duration,
    );
    return outcome;
  }

  Duration _targetLeadingSilence({
    required BreakClass boundaryClass,
    required Duration currentLeading,
    required Duration previousTrailing,
    required bool isInitialChunk,
    required bool isResumedChunk,
  }) {
    if (currentLeading <= Duration.zero) {
      return Duration.zero;
    }

    if (isInitialChunk || isResumedChunk) {
      return currentLeading <= initialOpeningCap
          ? currentLeading
          : initialOpeningCap;
    }

    final combinedCap = _combinedJoinCap(boundaryClass);
    final remainingBudget = combinedCap - previousTrailing;
    final hardLeadingCap = pathologicalLeadingSilence;
    final candidateCap = remainingBudget < hardLeadingCap
        ? remainingBudget
        : hardLeadingCap;
    final minimum = boundaryClass == BreakClass.none
        ? Duration.zero
        : _minimumRetainedLeadingSilence;
    final normalizedCap = candidateCap < minimum ? minimum : candidateCap;

    if (currentLeading <= normalizedCap) {
      return currentLeading;
    }

    return normalizedCap;
  }

  Duration _combinedJoinCap(BreakClass boundaryClass) {
    return switch (boundaryClass) {
      BreakClass.none => const Duration(milliseconds: 60),
      BreakClass.weak => const Duration(milliseconds: 120),
      BreakClass.sentence => const Duration(milliseconds: 240),
      BreakClass.paragraph => const Duration(milliseconds: 420),
      BreakClass.section => const Duration(milliseconds: 650),
    };
  }

  int _leadingSilentSamples(Int16List pcm) {
    var count = 0;
    while (count < pcm.length && _isSilent(pcm[count])) {
      count += 1;
    }
    return count;
  }

  int _trailingSilentSamples(Int16List pcm) {
    var count = 0;
    for (var index = pcm.length - 1; index >= 0; index -= 1) {
      if (!_isSilent(pcm[index])) {
        break;
      }
      count += 1;
    }
    return count;
  }

  bool _isSilent(int sample) {
    return sample.abs() / 32767.0 <= _silenceAmplitudeThreshold;
  }

  Duration _silenceDuration(int sampleCount) {
    return Duration(milliseconds: (sampleCount / sampleRate * 1000).round());
  }

  int _durationToSamples(Duration duration) {
    return (duration.inMilliseconds / 1000 * sampleRate).round();
  }

  void _updateSidecarSync(
    File wavFile,
    BoundaryCorrectionOutcome outcome,
    bool isInitialChunk,
    bool isResumedChunk, {
    required Duration duration,
  }) {
    final sidecarFile = File(
      wavFile.path.replaceFirst(RegExp(r'\.wav$'), '.json'),
    );
    if (!sidecarFile.existsSync()) {
      return;
    }

    final raw = jsonDecode(sidecarFile.readAsStringSync());
    if (raw is! Map<String, dynamic>) {
      return;
    }

    raw['chunkId'] = outcome.candidate.chunkId;
    raw['durationMillis'] = duration.inMilliseconds;
    raw['boundaryClass'] = outcome.candidate.boundaryClass.name;
    raw['boundaryCorrectionApplied'] = outcome.applied;
    raw['joinSilenceBeforeMs'] = outcome.joinSilenceBefore.inMilliseconds;
    raw['joinSilenceAfterMs'] = outcome.joinSilenceAfter.inMilliseconds;
    raw['leadingSilenceBeforeMs'] = outcome.leadingSilenceBefore.inMilliseconds;
    raw['leadingSilenceAfterMs'] = outcome.leadingSilenceAfter.inMilliseconds;
    raw['trailingSilenceBeforeMs'] =
        outcome.trailingSilenceBefore.inMilliseconds;
    raw['trailingSilenceAfterMs'] = outcome.trailingSilenceAfter.inMilliseconds;
    raw['isInitialChunk'] = isInitialChunk;
    raw['isResumedChunk'] = isResumedChunk;

    sidecarFile.writeAsStringSync(jsonEncode(raw), flush: true);
  }
}
