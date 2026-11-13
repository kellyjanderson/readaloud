"""Bounded cancellation capture evidence, not full-turn or transcript acceptance.

Uses capture callback receipt clocks, not physical speaker onset. The 40ms
reference comparison deliberately covers only an active first-packet prefix.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from scipy.signal import correlate, fftconvolve, resample_poly

from compare_captured_dialogue import read_mono


def require(condition, message):
    if not condition:
        raise ValueError(message)


def analyze(receipt, runner, capture_path, timing, native_input=None):
    require(receipt.get('schema') == 'readaloud-native-packet-cancellation-v1',
            'Wrong cancellation receipt schema')
    for key in ('passed', 'functionalPassed', 'resourceShutdownComplete',
                'sceneIncompleteAtFirstPacket'):
        require(receipt.get(key) is True, f'Missing native gate: {key}')
    require(receipt.get('shutdownErrors') == [], 'Shutdown errors')
    require(receipt.get('nativeMainResponsiveness', {}).get('passed') is True,
            'Native responsiveness failed')
    for key in ('passed', 'nativePassed', 'normalQuit', 'appExitVerified'):
        require(runner.get(key) is True, f'Missing runner gate: {key}')
    require(runner.get('forcedCleanup') is False and
            runner.get('remainingOwnedPids') == [] and
            runner.get('ownedPidsAfterNormalQuit') == [] and
            runner.get('errors') == [] and runner.get('captureExitStatus') == 0,
            'Runner/capture cleanup failed')
    resources = receipt['finalNativeResources']
    require(resources == dict(playerPlaying=False, pendingPlaybackPreparationTasks=0,
                              playbackPins=0, resourcesReady=False),
            'Final native resources not drained')
    activity = receipt['speechWorkActivity']
    require(activity['active'] == 0 and activity['started'] == activity['ended']
            and activity['started'] > 0, 'Native activities not balanced')
    require(receipt.get('playerStateOverflow') is False, 'Player state overflow')
    states = receipt['playerStateEvents']
    stopped = receipt['nativePlayerStoppedEventIndex']
    require(isinstance(stopped, int) and 0 < stopped < len(states),
            'Missing native stop event')
    require(any(s['playing'] for s in states[:stopped]) and
            not any(s['playing'] for s in states[stopped:]),
            'Native player did not stop or resumed')
    events = {e['event']: e for e in receipt['cancellationEvents']}
    require(len(events) == len(receipt['cancellationEvents']), 'Duplicate lifecycle event')
    pause = events['packet-pause-request']
    retry = events['retry-play-request']
    require(receipt.get('packetPauseCoverage') ==
            'native packet before complete scene; paused', 'Packet Pause coverage missing')
    require(pause['unixMicros'] <= states[stopped]['unixMicros'] <=
            events['packet-pause-returned']['unixMicros'],
            'Native stop does not belong to this Pause')
    require(not any(s['playing'] for s in states
                    if s['unixMicros'] < retry['unixMicros']),
            'Native player started before fresh retry')
    observed = events.get('native-cancel-intent-observed',
                          events.get('cold-cancel-immediate-intent'))
    require(observed is not None and observed['pendingIntent'] is False and
            observed['playerPlaying'] is False, 'Cold intent cancellation absent')
    require(events['packet-pause-returned']['playerPlaying'] is False,
            'Native player still playing after Pause')
    require(events['packet-pause-observation-ended']['unixMicros'] -
            states[stopped]['unixMicros'] >= 500000, 'Insufficient native stopped tail')

    def unfinished(value):
        records = value.get('spokenScenes', [])
        return (value.get('unknownActiveScene') is True and records and
                records[-1]['completed'] is False and
                records[-1]['audioDurationMicros'] == 0 and
                value.get('completedExports') == 0 and
                value.get('completedOrdinaryScenes') == 0)

    require(unfinished(receipt['firstNativePacket']) and unfinished(pause),
            'Positive unfinished source ownership absent')
    interval = receipt['nativePlaybackIntervalBeforePause']
    require(interval['sampledPositionTotalMs'] >= 180 and interval['playerPlaying'] is True
            and interval['unknownActiveScene'] is True and
            interval['completedOrdinaryScenes'] == interval['completedExports'] == 0
            and pause['playerPlaying'] is True, 'No unfinished active playback interval')

    require(len(states) <= 256 and len(events) <= 128, 'Evidence event bound exceeded')
    require(Path(capture_path).stat().st_size <= 256 * 1024 * 1024,
            'Capture exceeds bounded 256MiB input')
    rate, capture = read_mono(capture_path)
    require(8000 <= rate <= 192000 and 0 < len(capture) <= rate * 300,
            'Capture outside bounded 300-second/rate envelope')
    require(rate == timing['sampleRate'] and len(capture) == timing['frames'],
            'Capture timing extent mismatch')
    origin = timing['firstPacketReceivedUnixMicros']
    def frame(unix_micros):
        return round((unix_micros - origin) * rate / 1000000)
    retry_frame = frame(retry['unixMicros'])
    tail_frame = frame(pause['unixMicros'] + 250000)
    require(0 < retry_frame < tail_frame < len(capture),
            'Receipt clocks outside capture')
    require(retry['unixMicros'] < timing['firstSignalReceivedUnixMicros'] <
            pause['unixMicros'], 'Capture signal callback not before Pause after retry')
    signal_clock_frame = frame(timing['firstSignalReceivedUnixMicros'])
    require(abs(signal_clock_frame - timing['firstSignalFrame']) <= rate * .25,
            'Capture signal frame/callback clocks exceed 250ms guard')
    pre = capture[:retry_frame]
    tail = capture[tail_frame:]
    require(len(pre) / rate >= .5 and len(tail) / rate >= .5,
            'Need at least 500ms pre-retry and post-Pause guard tail')
    silence_threshold = .001
    pre_peak = float(np.max(np.abs(pre)))
    tail_peak = float(np.max(np.abs(tail)))
    require(pre_peak <= silence_threshold, 'Audio before retry')
    require(tail_peak <= silence_threshold, 'Late audio after Pause +250ms guard')

    queued = sorted(receipt['queuedAudio'], key=lambda q: q['queueIndex'])
    require(queued and len(queued) <= 512 and [q['queueIndex'] for q in queued] == list(range(len(queued)))
            and all('error' not in q for q in queued), 'Missing/invalid queued packets')
    require(receipt['firstNativePacket'].get('nativeIndex') == 0,
            'First queued reference was not the active native packet')
    reference = Path(queued[0]['path'])
    require(reference.stat().st_size <= 64 * 1024 * 1024, 'Queued packet exceeds 64MiB')
    require(hashlib.sha256(reference.read_bytes()).hexdigest() == queued[0]['sha256'],
            'Queued reference hash mismatch')
    source_rate, source = read_mono(reference)
    active = np.flatnonzero(np.abs(source) > .01)
    require(len(active) > 0, 'Silent queued packet')
    # Fourfold comparison resolves fractional 44.1kHz -> 48kHz mixing phase,
    # using the unchanged .98 waveform threshold of the full-dialogue analyzer.
    comparison_rate = rate * 4
    divisor = math.gcd(source_rate, comparison_rate)
    source = resample_poly(source, comparison_rate // divisor, source_rate // divisor)
    active = np.flatnonzero(np.abs(source) > .01)
    start = int(active[0])
    count = round(.04 * comparison_rate)
    template = source[start:start + count]
    require(len(template) == count and np.sqrt(np.mean(template ** 2)) >= .002,
            'No positive-energy 40ms first-packet prefix')
    lower = max(retry_frame, frame(receipt['firstNativePacket']['unixMicros'] - 250000))
    upper = min(len(capture), frame(pause['unixMicros'] + 250000))
    window = resample_poly(capture[lower:upper], 4, 1)
    require(len(window) >= len(template), 'Capture too short for prefix')
    correlation = correlate(window, template, mode='valid', method='fft')
    power = fftconvolve(window ** 2, np.ones(count), mode='valid')
    template_power = float(template @ template)
    scores = np.zeros_like(correlation)
    valid = power > max(count * 1e-10, template_power * 1e-6)
    np.divide(correlation, np.sqrt(np.maximum(power, 0) * template_power),
              out=scores, where=valid)
    best = int(scores.argmax())
    score = float(scores[best])
    require(score >= .98, f'No first-packet 40ms prefix match: best={score:.6f}')
    matched_start = lower / rate + best / comparison_rate
    matched = window[best:best + count]
    rms = float(np.sqrt(np.mean(matched ** 2)))
    require(rms >= .002, 'No positive captured prefix energy')
    require(matched_start + .04 <= (pause['unixMicros'] - origin) / 1000000,
            'Matched prefix was not wholly before Pause callback clock')

    report = {
        'passed': True,
        'scope': '40ms active first-queued-packet prefix only; not whole-turn, '
                 'transcript, voice identity or physical speaker onset acceptance.',
        'clockScope': 'Capture firstPacketReceivedUnixMicros maps callback receipt '
                      'clocks to frames; post-Pause +250ms is a clock/output guard.',
        'captureSampleRate': rate, 'captureFrames': len(capture),
        'signalCallbackBeforePauseMs': (pause['unixMicros'] -
                                       timing['firstSignalReceivedUnixMicros']) / 1000,
        'prefix': {'durationMs': 40, 'correlation': score, 'rms': rms,
                   'referencePath': str(reference), 'referenceSha256': queued[0]['sha256'],
                   'referenceActiveStartSeconds': start / comparison_rate,
                   'captureStartSeconds': matched_start},
        'silence': {'peakThreshold': silence_threshold, 'preRetryPeak': pre_peak,
                    'preRetryObservedMs': len(pre) * 1000 / rate,
                    'postPauseGuardMs': 250, 'postPauseTailPeak': tail_peak,
                    'postPauseTailObservedMs': len(tail) * 1000 / rate},
        'native': {'sampledPositionTotalMsBeforePause': interval['sampledPositionTotalMs'],
                   'pauseDrainMs': receipt['packetPauseDrainMs'],
                   'stateEvents': len(states), 'queuedPackets': len(queued),
                   'activitiesStarted': activity['started'], 'activitiesEnded': activity['ended'],
                   'remainingOwnedProcessCount': len(runner['remainingOwnedPids'])},
        'coldCancellation': {
            'inputMode': receipt['coldInputMode'],
            'drainAfterIntentMs': (events['cold-preparation-drained']['unixMicros'] -
                                   observed['unixMicros']) / 1000,
            'rawColdCancelDrainMs': receipt['coldCancelDrainMs'],
            'rawDrainScope': 'Includes external input wait; not human input latency.',
        },
    }
    if native_input is not None:
        require(receipt['coldInputMode'] == 'external-native-input',
                'Input timestamps require external-native-input mode')
        before = native_input['clickBeforeUnixMicros']
        returned = native_input['clickReturnedUnixMicros']
        require(before <= returned <= observed['unixMicros'] < retry['unixMicros'],
                'Native input timestamps out of order')
        report['coldCancellation']['nativeInput'] = {
            **native_input,
            'clickBeforeToIntentObservedMs': (observed['unixMicros'] - before) / 1000,
            'clickReturnedToIntentObservedMs': (observed['unixMicros'] - returned) / 1000,
            'scope': 'External tool call boundary to observed intent; not physical input latency.',
        }
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--native-input', type=Path)
    args = parser.parse_args()
    try:
        load = lambda name: json.loads((args.evidence / name).read_text())
        result = analyze(load('receipt.json'), load('runner.json'),
                         args.evidence / 'capture.wav', load('capture.wav.timing.json'),
                         json.loads(args.native_input.read_text()) if args.native_input else None)
    except (ValueError, KeyError, IndexError, TypeError, OSError) as error:
        result = {'passed': False, 'error': str(error), 'scope': __doc__.strip()}
    with args.output.open('x') as target:
        json.dump(result, target, indent=2)
    print(json.dumps(result))
    raise SystemExit(0 if result['passed'] else 1)
