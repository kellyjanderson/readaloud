import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

import '../models/speech_annotation.dart';

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
    required this.applied,
    required this.leadingSilenceBefore,
    required this.leadingSilenceAfter,
    required this.trailingSilenceBefore,
    required this.trailingSilenceAfter,
    required this.joinSilenceBefore,
    required this.joinSilenceAfter,
  });

  final BoundaryCandidateMetadata candidate;
  final bool applied;
  final Duration leadingSilenceBefore;
  final Duration leadingSilenceAfter;
  final Duration trailingSilenceBefore;
  final Duration trailingSilenceAfter;
  final Duration joinSilenceBefore;
  final Duration joinSilenceAfter;
}

class SynthesisBoundaryPolicy {
  const SynthesisBoundaryPolicy();

  static const Duration pathologicalLeadingSilence = Duration(milliseconds: 180);
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
  }) async {
    return correctWavFileSync(
      chunkId: chunkId,
      wavFilePath: wavFilePath,
      boundaryClass: boundaryClass,
      isInitialChunk: isInitialChunk,
      isResumedChunk: isResumedChunk,
      previousTrailingSilence: previousTrailingSilence,
    );
  }

  BoundaryCorrectionOutcome correctWavFileSync({
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
      );
    }

    final header = Uint8List.fromList(wavBytes.sublist(0, 44));
    final pcm = Int16List.sublistView(wavBytes, 44);
    final leadingBefore = _silenceDuration(
      _leadingSilentSamples(pcm),
    );
    final trailingBefore = _silenceDuration(
      _trailingSilentSamples(pcm),
    );
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

    if (applied) {
      final samplesToTrim = _durationToSamples(
        leadingBefore - targetLeading,
      ).clamp(0, pcm.length);
      final trimmedPcm = Int16List.fromList(pcm.sublist(samplesToTrim));
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
    );
    _updateSidecarSync(wavFile, outcome, isInitialChunk, isResumedChunk);
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
    bool isResumedChunk,
  ) {
    final sidecarFile = File(
      wavFile.path.replaceFirst(RegExp(r'\.wav$'), '.json'),
    );
    if (!sidecarFile.existsSync()) {
      return;
    }

    try {
      final raw = jsonDecode(sidecarFile.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        return;
      }

      raw['chunkId'] = outcome.candidate.chunkId;
      raw['boundaryClass'] = outcome.candidate.boundaryClass.name;
      raw['boundaryCorrectionApplied'] = outcome.applied;
      raw['joinSilenceBeforeMs'] = outcome.joinSilenceBefore.inMilliseconds;
      raw['joinSilenceAfterMs'] = outcome.joinSilenceAfter.inMilliseconds;
      raw['leadingSilenceBeforeMs'] =
          outcome.leadingSilenceBefore.inMilliseconds;
      raw['leadingSilenceAfterMs'] = outcome.leadingSilenceAfter.inMilliseconds;
      raw['trailingSilenceBeforeMs'] =
          outcome.trailingSilenceBefore.inMilliseconds;
      raw['trailingSilenceAfterMs'] =
          outcome.trailingSilenceAfter.inMilliseconds;
      raw['isInitialChunk'] = isInitialChunk;
      raw['isResumedChunk'] = isResumedChunk;

      sidecarFile.writeAsStringSync(jsonEncode(raw), flush: true);
    } catch (_) {
      // Sidecar updates are best-effort; playback should not fail on them.
    }
  }
}
