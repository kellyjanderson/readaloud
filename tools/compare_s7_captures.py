#!/usr/bin/env python3
"""Diagnostic S7 queued-waveform comparison of SCK and CoreAudio process tap.

Issue #142 under #112, ACD-M1 R1. This does not alter strict acceptance.

Usage: compare_s7_captures.py RUN_DIRECTORY NEW_OUTPUT.json
Reads receipt.json, runner.json, capture.wav[.timing.json] and
coreaudio.wav[.timing.json]. Recomputes the unchanged primary diagnostic for
packet placements; runtime failures do not prevent acoustic diagnostics.
No capture/app/device actions. Exit 0 means a diagnostic was produced without
input-integrity errors, never product acceptance. Output always has passed=false.
"""
import argparse
from collections import Counter
import json
import math
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly

from analyze_s7_variants import (MAX_CAPTURE_BYTES, MAX_GAP_MS, THRESHOLD,
                                 analyze as primary_analyze, finite, load_json,
                                 match_reference, read_audio, require, resample)
from analyze_s7_switches import verify_references
from process_tap_validation import validate_process_tap


def capture(directory, name, pid, tap=False):
    """Validate final PCM/timing before treating missing content as evidence."""
    timing = load_json(directory / f'{name}.wav.timing.json')
    require(timing.get('schema') == 'readaloud-app-capture-timing-v1'
            and timing.get('appPid') == pid, f'{name}: capture app identity mismatch')
    rate, pcm, _, _ = read_audio(directory / f'{name}.wav', MAX_CAPTURE_BYTES, 300)
    require(rate in (44100, 48000) and timing.get('sampleRate') == rate
            and timing.get('frames') == len(pcm), f'{name}: timing/PCM mismatch')
    origin = finite(timing.get('firstPacketReceivedUnixMicros'), f'{name} origin')
    require(origin > 0, f'{name}: invalid origin')
    gap = finite(timing.get('maxPacketGapSeconds'), f'{name} packet gap')
    require(0 <= gap <= MAX_GAP_MS / 1000, f'{name}: packet timing gap exceeds 10ms')
    if tap:
        validate_process_tap(timing, pid, len(pcm), rate)
    return {'rate': rate, 'pcm': pcm, 'origin': origin, 'timing': timing}


def compare_waveform(stream, pcm, source_rate, expected, duration, low, high,
                     ordered_end=None):
    """Full-reference placement and fixed active score at fourfold phase resolution.

    All times are local PCM seconds. No padding or prefix matching. A packet
    whose complete source interval is outside shared coverage is unobserved.
    """
    if expected < low or expected + duration > high:
        return {'status': 'unobserved', 'reason': 'Full source interval outside shared observed coverage'}
    rate = stream['rate']
    template = resample(pcm, source_rate, rate * 4)
    active = np.flatnonzero(np.abs(template) > .01)
    if not len(active):
        return {'status': 'source-silent', 'reason': 'No acoustic identity; never waveform credit'}
    start, end = int(active[0]), int(active[-1]) + 1
    a, b = max(low, expected - 1.), min(high, expected + duration + 1.)
    if ordered_end is not None:
        a, b = max(a, ordered_end - .05), min(b, ordered_end + duration + 2.)
    base = max(0, math.ceil(a * rate))
    finish = min(len(stream['pcm']), math.floor(b * rate))
    window = resample_poly(stream['pcm'][base:finish], 4, 1) if finish > base else np.empty(0)
    index, score, context_score = match_reference(window, template, start, end)
    actual = None if index is None else base / rate + index / (rate * 4)
    complete = (actual is not None and actual >= low
                and actual + duration <= high)
    row = {'status': 'matched' if complete else 'missing-full-waveform',
           'bestFullActiveCorrelation': score, 'activeComparisonFrames': end - start,
           'fullReferenceCorrelation': context_score, 'fullReferenceComparisonFrames': len(template),
           'searchWindowStartSeconds': base / rate, 'searchWindowEndSeconds': finish / rate}
    if not complete:
        row['reason'] = 'No complete ordered match in bounded onset window; not proof of global absence'
    if complete:
        residual = None if ordered_end is None else (actual - ordered_end) * 1000
        row.update(captureStartSeconds=actual, captureEndSeconds=actual + duration,
                   orderedTimingResidualMs=residual,
                   exceeds10msTimingPolicy=residual is not None and abs(residual) > MAX_GAP_MS)
    return row


