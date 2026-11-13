"""Inspect packet timing without weakening full-scene acoustic acceptance.

This is a diagnostic, not an acceptance substitute: every packet is compared
over its complete active waveform at the existing .98 threshold. It also checks
exact source PCM reconstruction and reports sub-sample boundary timing shifts.
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate, fftconvolve, resample_poly


def read(path):
    rate, values = wavfile.read(path)
    if np.issubdtype(values.dtype, np.integer):
        values = values.astype(np.float64) / 2 ** (8 * values.dtype.itemsize - 1)
    else:
        values = values.astype(np.float64)
    if values.ndim == 2:
        values = values.mean(axis=1)
    if values.ndim != 1 or not np.isfinite(values).all():
        raise ValueError('Invalid PCM')
    return rate, values


def resample(values, before, after):
    divisor = math.gcd(before, after)
    return resample_poly(values, after // divisor, before // divisor)


def match(window, template):
    if not len(template) or len(window) < len(template):
        raise ValueError('Capture does not contain the full active waveform')
    correlation = correlate(window, template, mode='valid', method='fft')
    power = fftconvolve(window * window, np.ones(len(template)), mode='valid')
    template_power = float(np.dot(template, template))
    scores = np.zeros_like(correlation)
    valid = power > max(len(template) * 1e-10, template_power * 1e-6)
    np.divide(correlation, np.sqrt(np.maximum(power, 0) * template_power),
              out=scores, where=valid)
    index = int(scores.argmax())
    return index, float(scores[index])


def diagnose(capture, reference, spool):
    capture_rate, captured = read(capture)
    source_rate, source = read(reference)
    packets = sorted(p for p in spool.glob('packet-*.wav') if '.onset-' not in p.name)
    packet_pcm = [read(p) for p in packets]
    if any(rate != source_rate for rate, _ in packet_pcm):
        raise ValueError('Packet format mismatch')
    raw = np.concatenate([pcm for _, pcm in packet_pcm])
    trim = len(raw) - len(source)
    if trim < 0 or not np.array_equal(raw[trim:], source):
        raise ValueError('Packets do not exactly reconstruct complete scene PCM')
    continuous = resample(source, source_rate, capture_rate)
    active = np.flatnonzero(np.abs(continuous) > .01)
    coarse_index, coarse_score = match(captured, continuous[active[0]:active[-1] + 1])
    scene_start = (coarse_index - active[0]) / capture_rate
    comparison_rate = capture_rate * 4
    captured = resample_poly(captured, 4, 1)
    records = []
    frame_start = 0
    for path, (_, pcm) in zip(packets, packet_pcm):
        skip = min(len(pcm), max(0, trim - frame_start))
        raw_start = frame_start
        frame_start += len(pcm)
        if skip == len(pcm):
            continue
        pcm = pcm[skip:]
        expected = scene_start + (raw_start + skip - trim) / source_rate
        template = resample(pcm, source_rate, comparison_rate)
        active = np.flatnonzero(np.abs(template) > .01)
        if not len(active):
            records.append({'packet': path.name, 'silent': True})
            continue
        start, end = int(active[0]), int(active[-1]) + 1
        low = max(0, round(expected * comparison_rate) - comparison_rate // 50)
        high = min(len(captured), round(expected * comparison_rate) + len(template) + comparison_rate // 50)
        index, score = match(captured[low:high], template[start:end])
        actual_start = (low + index - start) / comparison_rate
        records.append({'packet': path.name, 'rawFrameStart': raw_start,
                        'rawFrameCount': len(pcm) + skip,
                        'expectedSeconds': expected,
                        'captureStartSeconds': actual_start,
                        'residualCaptureFrames': (actual_start - expected) * capture_rate,
                        'fullActiveCorrelation': score,
                        'activeFirstFrame': start, 'activeEndFrame': end,
                        'activeComparisonFrames': end - start,
                        'activePower': float(np.dot(template[start:end], template[start:end]))})
    matched = [row for row in records if not row.get('silent')]
    jumps = [right['residualCaptureFrames'] - left['residualCaptureFrames']
             for left, right in zip(matched, matched[1:])]
    return {'reference': str(reference), 'spool': str(spool),
            'packetPcmExactlyReconstructsFinalScene': True,
            'captureRate': capture_rate, 'sourceRate': source_rate,
            'comparisonRate': comparison_rate, 'sourceFrames': len(source),
            'onsetTrimFrames': trim, 'coarseSceneStartSeconds': scene_start,
            'coarseContinuousCorrelation': coarse_score,
            'minimumFullActivePacketCorrelation': min(r['fullActiveCorrelation'] for r in matched),
            'maximumAbsoluteBoundaryResidualJumpCaptureFrames': max(map(abs, jumps), default=0),
            'packetsBelowStrictThreshold': [r['packet'] for r in matched if r['fullActiveCorrelation'] < .98],
            'packets': records,
            'limit': 'Diagnostic only; retain full-source/end coverage and strict .98 acceptance.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('reference', type=Path)
    parser.add_argument('spool', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = diagnose(args.capture, args.reference, args.spool)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
    print(json.dumps({k: v for k, v in result.items() if k != 'packets'}, indent=2))
