#!/usr/bin/env python3
"""#144 diagnostic comparison of the same expected PCM under two queue shapes.

Usage: analyze_s7_queue_replay.py RUN_DIRECTORY NEW_OUTPUT.json
Always returns passed=false/exit 1. Original packet references are expectations,
never invented native URI observations. Raw player samples remain authoritative.
Uses the established full-active-waveform .98 and external-join 10ms criteria.
"""
import argparse
import hashlib
import math
from pathlib import Path
from urllib.parse import unquote, urlparse

import numpy as np

from analyze_s7_variants import (MAX_CAPTURE_BYTES, MAX_GAP_MS,
                                 MIN_COMPLETE_SECONDS, THRESHOLD, finite,
                                 load_json, match, read_audio, require, resample)
from analyze_s7_switches import quiet_interval


def verify_reference(ref):
    path = Path(ref['path'])
    size = path.stat().st_size
    require(size == ref['bytes'] and 44 <= size <= 120_000_000,
            'Reference size mismatch/bound')
    require(hashlib.sha256(path.read_bytes()).hexdigest() == ref['sha256'],
            'Reference SHA256 mismatch')
    rate, pcm, channels, bits = read_audio(path, 120_000_000, 120)
    require(rate == ref['sampleRate'] == 44100 and channels == ref['channels'] == 1
            and bits == ref['bitsPerSample'] == 16
            and len(pcm) * 2 == ref['pcmBytes'], 'Reference format mismatch')
    return pcm


def raw_source(sample):
    parsed = urlparse(sample.get('source') or '')
    require(parsed.scheme == 'file' and parsed.netloc in ('', 'localhost'),
            'Invalid actual native source URI')
    return unquote(parsed.path)