def compare(directory):
    directory = Path(directory)
    result = {'schema': 'readaloud-s7-dual-capture-diagnostic-v1', 'diagnosticOnly': True,
              'passed': False, 'errors': [], 'captureErrors': {}, 'packets': [],
              'policy': {'fullActiveCorrelationMinimum': THRESHOLD, 'phaseMultiplier': 4,
                         'fullReferencePlacementCorrelationMinimum': THRESHOLD,
                         'maximumAbsoluteExternalJoinMs': MAX_GAP_MS},
              'limits': 'Diagnostic only, never product acceptance. Callback receipt origins are upper bounds, '
                        'not synchronized presentation clocks or physical speaker onset. Shared coverage uses '
                        'each actual first packet plus saved frame duration, without padding. Matches prove '
                        'saved PCM identity only; two missing captures cannot identify app versus common '
                        'capture/output loss. Source silence, unobserved boundaries and queued unplayed tail '
                        'receive no waveform credit. No listening, transcript, quality, startup, memory or M3 claim.'}
    try:
        native = load_json(directory / 'receipt.json')
        runner = load_json(directory / 'runner.json')
        require(native.get('schema') == 'readaloud-native-variant-v1'
                and runner.get('schema') == 'readaloud-native-variant-runner-v1', 'Unknown receipt schema')
        require(native.get('mode') == runner.get('mode'), 'Receipt/runner mode mismatch')
        pid = runner.get('pid')
        require(isinstance(pid, int) and not isinstance(pid, bool) and pid > 0, 'Invalid runner PID')
        queued = native.get('queuedAudio', [])
        require(0 < len(queued) <= 2048, 'Invalid queued reference count')
        _, references = verify_references(queued)  # Includes prepared/unplayed tail SHA validation.
        streams = {}
        for name in ('capture', 'coreaudio'):
            try:
                streams[name] = capture(directory, name, pid, tap=name == 'coreaudio')
            except (ValueError, KeyError, TypeError, OSError) as error:
                result['captureErrors'][name] = str(error)
        if result['captureErrors']:
            result['errors'].extend(result['captureErrors'].values())
            # Do not turn a corrupt/unfinished path into a missing-audio claim.
            result['packets'] = [{'queueIndex': i, 'sourcePath': q['sourcePath'],
                                  'classification': 'invalid-capture-evidence'} for i, q in enumerate(queued)]
            return result
        primary = primary_analyze(directory, diagnostic_only=True)
        result['primaryDiagnostic'] = {'passed': primary['passed'],
                                       'runtimeFailures': primary.get('runtimeFailures', []),
                                       'errors': primary.get('errors', [])}
        reports = primary.get('segments', [])
        require(len(reports) == 1, 'Primary diagnostic lacks sustained packet placements')
        report = reports[0]
        placements = {m['queueIndex']: (m, 'captureStartSeconds') for m in report.get('matches', [])}
        placements.update({m['queueIndex']: (m, 'expectedStartSeconds')
                           for m in report.get('failedWaveforms', [])})
        silent = {r['queueIndex']: r for r in report.get('encodedSilentPackets', [])}
        excluded = {r['queueIndex']: 'Prepared tail outside playback interval'
                    for r in report.get('preparedTailOutsidePlaybackInterval', [])}
        final = report.get('excludedFinalWaveform')
        if final:
            excluded[final['queueIndex']] = 'Final Pause-interrupted source; no partial waveform credit'
        sck = streams['capture']
        # Work relative to SCK's receipt origin to preserve sub-sample precision.
        offsets = {name: (s['origin'] - sck['origin']) / 1e6 for name, s in streams.items()}
        low = max(offsets.values())
        high = min(offsets[name] + len(s['pcm']) / s['rate'] for name, s in streams.items())
        require(low < high, 'No shared observed capture interval')
        result['sharedObservedInterval'] = {'originUnixMicros': sck['origin'],
                                            'startSeconds': low, 'endSeconds': high,
                                            'durationSeconds': high - low}
        result['captures'] = {name: {'appPid': pid, 'sampleRate': s['rate'], 'frames': len(s['pcm']),
                                     'firstPacketReceivedUnixMicros': s['origin'],
                                     'durationSeconds': len(s['pcm']) / s['rate']}
                              for name, s in streams.items()}
        ends = {name: None for name in streams}
        pending = {name: 0. for name in streams}
        pending_silent = {name: 0. for name in streams}
        for i, (q, (source_rate, pcm)) in enumerate(zip(queued, references)):
            duration = len(pcm) / source_rate
            row = {'queueIndex': i, 'sourcePath': q['sourcePath'], 'reference': q['reference'],
                   'sourceDurationSeconds': duration}
            result['packets'].append(row)
            if i not in placements:
                if i in silent:
                    row.update(classification='source-silent',
                               reason='Source-encoded silence has no acoustic identity; no waveform credit',
                               primarySilentEvidence=silent[i])
                else:
                    row.update(classification='unobserved', reason=excluded.get(i, 'No primary audible placement'))
                # Source-silent packets lack identity but their exact duration
                # still belongs in ordered accounting between audible anchors.
                for name in streams:
                    if i in silent:
                        pending_silent[name] += duration
                    else:
                        pending[name] += duration
                continue
            placement, key = placements[i]
            require(placement.get('sourcePath') == q['sourcePath']
                    and placement.get('reference') == q['reference'], 'Primary queued identity mismatch')
            expected = finite(placement.get(key), 'primary packet placement')
            row['placementAuthority'] = 'SCK full-waveform match' if key == 'captureStartSeconds' else 'Primary native/ordered search hint'
            row['expectedStartSecondsFromSckOrigin'] = expected
            for name, stream in streams.items():
                offset = offsets[name]
                ordered = None if ends[name] is None else ends[name] + pending[name] + pending_silent[name]
                found = compare_waveform(stream, pcm, source_rate, expected - offset, duration,
                                         low - offset, high - offset, ordered)
                row[name] = found
                if found['status'] == 'matched':
                    found['failedOrUnobservedReferenceSecondsBefore'] = pending[name]
                    found['encodedSilentSecondsBefore'] = pending_silent[name]
                    found['externalGapBeforeMs'] = found['orderedTimingResidualMs'] if not pending[name] else None
                    ends[name] = found['captureEndSeconds']
                    pending[name] = 0.
                    pending_silent[name] = 0.
                else:
                    pending[name] += duration
            a, b = row['capture']['status'], row['coreaudio']['status']
            if 'unobserved' in (a, b):
                classification = 'unobserved'
            elif a == b == 'matched':
                classification = 'agreement-matched'
                row['tapMinusSckReceiptMappedStartMs'] = (
                    offsets['coreaudio'] + row['coreaudio']['captureStartSeconds']
                    - row['capture']['captureStartSeconds']) * 1000
            elif a == 'missing-full-waveform' and b == 'matched':
                classification = 'sck-missing-tap-matches'
            elif a == 'matched' and b == 'missing-full-waveform':
                classification = 'sck-matches-tap-missing'
            elif a == b == 'missing-full-waveform':
                classification = 'both-missing-full-waveform'
            else:
                classification = 'source-silent'
            row['classification'] = classification
        result['classificationCounts'] = dict(Counter(r['classification'] for r in result['packets']))
        result['perCaptureSummary'] = {}
        for name in streams:
            matched = [r for r in result['packets'] if r.get(name, {}).get('status') == 'matched']
            result['perCaptureSummary'][name] = {
                'completeMatchedAudiblePackets': len(matched),
                'completeMatchedReferenceSeconds': sum(r['sourceDurationSeconds'] for r in matched),
                'minimumFullActiveCorrelation': min((r[name]['bestFullActiveCorrelation']
                                                       for r in matched), default=None),
                'maximumAbsoluteExternalJoinMs': max((abs(r[name]['externalGapBeforeMs'])
                                                        for r in matched
                                                        if r[name]['externalGapBeforeMs'] is not None), default=None)}
        result['timingViolations'] = [
            {'queueIndex': r['queueIndex'], 'capture': name,
             'residualMs': r[name]['orderedTimingResidualMs']}
            for r in result['packets'] for name in streams
            if r.get(name, {}).get('exceeds10msTimingPolicy')]
    except (ValueError, KeyError, TypeError, OSError) as error:
        result['errors'].append(str(error))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = compare(args.directory)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
    print(json.dumps({k: result.get(k) for k in ('diagnosticOnly', 'passed', 'errors', 'classificationCounts')}))
    return 1 if result['errors'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
