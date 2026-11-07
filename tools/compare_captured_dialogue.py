"""Compare a short native app capture with the exact queued speech WAVs.

Use the managed MLX Python (numpy/scipy already installed). This proves acoustic
presence/order and measures joins, not transcript correctness or perceived voice
identity. Only the initial completed pass is compared; transport retries follow.
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate, fftconvolve, resample_poly


def read_mono(path):
    rate, pcm = wavfile.read(path)
    if np.issubdtype(pcm.dtype, np.integer):
        pcm = pcm.astype(np.float64) / (2 ** (8 * pcm.dtype.itemsize - 1))
    else:
        pcm = pcm.astype(np.float64)
    if pcm.ndim == 2:
        pcm = pcm.mean(axis=1)
    if pcm.ndim != 1 or not np.isfinite(pcm).all():
        raise ValueError('Invalid captured PCM')
    return rate, pcm


def compare(receipt, capture_path):
    capture_rate, captured = read_mono(capture_path)
    capture_peak = float(np.abs(captured).max())
    # System mixing places a 44.1 kHz source at fractional 48 kHz sample offsets.
    # Fourfold interpolation resolves that phase instead of weakening the
    # waveform-match threshold for noisy/whispered speech.
    rate = capture_rate * 4
    captured = resample_poly(captured, 4, 1)
    chunks = receipt['spokenChunks']
    paths = receipt['audioPaths'][:len(chunks)]
    if not chunks or len(paths) != len(chunks) or not all(c['completed'] for c in chunks):
        raise ValueError('Requires a completed first dialogue pass')
    cursor = 0
    previous_end = None
    matches = []
    for chunk, path in zip(chunks, paths):
        source_rate, source = read_mono(path)
        divisor = math.gcd(source_rate, rate)
        source = resample_poly(source, rate // divisor, source_rate // divisor)
        # Interior speech avoids a boundary fade being treated as a missing turn.
        active = np.flatnonzero(np.abs(source) > .01)
        if len(active) < rate // 10:
            raise ValueError('Near-silent reference cannot prove a spoken turn')
        start = int(active[0])
        end = int(active[-1]) + 1
        template = source[start:end]
        if len(captured) - cursor < len(template):
            raise ValueError('Capture ended before all turns could be compared')
        window = captured[cursor:]
        correlation = correlate(window, template, mode='valid', method='fft')
        power = fftconvolve(window * window, np.ones(len(template)), mode='valid')
        template_power = np.dot(template, template)
        # FFT roundoff in silence is not acoustic evidence. Reject windows
        # below a meaningful energy floor before normalizing correlation.
        valid = power > max(len(template) * 1e-10, template_power * 1e-6)
        scores = np.zeros_like(correlation)
        np.divide(correlation, np.sqrt(np.maximum(power, 0) * template_power),
                  out=scores, where=valid)
        # Match the complete active waveform, including its ending. Record the
        # earliest ordered occurrence; audio outside that interval is not judged.
        candidates = np.flatnonzero(scores >= .98)
        if not len(candidates):
            raise ValueError(f'No acoustic match for source span {chunk["startWord"]}:{chunk["endWord"]}; best={scores.max():.3f}')
        first = int(candidates[0])
        vicinity = scores[first:min(len(scores), first + rate // 20)]
        matched = cursor + first + int(vicinity.argmax())
        source_start = (matched - start) / rate
        gap = None if previous_end is None else source_start - previous_end
        score = float(scores[matched - cursor])
        matches.append({
            'startWord': chunk['startWord'], 'endWord': chunk['endWord'],
            'castId': chunk['castId'], 'voiceId': chunk['voiceId'],
            'captureStartSeconds': source_start, 'correlation': score,
            'activeSpeechStartSeconds': matched / rate,
            'gapBeforeMs': None if gap is None else round(gap * 1000, 2),
        })
        previous_end = source_start + len(source) / rate
        cursor = max(cursor + 1, round((previous_end - .05) * rate))
    gaps = [m['gapBeforeMs'] for m in matches if m['gapBeforeMs'] is not None]
    return {
        'captureSampleRate': capture_rate, 'comparisonSampleRate': rate,
        'capturePeak': capture_peak,
        'matchedTurns': matches, 'firstSpeechStartSeconds': matches[0]['captureStartSeconds'],
        'lastSpeechEndSeconds': previous_end,
        'maxJoinGapMs': max(gaps, default=0),
        'passed': all(-50 <= gap <= 250 for gap in gaps),
        'limit': 'Queued-waveform presence/order and joins only; human expression/identity/transcript review required.',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('receipt', type=Path)
    parser.add_argument('capture', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = compare(json.loads(args.receipt.read_text()), args.capture)
    with args.output.open('x') as target:
        json.dump(result, target, indent=2)
    print(json.dumps({k: result[k] for k in ('passed', 'maxJoinGapMs', 'capturePeak')}))
    raise SystemExit(0 if result['passed'] else 1)