def analyze(directory):
    directory = Path(directory)
    result = {'schema': 'readaloud-s7-queue-replay-analysis-v1',
              'diagnosticOnly': True, 'passed': False, 'acousticCriteriaMet': False,
              'runtimeCriteriaMet': False, 'runtimeFailures': [], 'errors': [],
              'matches': [], 'encodedSilentPackets': [], 'excludedFinalWaveform': None,
              'policy': {'fullActiveCorrelationMinimum': THRESHOLD,
                         'maximumAbsoluteExternalJoinMs': MAX_GAP_MS,
                         'minimumCompleteReferenceSeconds': MIN_COMPLETE_SECONDS,
                         'minimumObservedPlaybackSeconds': 60,
                         'maximumUiAndNativeResponseMs': 250,
                         'maximumQuietPeak': .001, 'quietGuardSeconds': .25,
                         'minimumQuietSeconds': 1},
              'limits': 'Diagnostic expected-packet PCM comparison. Joined native samples retain the '
                        'single actual URI; no synthetic native packet observations. Full expected '
                        'waveforms and joins are scored independently from unchanged runtime gates. '
                        'Final Pause-interrupted packet may be excluded explicitly. No model, '
                        'document/reading, voice quality, human listening, memory or M3 qualification.'}
    try:
        native, runner, timing = [load_json(directory / name) for name in (
            'receipt.json', 'runner.json', 'capture.wav.timing.json')]
        require(native.get('queueReplayDiagnostic') is True and runner.get('queueReplayDiagnostic') is True
                and native.get('replayMode') == runner.get('replayMode')
                and native.get('replayMode') in ('packets', 'joined'), 'Not a queue replay diagnosis')
        require(native.get('passed') is False and runner.get('passed') is False,
                'Diagnostic must never claim qualification')
        result['replayMode'] = mode = native['replayMode']
        def runtime(condition, message):
            if not condition:
                result['runtimeFailures'].append(message)
        runtime(native.get('replayCompleted') is True and native.get('error') is None,
                'Native replay failed')
        runtime(native.get('replayCleanupComplete') is True and native.get('shutdownErrors') == []
                and native.get('observationErrors') == [], 'Native cleanup/observation failed')
        runtime(runner.get('normalQuit') is True and runner.get('appExitVerified') is True
                and runner.get('forcedCleanup') is False and runner.get('remainingOwnedPids') == []
                and runner.get('captureExitStatus') == 0 and runner.get('appExitStatus') == 0,
                'Runner capture/normal Quit/orphan gate failed')
        expected_error = 'Queue replay diagnosis only; model and product qualification not applicable'
        runtime(runner.get('errors') == [expected_error], 'Unexpected runner errors')
        runtime(runner.get('maxMlxChildren') == 0 and runner.get('observedMlxSamples') == 0
                and runner.get('processEvents') and all(p.get('pids') == [] for p in runner['processEvents']),
                'Replay requires zero observed MLX children')
        probe = native.get('nativeMainResponsiveness', {})
        runtime(probe.get('passed') is True and probe.get('error') is None
                and finite(probe.get('samples'), 'native probe count') > 0
                and finite(probe.get('applicationActiveSamples'), 'active probe count') > 0
                and 0 <= finite(probe.get('maxRoundTripMs'), 'native delay') <= 250
                and 0 <= finite(native.get('maxUiHeartbeatDelayMs'), 'UI delay') <= 250,
                'Unchanged 250ms native/UI responsiveness gate failed')
        result['nativeMainResponsiveness'] = probe
        runtime(timing.get('schema') == 'readaloud-app-capture-timing-v1'
                and timing.get('appPid') == runner.get('pid'), 'Capture identity mismatch')
        require(len(native.get('segments', [])) == 1, 'Requires one playback interval')
        segment = native['segments'][0]
        play, first, pause, returned = [finite(segment.get(k), k) for k in (
            'playRequestedUnixMicros', 'firstPositionUnixMicros',
            'pauseRequestedUnixMicros', 'pauseReturnedUnixMicros')]
        runtime(segment.get('requiredWallPlaybackMs') == 60000 and play <= first < pause <= returned
                and pause - first >= 60_000_000 and segment.get('terminal') is None
                and finite(segment.get('observedPositionAdvanceMs'), 'player advance') >= 51000
                and segment.get('positionEvidence', {}).get('overflow') is False,
                'Requires 60s real playback and sufficient actual native progress')
        result['runtimeCriteriaMet'] = not result['runtimeFailures']
        rate, captured, _, _ = read_audio(directory / 'capture.wav', MAX_CAPTURE_BYTES, 300)
        require(rate in (44100, 48000) and rate == timing.get('sampleRate')
                and len(captured) == timing.get('frames'), 'Capture PCM/timing mismatch')
        origin = finite(timing.get('firstPacketReceivedUnixMicros'), 'capture origin')
        low_time, stop = (play - origin) / 1e6, (pause - origin) / 1e6
        require(0 <= low_time < stop <= len(captured) / rate, 'Capture misses playback')
        provenance = native['sourceProvenance']
        input_path = Path(provenance['inputReceipt'])
        require(input_path.stat().st_size <= 8_000_000 and
                hashlib.sha256(input_path.read_bytes()).hexdigest() == provenance['inputReceiptSha256'],
                'Source receipt hash mismatch')
        input_rows = load_json(input_path)['queuedAudio']
        packets = provenance['expectedPackets']
        require(0 < len(packets) <= 220 and len(input_rows) <= 2048, 'Expected packet bound')
        references, frame, byte_count, pcm_hash = [], 0, 0, hashlib.sha256()
        for i, row in enumerate(packets):
            ref = row['reference']
            require(row['sourceReceiptIndex'] == i and row['startFrame'] == frame
                    and row['sourcePath'] == ref['path'], 'Expected packet source map/order mismatch')
            original = input_rows[i]['reference']
            require(row['originalReferencePath'] == original['path']
                    and all(ref.get(k) == original.get(k) for k in (
                        'sha256', 'bytes', 'sampleRate', 'channels', 'bitsPerSample', 'pcmBytes')),
                    'Expected packet differs from source receipt')
            pcm = verify_reference(ref)
            byte_count += ref['bytes']
            require(byte_count <= 120_000_000 and row['frameCount'] == len(pcm),
                    'Expected PCM bounds/frame count')
            raw = (pcm * 32768).astype('<i2').tobytes()
            pcm_hash.update(raw)
            references.append(pcm)
            frame += len(pcm)
        require(frame == provenance['totalFrames'] and 65 * 44100 <= frame <= 120 * 44100
                and pcm_hash.hexdigest() == provenance['pcmSha256'], 'Expected PCM identity mismatch')
        joined = verify_reference(provenance['joined'])
        require(len(joined) == frame and
                hashlib.sha256((joined * 32768).astype('<i2').tobytes()).hexdigest() == pcm_hash.hexdigest(),
                'Joined PCM differs from original packet PCM')
        result['pcmSha256'] = pcm_hash.hexdigest()
        actual = native['queuedAudio']
        require(0 < len(actual) <= 2048, 'Actual queue bound')
        if mode == 'joined':
            require(len(actual) == 1 and actual[0]['reference'] == provenance['joined'],
                    'Joined actual queue mismatch')
        else:
            require(all(a['reference'] == packets[i]['reference']
                        and a['sourcePath'] == packets[i]['sourcePath'] for i, a in enumerate(actual)),
                    'Actual packet queue order mismatch')
        actual_paths = [a['sourcePath'] for a in actual]
        samples = native['playerSamples']
        require(0 < len(samples) <= 2700, 'Native sample bound')
        active = [s for s in samples if s.get('playing') is True
                  and play <= finite(s.get('unixMicros'), 'sample wall time') <= pause
                  and s.get('source') is not None]
        require(active and all(raw_source(s) in actual_paths for s in active),
                'Native observation absent from actual queue')
        require(abs(active[-1]['unixMicros'] - pause) <= 250_000,
                'No actual source witness within 250ms of Pause')
        def global_seconds(sample):
            index = actual_paths.index(raw_source(sample))
            return (packets[index]['startFrame'] / 44100 if mode == 'packets' else 0) + sample['positionMs'] / 1000
        # Raw positions are only onset search hints. Complete waveform correlation
        # and expected order below decide acoustic identity in both queue modes.
        initial = [s for s in active if global_seconds(s) < 1]
        require(initial, 'Missing initial native playback observations')
        expected_start = float(np.median([(s['unixMicros'] - origin) / 1e6 - global_seconds(s)
                                         for s in initial]))
        comparison_rate = rate * 4
        previous_end = None
        silent_seconds = 0.
        silent_pending = []
        complete_seconds = 0.
        for i, (row, pcm) in enumerate(zip(packets, references)):
            duration = len(pcm) / 44100
            nominal = expected_start + row['startFrame'] / 44100
            ordered = None if previous_end is None else previous_end + silent_seconds
            expected = nominal if ordered is None else ordered
            if expected >= stop:
                break
            template = resample(pcm, 44100, comparison_rate)
            audible = np.flatnonzero(np.abs(template) > .01)
            if not len(audible):
                silent = {'queueIndex': i, 'durationSeconds': duration, 'reference': row['reference']}
                result['encodedSilentPackets'].append(silent)
                silent_pending.append(silent)
                silent_seconds += duration
                continue
            start, end = int(audible[0]), int(audible[-1]) + 1
            low, high = max(low_time, expected - .05 if ordered is not None else expected - 1), min(stop, expected + duration + 2)
            base, finish = max(0, math.floor(low * rate)), min(len(captured), math.ceil(high * rate))
            window = resample(captured[base:finish], rate, comparison_rate)
            index, score = (None, 0.) if len(window) < end - start else match(window, template[start:end])
            actual_start = None if index is None else base / rate + (index - start) / comparison_rate
            complete = actual_start is not None and actual_start >= low_time - .01 and actual_start + duration <= stop + .001
            if not complete:
                if expected < stop and expected + duration > stop + .001:
                    witness_frame = round(global_seconds(active[-1]) * 44100)
                    require(row['startFrame'] <= witness_frame < row['startFrame'] + row['frameCount'],
                            'Final exclusion lacks actual native position witness')
                    result['excludedFinalWaveform'] = {'queueIndex': i, 'reference': row['reference'],
                        'reason': 'Final expected packet interrupted by Pause; no prefix acceptance',
                        'expectedStartSeconds': expected, 'durationSeconds': duration}
                    break
                result['errors'].append(f'No complete ordered waveform #{i + 1}; best={score:.6f}')
                # Continue diagnostics without accepting this missing waveform.
                silent_seconds += duration
                continue
            gap = None if ordered is None else (actual_start - ordered) * 1000
            result['matches'].append({'queueIndex': i, 'reference': row['reference'],
                'captureStartSeconds': actual_start, 'captureEndSeconds': actual_start + duration,
                'fullActiveCorrelation': score, 'sourceDurationSeconds': duration,
                'externalGapBeforeMs': gap})
            if gap is not None and abs(gap) > MAX_GAP_MS:
                result['errors'].append(f'External join #{i}: {gap:.3f}ms exceeds 10ms')
            silent_start = actual_start - silent_seconds if previous_end is None else previous_end
            for silent in silent_pending:
                silent_end = silent_start + silent['durationSeconds']
                a, b = math.ceil((silent_start + .01) * rate), math.floor((silent_end - .01) * rate)
                require(0 <= a < b <= len(captured), 'Silent packet lacks bounded capture')
                silent['interiorCapturedPeak'] = float(np.max(np.abs(captured[a:b])))
                require(silent['interiorCapturedPeak'] <= .01, 'Unexpected signal in source silence')
                silent_start = silent_end
            complete_seconds += duration
            previous_end = actual_start + duration
            silent_seconds, silent_pending = 0., []
        require(not silent_pending, 'Unanchored source-silent tail')
        require(len(result['matches']) >= 2, 'Insufficient complete waveform joins')
        result['completeReferenceSeconds'] = complete_seconds
        if complete_seconds < MIN_COMPLETE_SECONDS:
            result['errors'].append(f'Insufficient full-waveform coverage: {complete_seconds:.3f}s < 50s')
        require(result['excludedFinalWaveform'] is not None or
                previous_end is not None and 0 <= stop - previous_end <= .25,
                'Complete waveform evidence does not reach Pause')
        # Require one entire guarded second after actual Pause completion.
        quiet_start = (returned - origin) / 1e6 + .25
        result['quietTail'] = quiet_interval(captured, rate, quiet_start, len(captured) / rate,
                                             'after-Pause', minimum=1.)
        result['acousticCriteriaMet'] = not result['errors']
        result['maximumAbsoluteExternalJoinMs'] = max((abs(m['externalGapBeforeMs']) for m in result['matches']
                                                       if m['externalGapBeforeMs'] is not None), default=None)
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        result['errors'].append(str(error))
    return result


def main():
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = analyze(args.directory)
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps({k: result[k] for k in (
        'passed', 'acousticCriteriaMet', 'runtimeCriteriaMet', 'runtimeFailures', 'errors')}))
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
