"""Bounded engine-switch evidence: real prefix, then no obsolete speech.

Does not qualify complete turns, model quality, physical speaker latency or M3.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly

from compare_captured_dialogue import read_mono
from diagnose_packet_capture import match


def require(ok, message):
    if not ok:
        raise ValueError(message)


def analyze(receipt, runner, timing, capture_path):
    require(receipt.get('schema') == 'readaloud-native-engine-session-v1', 'Wrong schema')
    require(all(receipt.get(k) is True for k in
                ('passed', 'functionalPassed', 'resourceShutdownComplete', 'offline',
                 'previewCancelledBeforeAudio', 'exportCancelledWithoutPublication')),
            'Native session gates failed')
    require(receipt.get('shutdownErrors') == [], 'Native cleanup errors')
    require(receipt.get('nativeMainResponsiveness', {}).get('passed') is True and
            receipt['nativeMainResponsiveness']['maxRoundTripMs'] <= 250 and
            receipt['maxUiHeartbeatDelayMs'] <= 250, 'Responsiveness failed')
    require(all(runner.get(k) is True for k in
                ('passed', 'nativePassed', 'normalQuit', 'appExitVerified', 'ownedAliasAbsent'))
            and runner.get('forcedCleanup') is False and
            runner.get('remainingOwnedPids') == [] and runner.get('errors') == [] and
            runner.get('captureExitStatus') == 0, 'Runner/normal-Quit gates failed')
    require(runner.get('maxMlxChildren') == 1 and
            runner.get('observedMlxSamples', 0) > 0, 'Missing single-child observation')
    activity = receipt['speechWorkActivity']
    require(activity['active'] == 0 and activity['started'] == activity['ended'] and
            activity['started'] > 0, 'Unbalanced native activities')
    events = receipt['events']
    failed = [e for e in events if e['event'] == 'offline-failed']
    complete = [e for e in events if e['event'] == 'complete']
    require(len(failed) == len(complete) == 1 and
            failed[0]['selected'] == 'fish_drama3_8bit' and failed[0]['active'] is None and
            failed[0]['lastWorking'] == 'fish_drama3' and
            failed[0]['sessionPhase'] == 'failed', 'Offline selected/active failure absent')
    require(not any(e['active'] == 'fish_drama3_8bit' for e in events),
            'Unavailable variant became active')
    final = complete[0]
    require(final['selected'] == final['active'] == final['lastWorking'] == 'fish_drama3'
            and final['sessionPhase'] == 'active' and final['startupError'] is None and
            final['pendingPlay'] is False and final['playing'] is False and
            final['word'] == receipt['retainedAnchor'] > 0,
            'Validated return/anchor/no-autoplay evidence absent')
    rate, capture = read_mono(capture_path)
    require(rate == timing['sampleRate'] and len(capture) == timing['frames'] and
            rate in (44100, 48000) and len(capture) <= rate * 360,
            'Capture extent/rate mismatch')
    origin = timing['firstPacketReceivedUnixMicros']
    require(final['unixMicros'] <= origin + len(capture) / rate * 1e6 + 250000,
            'Capture ended before the final switch observation')
    pause_request = receipt['positivePauseRequestedUnixMicros']
    pause_return = receipt['positivePauseReturnedUnixMicros']
    require(origin < timing['firstSignalReceivedUnixMicros'] < pause_request <= pause_return,
            'No positive captured signal before Pause')
    signal_frame = round((timing['firstSignalReceivedUnixMicros'] - origin) * rate / 1e6)
    require(abs(signal_frame - timing['firstSignalFrame']) <= rate * .25,
            'Signal callback/frame clocks exceed guard')
    tail_frame = round((pause_return + 250000 - origin) * rate / 1e6)
    require(0 < tail_frame < len(capture) - rate,
            'Need at least one second of post-Pause capture')
    tail_peak = float(np.max(np.abs(capture[tail_frame:])))
    require(tail_peak <= .001, 'Obsolete audio during switch or after replacement')
    reference = receipt['positiveReference']
    path = Path(reference['path'])
    require(path.stat().st_size <= 64 * 1024 * 1024 and
            hashlib.sha256(path.read_bytes()).hexdigest() == reference['sha256'],
            'Positive reference identity invalid')
    source_rate, source = read_mono(path)
    comparison_rate = rate * 4
    divisor = math.gcd(source_rate, comparison_rate)
    source = resample_poly(source, comparison_rate // divisor, source_rate // divisor)
    active = np.flatnonzero(np.abs(source) > .01)
    require(len(active) > 0, 'Silent positive reference')
    count = round(.04 * comparison_rate)
    template = source[active[0]:active[0] + count]
    require(len(template) == count and float(np.sqrt(np.mean(template ** 2))) >= .002,
            'No active 40ms reference prefix')
    end = min(len(capture), round((pause_request + 250000 - origin) * rate / 1e6))
    window = resample_poly(capture[:end], 4, 1)
    index, correlation = match(window, template)
    require(correlation >= .98 and index / comparison_rate + .04 <=
            (pause_request - origin) / 1e6, 'Positive prefix not matched wholly before Pause')
    return {
        'passed': True, 'prefixCorrelation': correlation, 'prefixDurationMs': 40,
        'postPauseGuardMs': 250, 'postPausePeak': tail_peak,
        'postPauseObservedMs': (len(capture) - tail_frame) / rate * 1000,
        'maxObservedMlxChildren': runner['maxMlxChildren'],
        'observedMlxSamples': runner['observedMlxSamples'],
        'nativeMainMaxMs': receipt['nativeMainResponsiveness']['maxRoundTripMs'],
        'maxUiHeartbeatDelayMs': receipt['maxUiHeartbeatDelayMs'],
        'retainedAnchor': receipt['retainedAnchor'],
        'scope': '40ms app-emitted positive prefix and post-Pause switch silence; '
                 '100ms sampled child count. Not complete-turn, universal overlap, '
                 'quantized-model, memory-envelope, physical-speaker or M3 acceptance.',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    read = lambda name: json.loads((args.run / name).read_text())
    result = analyze(read('receipt.json'), read('runner.json'),
                     read('capture.wav.timing.json'), args.run / 'capture.wav')
    with args.output.open('x') as target:
        json.dump(result, target, indent=2)
    print(json.dumps(result))
