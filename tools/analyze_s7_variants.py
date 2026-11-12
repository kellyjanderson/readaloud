#!/usr/bin/env python3
"""Strict sustained S7 emitted-waveform acceptance (managed MLX Python).

Usage: analyze_s7_variants.py RUN_DIRECTORY NEW_OUTPUT.json [--diagnostic-only]
Reads receipt.json, runner.json, capture.wav and capture.wav.timing.json. Queue
order and copied-file SHA/size are authoritative; names never establish order.
Full-reference context selects placement at correlation .98; the complete active
waveform must independently reach .98 at that same placement.
Explicit process-tap primary receipts qualify bounded warm source coverage only;
Play-to-tap is unobserved and never establishes first audio or a full session.
Only the final playback-interval WAV interrupted by Pause may be excluded,
explicitly. Prepared queue entries beyond the Pause witness remain unplayed.
This does not establish transcript/voice quality, human listening, memory or M3.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from urllib.parse import unquote, urlparse

import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate, resample_poly
from process_tap_validation import validate_process_tap

THRESHOLD = .98
MAX_GAP_MS = 10.0
MIN_COMPLETE_SECONDS = 50.0
MAX_CAPTURE_BYTES = 120_000_000
MAX_REFERENCE_BYTES = 48_000_000
MAX_JSON_BYTES = 8_000_000


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite(value, label):
    require(isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value), f'Invalid {label}')
    return value


def load_json(path):
    require(path.stat().st_size <= MAX_JSON_BYTES, f'Oversized JSON: {path}')
    def invalid(value):
        raise ValueError(f'Nonfinite JSON: {value}')
    def number(value):
        parsed = float(value)
        if not math.isfinite(parsed):
            return invalid(value)
        return parsed
    return json.loads(path.read_text(), parse_constant=invalid, parse_float=number)


def read_audio(path, maximum_bytes, maximum_seconds):
    require(44 <= path.stat().st_size <= maximum_bytes, f'Oversized/empty WAV: {path}')
    rate, raw = wavfile.read(path)
    require(isinstance(rate, int) and 8000 <= rate <= 192000, 'Unsupported sample rate')
    require(raw.ndim in (1, 2) and (raw.ndim == 1 or raw.shape[1] in (1, 2)),
            'Unsupported channel layout')
    require(0 < len(raw) <= rate * maximum_seconds, 'WAV duration bound')
    require(raw.dtype in (np.dtype('int16'), np.dtype('int32'), np.dtype('float32'),
                          np.dtype('float64')), 'Unsupported WAV PCM')
    pcm = raw.astype(np.float64)
    if np.issubdtype(raw.dtype, np.integer):
        pcm /= 2 ** (raw.dtype.itemsize * 8 - 1)
    require(np.isfinite(pcm).all() and np.max(np.abs(pcm)) <= 1.01,
            'Nonfinite/out-of-range PCM')
    if pcm.ndim == 2:
        pcm = pcm.mean(axis=1)
    return rate, pcm, 1 if raw.ndim == 1 else raw.shape[1], raw.dtype.itemsize * 8


def resample(pcm, before, after):
    divisor = math.gcd(before, after)
    return resample_poly(pcm, after // divisor, before // divisor)


def match(window, template):
    require(0 < len(template) <= len(window), 'Capture lacks complete active waveform')
    power_template = float(np.dot(template, template))
    require(math.isfinite(power_template) and power_template > len(template) * 1e-8,
            'Near-silent reference cannot establish waveform identity')
    correlations = correlate(window, template, mode='valid', method='fft')
    cumulative = np.concatenate(([0.], np.cumsum(window * window)))
    powers = cumulative[len(template):] - cumulative[:-len(template)]
    scores = np.zeros_like(correlations)
    valid = powers > max(len(template) * 1e-10, power_template * 1e-6)
    np.divide(correlations, np.sqrt(np.maximum(powers, 0) * power_template),
              out=scores, where=valid)
    require(np.isfinite(scores).all(), 'Nonfinite acoustic correlation')
    candidates = np.flatnonzero(scores >= THRESHOLD)
    if not len(candidates):
        return None, float(scores.max())
    # Earliest qualifying occurrence, then resolve its fractional phase locally.
    first = int(candidates[0])
    end = min(len(scores), first + 1920)
    index = first + int(scores[first:end].argmax())
    return index, float(scores[index])


def match_reference(window, template, active_start, active_end):
    """Select with all reference context, then score active PCM without shifting.

    A few above-threshold samples can resemble an unrelated transient. Their
    surrounding low-level PCM must establish placement before those samples
    receive identity credit. Neither joins nor native position hints select a
    correlation peak. Source-silent references are excluded by callers.
    """
    require(0 <= active_start < active_end <= len(template), 'Invalid active waveform span')
    if len(window) < len(template):
        return None, 0., 0.
    index, context_score = match(window, template)
    if index is None:
        return None, 0., context_score
    active_template = template[active_start:active_end]
    captured = window[index + active_start:index + active_end]
    denominator = math.sqrt(float(np.dot(active_template, active_template))
                            * float(np.dot(captured, captured)))
    active_score = float(np.dot(captured, active_template)) / denominator if denominator > 0 else 0.
    require(math.isfinite(active_score), 'Nonfinite fixed-placement active correlation')
    return (index if active_score >= THRESHOLD else None), active_score, context_score


def source_path(uri):
    parsed = urlparse(uri)
    require(parsed.scheme == 'file' and parsed.netloc in ('', 'localhost'),
            'Player sample is not a local source URI')
    return unquote(parsed.path)


def primary_capture_mode(native, runner, timing):
    mode = native.get('primaryCaptureMode', 'screen-capture-kit')
    require(mode in ('screen-capture-kit', 'process-tap')
            and runner.get('primaryCaptureMode', 'screen-capture-kit') == mode,
            'Primary capture mode mismatch')
    if mode == 'process-tap':
        require(native.get('ungatedProcessCaptureDiagnostic') is not True
                and runner.get('ungatedProcessCaptureDiagnostic') is not True,
                'Ungated diagnostic cannot qualify as process-tap primary')
        require(re.fullmatch('[0-9a-f]{64}', str(runner.get('primaryCaptureExecutableSha256'))) is not None,
                'Missing actual primary capture helper SHA256')
        require(isinstance(runner.get('processTapSessionID'), str), 'Missing runner tap session identity')
        validate_process_tap(timing, runner.get('pid'), timing.get('frames'),
                             timing.get('sampleRate'), runner['processTapSessionID'])
    return mode


def capture_scope(mode):
    if mode != 'process-tap':
        return {'primaryCaptureMode': mode}
    return {'primaryCaptureMode': mode, 'acceptanceScope': 'bounded warm intended-source coverage only',
            'firstEmittedAudioQualified': False, 'fullSessionQualified': False,
            'noEarlierPrefixOrReplayQualified': False, 'startupOrLoadQualified': False,
            'playToTapObservation': 'UNOBSERVED; no silence or synthesis-state inference'}


def playback_bounds(segment, origin, captured_seconds, allow_late_tap=False):
    play = finite(segment.get('playRequestedUnixMicros'), 'Play request')
    first = finite(segment.get('firstPositionUnixMicros'), 'first player movement')
    stop = (finite(segment.get('pauseRequestedUnixMicros'), 'Pause request') - origin) / 1e6
    require(origin > 0 and (origin < first if allow_late_tap else origin <= play),
            'Capture misses playback interval')
    low = max(0., (play - origin) / 1e6) if allow_late_tap else (play - origin) / 1e6
    require(0 <= low < stop <= captured_seconds, 'Capture misses playback interval')
    return low, stop


def runtime_gates(native, runner, timing, failures=None):
    def require(condition, message):
        if not condition:
            if failures is None:
                raise ValueError(message)
            failures.append(message)
    require(native.get('schema') == 'readaloud-native-variant-v1'
            and runner.get('schema') == 'readaloud-native-variant-runner-v1', 'Unknown receipt schema')
    require(native.get('mode') == runner.get('mode')
            and native.get('mode') in ('default-policy', 'cached-bf16', 'cached-8bit', 'cached-4bit'),
            'Sustained acceptance requires an offline single-variant mode')
    for field in ('passed', 'functionalPassed', 'resourceShutdownComplete'):
        require(native.get(field) is True, f'Native gate failed: {field}')
    for field in ('passed', 'nativePassed', 'normalQuit', 'appExitVerified'):
        require(runner.get(field) is True, f'Runner gate failed: {field}')
    require(runner.get('forcedCleanup') is False and runner.get('remainingOwnedPids') == [],
            'Forced cleanup or orphan process')
    require(runner.get('captureExitStatus') == 0 and runner.get('appExitStatus') == 0,
            'Unsuccessful capture/app exit')
    require(runner.get('errors') == [] and native.get('shutdownErrors') == []
            and native.get('observationErrors') == [], 'Receipt contains runtime errors')
    require(runner.get('maxMlxChildren') == 1
            and finite(runner.get('observedMlxSamples'), 'child samples') > 0,
            'Requires exactly one observed model child without overlap')
    process = runner.get('processEvents', [])
    require(0 < len(process) <= 128 and all(len(p.get('pids', [])) <= 1 for p in process)
            and any(len(p.get('pids', [])) == 1 for p in process), 'Invalid process observations')
    responsiveness = native.get('nativeMainResponsiveness', {})
    require(responsiveness.get('passed') is True and responsiveness.get('error') is None
            and finite(responsiveness.get('samples'), 'native probe count') > 0
            and finite(responsiveness.get('applicationActiveSamples'), 'active native probes') > 0
            and 0 <= finite(responsiveness.get('maxRoundTripMs'), 'native response') <= 250
            and 0 <= finite(native.get('maxUiHeartbeatDelayMs'), 'UI response') <= 250,
            '250ms responsiveness gate failed')
    require(timing.get('schema') == 'readaloud-app-capture-timing-v1'
            and timing.get('appPid') == runner.get('pid'), 'Capture app identity mismatch')
    primary_capture_mode(native, runner, timing)
    require(finite(timing.get('firstSignalReceivedUnixMicros'), 'capture signal time') > 0,
            'Missing captured signal')
    signal = runner.get('emittedSignal') or []
    require(len(signal) == len(native.get('segments', [])) and signal
            and all(s.get('passed') is True for s in signal), 'Captured signal gate failed')


def analyze(directory, diagnostic_only=False):
    directory = Path(directory)
    native = load_json(directory / 'receipt.json')
    runner = load_json(directory / 'runner.json')
    timing = load_json(directory / 'capture.wav.timing.json')
    result = {'schema': 'readaloud-s7-strict-acoustic-v1', 'passed': False,
              'diagnosticOnly': diagnostic_only, 'acousticCriteriaPassed': False,
              'runtimeFailures': [],
              'runtimeEvidence': {'nativePassed': native.get('passed'),
                                  'runnerPassed': runner.get('passed'),
                                  'runnerErrors': runner.get('errors'),
                                  'nativeMainResponsiveness': native.get('nativeMainResponsiveness')},
              'mode': native.get('mode'), 'errors': [], 'segments': [],
              'policy': {'fullActiveCorrelationMinimum': THRESHOLD,
                         'fullReferencePlacementCorrelationMinimum': THRESHOLD,
                         'maximumAbsoluteExternalJoinMs': MAX_GAP_MS,
                         'minimumCompleteReferenceSeconds': MIN_COMPLETE_SECONDS},
              'limits': 'Full queued-waveform identity/order and external joins for sustained native runs. '
                        'Final Pause-interrupted WAV is excluded explicitly, never prefix-qualified. '
                        'Source-silent packets have signal and aggregate timing checks between audible anchors; '
                        'individual silent boundaries have no acoustic identity. '
                        'No transcript, perceived quality/voice, human listening, startup, memory or M3 acceptance.'}
    try:
        capture_mode = primary_capture_mode(native, runner, timing)
        result.update(capture_scope(capture_mode))
        runtime_gates(native, runner, timing,
                      result['runtimeFailures'] if diagnostic_only else None)
        if diagnostic_only:
            result['errors'].extend(result['runtimeFailures'])
        rate, captured, _, _ = read_audio(directory / 'capture.wav', MAX_CAPTURE_BYTES, 300)
        require(rate in (44100, 48000) and timing.get('sampleRate') == rate
                and timing.get('frames') == len(captured), 'Capture timing/PCM mismatch')
        origin = finite(timing.get('firstPacketReceivedUnixMicros'), 'capture origin')
        comparison_rate = rate * 4
        result.update(captureSampleRate=rate, comparisonSampleRate=comparison_rate,
                      capturePeak=float(np.max(np.abs(captured))))
        queued = native.get('queuedAudio', [])
        samples = native.get('playerSamples', [])
        segments = native.get('segments', [])
        require(0 < len(queued) <= 2048 and 0 < len(samples) <= 2700
                and len(segments) == 1, 'Sustained receipt observation bounds')
        paths = [q.get('sourcePath') for q in queued]
        require(all(isinstance(p, str) and p for p in paths) and len(set(paths)) == len(paths),
                'Missing/duplicate queued source identity')
        # Verify every copied file before interpreting playback or exclusions.
        references = []
        total_bytes = 0
        total_seconds = 0
        for row in queued:
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
        for segment in segments:
            report = {'label': segment.get('label'), 'matches': [], 'excludedFinalWaveform': None,
                      'completeReferenceSeconds': 0., 'errors': []}
            result['segments'].append(report)
            play = finite(segment.get('playRequestedUnixMicros'), 'Play request')
            first = finite(segment.get('firstPositionUnixMicros'), 'first player movement')
            pause = finite(segment.get('pauseRequestedUnixMicros'), 'Pause request')
            require(segment.get('requiredWallPlaybackMs') == 60000 and play <= first < pause
                    and pause - first >= 59_900_000, 'Requires observed 60s sustained interval')
            require(segment.get('terminal') is None
                    and finite(segment.get('observedPositionAdvanceMs'), 'player advance') >= 51000
                    and segment.get('positionEvidence', {}).get('overflow') is False,
                    'Insufficient native player progress')
            process_primary = capture_mode == 'process-tap'
            low_time, stop = playback_bounds(segment, origin, len(captured) / rate, process_primary)
            if process_primary:
                report['unobservedPlayToTapInterval'] = {
                    'startUnixMicros': play, 'endUnixMicros': max(play, origin),
                    'status': 'UNOBSERVED', 'inference': 'No first-audio, silence or earlier replay claim'}
            engine = segment.get('engineIndex')
            require(all(q.get('engineIndex') == engine and q.get('engineId') == segment.get('engineId')
                        and finite(q.get('queuedUnixMicros'), 'queue time') <= pause for q in queued),
                    'Queued source outside sustained engine/playback interval')
            observations = [s for s in samples if s.get('engineIndex') == engine and s.get('playing') is True
                            and play <= finite(s.get('unixMicros'), 'sample time') <= pause]
            observed_order = []
            observations_by_path = {}
            for sample in observations:
                if sample.get('source') is None:
                    continue
                path = source_path(sample['source'])
                require(path in paths, 'Player source absent from queued evidence')
                position = finite(sample.get('positionMs'), 'native position')
                require(position >= 0, 'Negative native position')
                observations_by_path.setdefault(path, []).append(sample)
                if not observed_order or observed_order[-1] != path:
                    observed_order.append(path)
            indices = [paths.index(p) for p in observed_order]
            require(indices, 'No native source observations')
            # sequence/currentIndex/position are read separately by the probe.
            # A brief mixed snapshot is a search hint, never authority to change
            # queue order or waive acoustic order. Preserve anomalies explicitly.
            report['playerSnapshotOrderAnomalies'] = [
                {'fromQueueIndex': a, 'toQueueIndex': b}
                for a, b in zip(indices, indices[1:]) if a >= b]
            # Rendering may queue well ahead of playback. Bound the measured
            # interval using its final source witness, including the first
            # paused sample if delivered during Pause's recorded completion.
            returned = finite(segment.get('pauseReturnedUnixMicros', pause), 'Pause completion')
            require(pause <= returned <= pause + 10_000_000, 'Invalid Pause completion interval')
            after_pause = [s for s in samples if s.get('engineIndex') == engine
                           and pause <= s['unixMicros'] <= min(returned, pause + 250_000)
                           and s.get('source') is not None and s.get('positionMs', 0) > 0]
            witness = after_pause[0] if after_pause else observations[-1]
            require(abs(witness['unixMicros'] - pause) <= 250_000,
                    'No source witness within 250ms of Pause')
            final_path = source_path(witness['source'])
            require(final_path in paths, 'Pause source absent from queued evidence')
            final_index = paths.index(final_path)
            report['pauseSourceWitness'] = {'queueIndex': final_index, 'sample': witness}
            report['preparedTailOutsidePlaybackInterval'] = [
                {'queueIndex': i, 'sourcePath': q['sourcePath'], 'reference': q['reference']}
                for i, q in enumerate(queued) if i > final_index]
            previous_end = None
            pending_silent_seconds = 0.
            pending_unmatched_seconds = 0.
            pending_silent_packets = []
            report['encodedSilentPackets'] = []
            report['failedWaveforms'] = []
            audible_digests = set()
            for number, (row, (source_rate, pcm)) in enumerate(zip(queued[:final_index + 1], references)):
                source = resample(pcm, source_rate, comparison_rate)
                duration = len(pcm) / source_rate
                active = np.flatnonzero(np.abs(source) > .01)
                if not len(active):
                    # A source-encoded silent packet has no acoustic identity.
                    # Preserve its complete duration between audible anchors;
                    # never count it toward 50s of waveform-matched evidence.
                    silent_record = {
                        'queueIndex': number, 'sourcePath': row['sourcePath'],
                        'durationSeconds': duration, 'reference': row['reference'],
                        'scope': 'Source-encoded silence; signal and aggregate timing between full acoustic anchors'}
                    report['encodedSilentPackets'].append(silent_record)
                    pending_silent_packets.append(silent_record)
                    pending_silent_seconds += duration
                    continue
                start, end = int(active[0]), int(active[-1]) + 1
                if process_primary:
                    digest = row['reference']['sha256']
                    require(digest not in audible_digests,
                            'Ambiguous duplicate audible reference identity within segment')
                    audible_digests.add(digest)
                seen = observations_by_path.get(row['sourcePath'], [])
                estimates = [(s['unixMicros'] - origin) / 1e6 - s['positionMs'] / 1000 for s in seen]
                ordered_end = (None if previous_end is None else previous_end
                               + pending_silent_seconds + pending_unmatched_seconds)
                expected = float(np.median(estimates)) if estimates else ordered_end
                require(expected is not None, 'Initial source has no native playback observation')
                # Restrict FFT to the source's observed onset neighborhood. Permit
                # up to 2s of join displacement to diagnose (and reject) stalls.
                low = max(low_time, expected - 1.)
                high = min(stop, expected + duration + 1.)
                if ordered_end is not None:
                    low = max(low, ordered_end - .05)
                    high = min(high, ordered_end + duration + 2.)
                base = max(0, math.floor(low * rate))
                finish = min(len(captured), math.ceil(high * rate))
                window = resample_poly(captured[base:finish], 4, 1)
                index, score, context_score = match_reference(window, source, start, end)
                actual = None if index is None else base / rate + index / comparison_rate
                complete = (actual is not None and actual >= (low_time if process_primary else low_time - .01)
                            and actual + duration <= (min(len(captured) / rate, stop + .001)
                                                      if process_primary else stop + .001))
                if not complete:
                    # The only permitted exclusion is the final source when the
                    # expected full end crosses Pause. Wrong/missing earlier or
                    # already-completable final audio always fails.
                    final_start = ordered_end if ordered_end is not None else expected
                    interrupted = (number == final_index and final_start < stop
                                   and final_start + duration > stop + .001
                                   and ((seen and row['sourcePath'] == final_path)
                                        or (not seen and ordered_end is not None
                                            and 0 <= stop - ordered_end <= .25)))
                    if not interrupted:
                        message = f'No complete ordered waveform #{number + 1}; best={score:.6f}'
                        require(diagnostic_only, message)
                        report['errors'].append(message)
                        report['failedWaveforms'].append({
                            'queueIndex': number, 'sourcePath': row['sourcePath'],
                            'reference': row['reference'], 'sourceDurationSeconds': duration,
                            'expectedStartSeconds': expected, 'bestFullActiveCorrelation': score,
                            'fullReferenceCorrelation': context_score,
                            'fullReferenceComparisonFrames': len(source),
                            'searchWindowStartSeconds': base / rate,
                            'searchWindowEndSeconds': finish / rate,
                            'scope': 'FAILED complete-waveform match; diagnostic continuation, never accepted'})
                        pending_unmatched_seconds += duration
                        continue
                    report['excludedFinalWaveform'] = {
                        'queueIndex': number, 'sourcePath': row['sourcePath'],
                        'reference': row['reference'], 'durationSeconds': duration,
                        'observedByPlayer': bool(seen), 'expectedStartSeconds': expected,
                        'reason': 'Final queued WAV interrupted by Pause; no partial waveform acceptance'}
                    continue
                residual = None if ordered_end is None else (actual - ordered_end) * 1000
                gap = residual if pending_unmatched_seconds == 0 else None
                record = {'queueIndex': number, 'sourcePath': row['sourcePath'],
                          'reference': row['reference'], 'captureStartSeconds': actual,
                          'captureEndSeconds': actual + duration, 'fullActiveCorrelation': score,
                          'fullReferenceCorrelation': context_score,
                          'fullReferenceComparisonFrames': len(source),
                          'activeComparisonFrames': end - start, 'sourceDurationSeconds': duration,
                          'externalGapBeforeMs': gap, 'encodedSilentSecondsBefore': pending_silent_seconds,
                          'failedReferenceSecondsBefore': pending_unmatched_seconds,
                          'aggregateTimingResidualAfterFailedReferencesMs':
                              residual if pending_unmatched_seconds else None,
                          'searchWindowSeconds': (finish - base) / rate}
                report['matches'].append(record)
                silent_start = (previous_end if previous_end is not None
                                else actual - pending_silent_seconds)
                silent_group = None
                if pending_silent_packets and not pending_unmatched_seconds:
                    # Consecutive quiet sources have no independent acoustic
                    # boundaries. Check their single anchored interval, keeping
                    # the same 10ms outer guards and aggregate join threshold.
                    # A tiny packet must not erase a larger checkable interval.
                    group_end = silent_start + pending_silent_seconds
                    a = max(0, math.ceil((silent_start + .01) * rate))
                    b = min(len(captured), math.floor((group_end - .01) * rate))
                    require(a < b and silent_start >= (low_time if process_primary else low_time - .01)
                            and group_end <= stop,
                            'Silent packet lacks bounded captured interval')
                    silent_group = {
                        'queueIndices': [s['queueIndex'] for s in pending_silent_packets],
                        'durationSeconds': pending_silent_seconds,
                        'captureStartSeconds': silent_start, 'captureEndSeconds': group_end,
                        'interiorCapturedPeak': float(np.max(np.abs(captured[a:b]))),
                        'scope': 'One anchored quiet interval; no individual boundary or waveform credit'}
                    require(silent_group['interiorCapturedPeak'] <= .01,
                            'Unexpected captured signal in source-encoded silent packet')
                for silent in pending_silent_packets:
                    if pending_unmatched_seconds:
                        silent['signalCheckNotRun'] = 'Failed preceding waveform placement; diagnostic only'
                        continue
                    silent_end = silent_start + silent['durationSeconds']
                    silent['captureStartSeconds'] = silent_start
                    silent['captureEndSeconds'] = silent_end
                    silent['signalCheckGroup'] = silent_group
                    silent_start = silent_end
                if gap is not None and abs(gap) > MAX_GAP_MS:
                    report['errors'].append(f'External join #{number}: {gap:.3f}ms exceeds 10ms')
                report['completeReferenceSeconds'] += duration
                previous_end = actual + duration
                pending_silent_seconds = 0.
                pending_unmatched_seconds = 0.
                pending_silent_packets = []
            require(pending_silent_seconds == 0.,
                    'Unanchored silent tail cannot prove complete end/continuity')
            if report['completeReferenceSeconds'] < MIN_COMPLETE_SECONDS:
                report['errors'].append(
                    f'Insufficient full-waveform coverage: {report["completeReferenceSeconds"]:.3f}s < 50s')
            require(len(report['matches']) >= 2, 'No measured waveform join')
            require(report['excludedFinalWaveform'] is not None
                    or 0 <= stop - previous_end <= .25,
                    'Final complete waveform does not reach the Pause interval')
            report['maximumAbsoluteExternalJoinMs'] = max(
                (abs(m['externalGapBeforeMs']) for m in report['matches']
                 if m['externalGapBeforeMs'] is not None), default=None)
            report['minimumFullActiveCorrelation'] = min(
                m['fullActiveCorrelation'] for m in report['matches'])
            report['passed'] = not report['errors']
            result['errors'].extend(f'{report["label"]}: {error}' for error in report['errors'])
        result['acousticCriteriaPassed'] = all(s.get('passed') is True for s in result['segments'])
        result['passed'] = result['acousticCriteriaPassed'] and not diagnostic_only
    except (ValueError, KeyError, TypeError, OSError) as error:
        result['errors'].append(str(error))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--diagnostic-only', action='store_true',
                        help='Compute acoustic metrics despite runtime failures; always return failed verdict/exit 1')
    args = parser.parse_args()
    try:
        result = analyze(args.directory, diagnostic_only=args.diagnostic_only)
    except (ValueError, KeyError, TypeError, OSError) as error:
        result = {'schema': 'readaloud-s7-strict-acoustic-v1', 'passed': False, 'errors': [str(error)]}
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps({'passed': result['passed'], 'errors': result['errors']}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
