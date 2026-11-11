#!/usr/bin/env python3
"""Strict SHORT S7 cached A/B/A and online double-Cancel/retry acoustic proof.

Usage: analyze_s7_switches.py RUN_DIRECTORY NEW_OUTPUT.json
Requires complete non-silent queued waveforms totaling >=1s per 3s segment,
correlation >=.98, external packet joins <=10ms, and quiet guarded gaps between
manual Plays and after final Pause. Never substitutes for the sustained 50s gate.
Copied reference digests/queue order establish identity; player snapshots are
non-atomic search hints. Final interrupted WAV and prepared tails are explicit.
No transcript, voice quality, human listening, memory, startup or M3 acceptance.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly

from analyze_s7_variants import (MAX_CAPTURE_BYTES, MAX_REFERENCE_BYTES,
                                 THRESHOLD, MAX_GAP_MS, finite, load_json, match,
                                 read_audio, require, resample, runtime_gates,
                                 source_path)

MIN_COMPLETE_SECONDS = 1.0
QUIET_PEAK = .001
GUARD_SECONDS = .25
MIN_FINAL_QUIET_SECONDS = .75
MODES = ('cached-aba', 'online-cancel-retry')
LABELS = ('initial-A8', 'B4', 'returned-A8')
ENGINES = ('fish_drama3_8bit', 'fish_drama3_4bit', 'fish_drama3_8bit')


def switch_gates(native, runner, timing):
    require(native.get('mode') == runner.get('mode') and native.get('mode') in MODES,
            'Short switch acceptance requires cached-aba or online-cancel-retry')
    # Reuse the unchanged sustained analyzer's common runtime/cleanup gates.
    # Only its single-mode selector is irrelevant here; actual route identity is
    # checked above and below. No acoustic or duration gate is borrowed/relaxed.
    runtime_gates(dict(native, mode='cached-8bit'), dict(runner, mode='cached-8bit'), timing)
    require(native.get('offline') is (native['mode'] == 'cached-aba')
            and native.get('managedModelPathOverride') is False,
            'Requires normal managed engine acquisition and declared network mode')
    require([s.get('label') for s in native.get('segments', [])] == list(LABELS)
            and [s.get('engineId') for s in native['segments']] == list(ENGINES),
            'Requires ordered initial A8, B4, returned A8 playback')
    indices = [s.get('engineIndex') for s in native['segments']]
    require(all(isinstance(i, int) and not isinstance(i, bool) and i >= 0 for i in indices)
            and indices[0] < indices[1] < indices[2], 'Invalid engine lifetime order')
    require(isinstance(native.get('retainedAnchor'), int) and native['retainedAnchor'] > 0
            and native.get('returnAnchor') == native['retainedAnchor'], 'Missing retained return anchor')
    if native['mode'] == 'cached-aba':
        require(native.get('rapidLatestSelectionValidated') is True,
                'Rapid latest-selection route not validated')
    else:
        for field in ('doubleCancelValidated', 'downloadRetiredWithoutLateActivation', 'retryValidated'):
            require(native.get(field) is True, f'Online route gate failed: {field}')
        baseline = finite(native.get('downloadBaselineBytes'), 'download baseline')
        event = native.get('downloadInterruptedAt', {})
        progress = event.get('resourceProgress', {})
        require(event.get('event') == 'download-interruption'
                and progress.get('unit') == 'bytes'
                and 'download' in str(progress.get('stage', '')).lower()
                and 0 <= baseline < finite(progress.get('completed'), 'download completed bytes'),
                'No actual advancing download before cancellation')


def verify_references(queued):
    paths = [q.get('sourcePath') for q in queued]
    require(all(isinstance(p, str) and p for p in paths) and len(set(paths)) == len(paths),
            'Missing/duplicate queued source identity')
    references = []
    total_bytes = total_seconds = 0
    for row in queued:
        finite(row.get('queuedUnixMicros'), 'queue time')
        ref = row.get('reference', {})
        path = Path(ref.get('path', ''))
        require(path.is_file(), 'Missing copied queued reference')
        size = path.stat().st_size
        total_bytes += size
        require(size == ref.get('bytes') and size <= MAX_REFERENCE_BYTES
                and total_bytes <= 512_000_000, 'Reference byte count/bound mismatch')
        require(hashlib.sha256(path.read_bytes()).hexdigest() == ref.get('sha256'),
                'Reference SHA256 mismatch')
        source_rate, source, channels, bits = read_audio(path, MAX_REFERENCE_BYTES, 120)
        require(source_rate == ref.get('sampleRate') and channels == ref.get('channels')
                and bits == ref.get('bitsPerSample'), 'Reference format metadata mismatch')
        total_seconds += len(source) / source_rate
        require(total_seconds <= 600, 'Total queued duration bound')
        references.append((source_rate, source))
    return paths, references


def quiet_interval(captured, rate, start, finish, label, minimum=0.):
    require(0 <= start < finish <= len(captured) / rate and finish - start >= minimum - 1e-6,
            f'Insufficient bounded quiet capture: {label}')
    a, b = math.ceil(start * rate), math.floor(finish * rate)
    require(a < b, f'Empty quiet capture: {label}')
    peak = float(np.max(np.abs(captured[a:b])))
    require(peak <= QUIET_PEAK, f'Unexpected speech/signal in quiet interval {label}: peak={peak:.6f}')
    return {'label': label, 'startSeconds': start, 'endSeconds': finish,
            'durationSeconds': finish - start, 'capturedPeak': peak, 'passed': True}


def analyze_segment(segment, queued, references, samples, captured, rate, origin):
    report = {'label': segment['label'], 'matches': [], 'excludedFinalWaveform': None,
              'completeReferenceSeconds': 0., 'encodedSilentPackets': [], 'errors': []}
    play = finite(segment.get('playRequestedUnixMicros'), 'Play request')
    first = finite(segment.get('firstPositionUnixMicros'), 'first movement')
    pause = finite(segment.get('pauseRequestedUnixMicros'), 'Pause request')
    returned = finite(segment.get('pauseReturnedUnixMicros'), 'Pause completion')
    require(segment.get('requiredWallPlaybackMs') == 3000 and play <= first < pause
            and pause - first >= 2_990_000 and pause <= returned <= pause + 10_000_000,
            'Requires observed 3s playback and completed Pause')
    require(segment.get('terminal') is None
            and finite(segment.get('observedPositionAdvanceMs'), 'position advance') >= 2550
            and segment.get('positionEvidence', {}).get('overflow') is False,
            'Insufficient native player progress')
    low_time, stop = (play - origin) / 1e6, (pause - origin) / 1e6
    require(0 <= low_time < stop <= len(captured) / rate, 'Capture misses playback interval')
    engine = segment['engineIndex']
    scoped = [(i, q, ref) for i, (q, ref) in enumerate(zip(queued, references))
              if q.get('engineIndex') == engine]
    require(scoped and all(q.get('engineId') == segment['engineId'] for _, q, _ in scoped),
            'Missing or mismatched engine queue')
    paths = [q['sourcePath'] for _, q, _ in scoped]
    observations = [s for s in samples if s.get('engineIndex') == engine and s.get('playing') is True
                    and play <= finite(s.get('unixMicros'), 'sample time') <= pause
                    and s.get('source') is not None]
    by_path = {}
    observed_order = []
    for sample in observations:
        path = source_path(sample['source'])
        require(path in paths and finite(sample.get('positionMs'), 'position') >= 0,
                'Native source absent from engine queue or negative position')
        by_path.setdefault(path, []).append(sample)
        if not observed_order or observed_order[-1] != path:
            observed_order.append(path)
    require(observations, 'No native source observations')
    indices = [paths.index(path) for path in observed_order]
    report['playerSnapshotOrderAnomalies'] = [
        {'fromScopedIndex': a, 'toScopedIndex': b}
        for a, b in zip(indices, indices[1:]) if a >= b]
    after_pause = [s for s in samples if s.get('engineIndex') == engine
                   and pause <= finite(s.get('unixMicros'), 'sample time') <= min(returned, pause + 250_000)
                   and s.get('source') is not None and finite(s.get('positionMs'), 'position') > 0]
    witness = after_pause[0] if after_pause else observations[-1]
    require(abs(witness['unixMicros'] - pause) <= 250_000, 'No source witness within 250ms of Pause')
    final_path = source_path(witness['source'])
    require(final_path in paths, 'Pause source absent from engine queue')
    final_index = paths.index(final_path)
    report['pauseSourceWitness'] = {'queueIndex': scoped[final_index][0], 'sample': witness}
    report['preparedTailOutsidePlaybackInterval'] = [
        {'queueIndex': i, 'sourcePath': q['sourcePath'], 'reference': q['reference']}
        for i, q, _ in scoped[final_index + 1:]]
    require(all(q['queuedUnixMicros'] <= pause for _, q, _ in scoped[:final_index + 1]),
            'Emitted reference queued after Pause')
    comparison_rate = rate * 4
    previous_end = None
    pending_silent_seconds = 0.
    pending_silent_packets = []
    for number, (global_index, row, (source_rate, pcm)) in enumerate(scoped[:final_index + 1]):
        source = resample(pcm, source_rate, comparison_rate)
        duration = len(pcm) / source_rate
        active = np.flatnonzero(np.abs(source) > .01)
        if not len(active):
            record = {'queueIndex': global_index, 'sourcePath': row['sourcePath'],
                      'durationSeconds': duration, 'reference': row['reference'],
                      'scope': 'Source-encoded silence; no waveform identity or coverage credit'}
            report['encodedSilentPackets'].append(record)
            pending_silent_packets.append(record)
            pending_silent_seconds += duration
            continue
        start, end = int(active[0]), int(active[-1]) + 1
        seen = by_path.get(row['sourcePath'], [])
        estimates = [(s['unixMicros'] - origin) / 1e6 - s['positionMs'] / 1000 for s in seen]
        ordered_end = None if previous_end is None else previous_end + pending_silent_seconds
        expected = float(np.median(estimates)) if estimates else ordered_end
        require(expected is not None, 'Initial source has no native playback observation')
        low = max(low_time, expected - 1.)
        high = min(stop, expected + duration + 1.)
        if ordered_end is not None:
            low = max(low, ordered_end - .05)
            high = min(high, ordered_end + duration + 2.)
        base = max(0, math.floor(low * rate))
        finish = min(len(captured), math.ceil(high * rate))
        window = resample_poly(captured[base:finish], 4, 1)
        index, score = (None, 0.) if len(window) < end - start else match(window, source[start:end])
        actual = None if index is None else base / rate + (index - start) / comparison_rate
        complete = actual is not None and actual >= low_time - .01 and actual + duration <= stop + .001
        if not complete:
            final_start = ordered_end if ordered_end is not None else expected
            interrupted = (number == final_index and final_start < stop
                           and final_start + duration > stop + .001
                           and ((seen and row['sourcePath'] == final_path)
                                or (not seen and ordered_end is not None and 0 <= stop - ordered_end <= .25)))
            require(interrupted, f'No complete ordered waveform #{global_index + 1}; best={score:.6f}')
            report['excludedFinalWaveform'] = {
                'queueIndex': global_index, 'sourcePath': row['sourcePath'], 'reference': row['reference'],
                'durationSeconds': duration, 'observedByPlayer': bool(seen), 'expectedStartSeconds': expected,
                'reason': 'Final queued WAV interrupted by Pause; no partial waveform acceptance'}
            continue
        gap = None if ordered_end is None else (actual - ordered_end) * 1000
        record = {'queueIndex': global_index, 'sourcePath': row['sourcePath'], 'reference': row['reference'],
                  'captureStartSeconds': actual, 'captureEndSeconds': actual + duration,
                  'fullActiveCorrelation': score, 'activeComparisonFrames': end - start,
                  'sourceDurationSeconds': duration, 'externalGapBeforeMs': gap,
                  'encodedSilentSecondsBefore': pending_silent_seconds}
        report['matches'].append(record)
        silent_start = previous_end if previous_end is not None else actual - pending_silent_seconds
        for silent in pending_silent_packets:
            silent_end = silent_start + silent['durationSeconds']
            a = max(0, math.ceil((silent_start + .01) * rate))
            b = min(len(captured), math.floor((silent_end - .01) * rate))
            require(a < b and silent_start >= low_time - .01 and silent_end <= stop,
                    'Silent packet lacks bounded captured interval')
            silent.update(captureStartSeconds=silent_start, captureEndSeconds=silent_end,
                          interiorCapturedPeak=float(np.max(np.abs(captured[a:b]))))
            require(silent['interiorCapturedPeak'] <= .01,
                    'Unexpected captured signal in source-encoded silent packet')
            silent_start = silent_end
        require(gap is None or abs(gap) <= MAX_GAP_MS,
                f'External join #{global_index}: {gap:.3f}ms exceeds 10ms' if gap is not None else '')
        report['completeReferenceSeconds'] += duration
        previous_end = actual + duration
        pending_silent_seconds = 0.
        pending_silent_packets = []
    require(pending_silent_seconds == 0., 'Unanchored silent tail cannot prove complete end/continuity')
    require(report['completeReferenceSeconds'] >= MIN_COMPLETE_SECONDS,
            'Insufficient full-waveform coverage: requires >=1s per short segment')
    require(report['excludedFinalWaveform'] is not None
            or 0 <= stop - previous_end <= .25, 'Final complete waveform does not reach Pause interval')
    report['maximumAbsoluteExternalJoinMs'] = max(
        (abs(m['externalGapBeforeMs']) for m in report['matches'] if m['externalGapBeforeMs'] is not None), default=0.)
    report['minimumFullActiveCorrelation'] = min(m['fullActiveCorrelation'] for m in report['matches'])
    report['passed'] = True
    return report


def analyze(directory):
    result = {'schema': 'readaloud-s7-short-switch-acoustic-v1', 'passed': False,
              'errors': [], 'segments': [], 'quietIntervals': [],
              'policy': {'scope': 'Short three-second engine-switch routes only; not sustained acceptance',
                         'minimumCompleteReferenceSecondsPerSegment': MIN_COMPLETE_SECONDS,
                         'fullActiveCorrelationMinimum': THRESHOLD,
                         'maximumAbsoluteExternalJoinMs': MAX_GAP_MS,
                         'maximumGuardedQuietPeak': QUIET_PEAK,
                         'quietEdgeGuardSeconds': GUARD_SECONDS,
                         'minimumFinalQuietSeconds': MIN_FINAL_QUIET_SECONDS},
              'limits': 'Complete copied-reference waveform identity/order and packet joins for short routes. '
                        'One final Pause-interrupted WAV per segment is excluded, never prefix-qualified. '
                        'Source-encoded silent packets have signal/aggregate timing checks between audible anchors, '
                        'no individual acoustic identity. Guards exclude 250ms at Pause and next Play. '
                        'No sustained, transcript, quality/voice, human listening, startup, memory or M3 acceptance.'}
    try:
        directory = Path(directory)
        native = load_json(directory / 'receipt.json')
        runner = load_json(directory / 'runner.json')
        timing = load_json(directory / 'capture.wav.timing.json')
        result['mode'] = native.get('mode')
        switch_gates(native, runner, timing)
        rate, captured, _, _ = read_audio(directory / 'capture.wav', MAX_CAPTURE_BYTES, 300)
        require(rate in (44100, 48000) and timing.get('sampleRate') == rate
                and timing.get('frames') == len(captured), 'Capture timing/PCM mismatch')
        origin = finite(timing.get('firstPacketReceivedUnixMicros'), 'capture origin')
        result.update(captureSampleRate=rate, comparisonSampleRate=rate * 4,
                      capturePeak=float(np.max(np.abs(captured))))
        queued, samples, segments = native.get('queuedAudio', []), native.get('playerSamples', []), native['segments']
        require(0 < len(queued) <= 2048 and 0 < len(samples) <= 2700, 'Receipt observation bounds')
        _, references = verify_references(queued)
        for segment in segments:
            result['segments'].append(analyze_segment(segment, queued, references, samples, captured, rate, origin))
        for index, segment in enumerate(segments):
            start = (segment['pauseReturnedUnixMicros'] - origin) / 1e6 + GUARD_SECONDS
            if index + 1 < len(segments):
                finish = (segments[index + 1]['playRequestedUnixMicros'] - origin) / 1e6 - GUARD_SECONDS
                label, minimum = f'{segment["label"]}-to-{segments[index + 1]["label"]}', 0.
            else:
                finish, label, minimum = len(captured) / rate, 'after-final-Pause', MIN_FINAL_QUIET_SECONDS
            result['quietIntervals'].append(quiet_interval(captured, rate, start, finish, label, minimum))
        result['passed'] = True
    except (ValueError, KeyError, TypeError, OSError) as error:
        result['errors'].append(str(error))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = analyze(args.directory)
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps({'passed': result['passed'], 'errors': result['errors']}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
