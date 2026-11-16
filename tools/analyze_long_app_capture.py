#!/usr/bin/env python3
"""Bounded ordinary-app emitted-waveform audit, without invented queue receipts.

Use managed MLX Python (numpy/scipy). Example:
  analyze_long_app_capture.py CAPTURE.wav RENDERED_SCENES SOURCE.md SOURCE_SHA256 \
    OUTPUT.json --app-pid PID [--minimum-seconds 1800]

RENDERED_SCENES contains scenes/ and artifacts/. Exact metadata selects Fish8 and
orders its raw predecessor chain; filenames and commit clocks never order it.
The first complete acoustic anchor may follow an unwitnessed prefix. Every next
reference must match completely, including its interior pauses, at one unique
placement. Joins compare complete final artifact ends, not detected speech edges.
Only the contiguous, fully matched interval is credited. Capture age, silence,
prepared scene count and the final tap clock cannot supply missing coverage.

Memory is bounded by one <=120s reference plus a <=30s search neighborhood;
capture PCM is read in slices, including while its RIFF header is unfinalized.
A growing-file result is provisional and can NEVER pass final qualification.
No transcript correctness, voice quality, startup, responsiveness, physical
speaker output, whole-book completeness or human listening is established.
"""
import argparse
import hashlib
import json
import math
import re
import struct
from pathlib import Path

import numpy as np
from scipy.signal import correlate

from analyze_s7_variants import THRESHOLD, load_json, read_audio, require, resample
from process_tap_validation import validate_process_tap

ENGINE = 'fish_drama3_8bit'
MAX_SCENES = 10000
MAX_REFERENCE_SECONDS = 120
MAX_REFERENCE_BYTES = 64_000_000
SEARCH_SECONDS = 30
NEXT_SEARCH_SECONDS = 2
MAX_GAP_MS = 10
SHA = re.compile(r'[0-9a-f]{64}')


def digest_file(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()


def identity(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                    separators=(',', ':'), allow_nan=False).encode()).hexdigest()


class Capture:
    """A fixed-size snapshot; never read newly appended frames during an audit."""
    def __init__(self, path):
        self.path = Path(path)
        self.stat = self.path.stat()
        require(44 <= self.stat.st_size <= 8_000_000_000, 'Capture byte bound')
        self.declared_bytes = None
        fmt = None
        with self.path.open('rb') as stream:
            require(stream.read(4) == b'RIFF', 'Requires little-endian RIFF WAV')
            stream.read(4)
            require(stream.read(4) == b'WAVE', 'Invalid WAV')
            while stream.tell() < min(self.stat.st_size, 65536):
                header = stream.read(8)
                require(len(header) == 8, 'Truncated WAV chunk')
                tag, size = struct.unpack('<4sI', header)
                if tag == b'data':
                    self.offset = stream.tell()
                    self.declared_bytes = size
                    break
                if tag == b'fmt ':
                    require(16 <= size <= 4096, 'Unsupported WAV format size')
                    fmt = struct.unpack('<HHIIHH', stream.read(16))
                    stream.seek(size - 16, 1)
                else:
                    require(size <= 65536, 'Oversized WAV header chunk')
                    stream.seek(size, 1)
                stream.seek(size % 2, 1)
        require(fmt is not None and self.declared_bytes is not None, 'Missing WAV fmt/data')
        kind, self.channels, self.rate, byte_rate, block, bits = fmt
        require(self.channels in (1, 2) and 8000 <= self.rate <= 192000,
                'Unsupported capture channels/rate')
        self.dtype = {(1, 16): '<i2', (1, 32): '<i4', (3, 32): '<f4',
                      (3, 64): '<f8'}.get((kind, bits))
        require(self.dtype is not None and block == self.channels * (bits // 8)
                and byte_rate == self.rate * block, 'Unsupported capture PCM')
        self.block = block
        self.frames = (self.stat.st_size - self.offset) // block
        require(0 < self.frames <= self.rate * 7200, 'Capture duration bound')
        require((self.stat.st_size - self.offset) % block == 0, 'Partial capture frame')
        # An open CoreAudio WAV has a zero data count. Finalized files must have
        # exactly one terminal data payload; trailing chunks are unsupported.
        require(self.declared_bytes in (0, self.frames * block), 'WAV data size mismatch')

    def read(self, begin, end):
        begin, end = max(0, int(begin)), min(self.frames, int(end))
        require(begin <= end and end - begin <= self.rate * (MAX_REFERENCE_SECONDS + SEARCH_SECONDS + 2),
                'PCM read exceeds bounded search window')
        with self.path.open('rb') as stream:
            stream.seek(self.offset + begin * self.block)
            raw = stream.read((end - begin) * self.block)
        require(len(raw) == (end - begin) * self.block, 'Capture truncated during audit')
        pcm = np.frombuffer(raw, dtype=self.dtype).astype(np.float64)
        if self.dtype[1] == 'i':
            pcm /= 2 ** (np.dtype(self.dtype).itemsize * 8 - 1)
        require(np.isfinite(pcm).all() and (not len(pcm) or np.max(np.abs(pcm)) <= 1.01),
                'Nonfinite/out-of-range capture PCM')
        return pcm.reshape(-1, self.channels).mean(axis=1)

    def summary(self):
        peak, active = 0., 0
        for start in range(0, self.frames, self.rate * 20):
            pcm = self.read(start, min(self.frames, start + self.rate * 20))
            peak = max(peak, float(np.max(np.abs(pcm))))
            active += int(np.count_nonzero(np.abs(pcm) > .01))
        return {'frames': self.frames, 'sampleRate': self.rate,
                'seconds': self.frames / self.rate, 'bytes': self.stat.st_size,
                'peak': peak, 'aboveThresholdSeconds': active / self.rate,
                'sha256OfSnapshot': digest_prefix(self.path, self.stat.st_size)}


def digest_prefix(path, size):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while size:
            block = stream.read(min(size, 1024 * 1024))
            require(block, 'Capture truncated during snapshot hash')
            h.update(block)
            size -= len(block)
    return h.hexdigest()


def scenes(root, source_path):
    paths = list((root / 'scenes').rglob('*.json'))
    require(len(paths) <= MAX_SCENES, 'Scene count bound')
    selected = []
    excluded = 0
    for path in paths:
        envelope = load_json(path)
        m = envelope.get('metadata', {})
        raw = m.get('dependencies', {}).get('raw', {})
        if raw.get('engineId') != ENGINE:
            excluded += 1
            continue
        source = m.get('sourceId', '')
        require(source.startswith('file-stat-v2:'), 'Unsupported source identity')
        source_parts = json.loads(source[len('file-stat-v2:'):])
        require(isinstance(source_parts, list) and len(source_parts) == 2
                and all(isinstance(p, str) for p in source_parts), 'Invalid file source revision')
        if str(Path(source_parts[0]).resolve()) != str(source_path.resolve()):
            excluded += 1
            continue
        require(source_parts[1] == source_stat(source_path), 'Scene source stat revision mismatch')
        require(envelope.get('checksum') == identity(m), 'Scene metadata checksum mismatch')
        require(m.get('schema') == 1 and m.get('dependencyDigest') == identity(m['dependencies'])
                and m.get('rawDependencyDigest') == identity(raw), 'Scene dependency digest mismatch')
        a, b = m.get('startWordIndex'), m.get('endWordIndex')
        require(type(a) is int and type(b) is int and 0 <= a < b
                and m.get('sceneId') == identity(['rendered-source-span-v1', source, a, b]),
                'Scene source span identity mismatch')
        provenance = m.get('provenance', {})
        key = provenance.get('rawArtifactIdentity')
        predecessor = provenance.get('predecessorRawArtifactIdentity')
        require(isinstance(key, str) and key.startswith('wav-sha256:') and SHA.fullmatch(key[11:]),
                'Missing raw artifact identity')
        require(predecessor == m['dependencies'].get('predecessorRawArtifactIdentity'),
                'Contradictory predecessor identity')
        selected.append({'metadataPath': str(path), 'metadata': m, 'rawIdentity': key,
                         'predecessor': predecessor, 'metadataChecksum': envelope['checksum']})
    require(selected, 'No exact Fish8 source references')
    require(len({s['metadata']['sourceId'] for s in selected}) == 1,
            'Ambiguous source stat revisions')
    children = {}
    spans = set()
    for scene in selected:
        key = scene['rawIdentity']
        m = scene['metadata']
        span = (m['startWordIndex'], m['endWordIndex'])
        require(span not in spans, 'Ambiguous duplicate reference/span')
        spans.add(span)
        children.setdefault(scene['predecessor'], []).append(scene)
    roots = children.get(None, [])
    require(len(roots) == 1,
            'Missing predecessor or ambiguous chain roots')
    ordered, current = [], roots[0]
    while current:
        require(current not in ordered, 'Scene predecessor cycle')
        if ordered:
            require(ordered[-1]['metadata']['endWordIndex'] == current['metadata']['startWordIndex'],
                    'Missing or overlapping source word coverage')
        ordered.append(current)
        # The same raw utterance can legitimately occur at different source
        # spans. It is not a unique node key. Predecessor identity and adjacent
        # canonical word bounds together resolve the next scene; neither file
        # names nor publication time can resolve an otherwise ambiguous branch.
        candidates = [s for s in children.get(current['rawIdentity'], [])
                      if s['metadata']['startWordIndex'] == current['metadata']['endWordIndex']]
        require(len(candidates) <= 1, 'Ambiguous predecessor fork')
        current = candidates[0] if candidates else None
    require(len(ordered) == len(selected), 'Missing predecessor or disconnected source coverage')
    return ordered, excluded


def source_stat(path):
    """Match macOS file-stat-v2 nanoseconds without lossy float timestamps."""
    s = path.stat()
    def stamp(ns):
        return f'{ns // 1_000_000_000}.{ns % 1_000_000_000:09d}'
    return ':'.join([str(s.st_dev), str(s.st_ino), str(getattr(s, 'st_gen', 0)),
                     str(s.st_size), stamp(s.st_mtime_ns), stamp(s.st_ctime_ns),
                     format(s.st_mode, 'o'), 'Regular File'])


def reference(root, scene, rate):
    m = scene['metadata']
    key = m.get('audioArtifactIdentity', '')
    require(isinstance(key, str) and SHA.fullmatch(key), 'Invalid final artifact identity')
    candidates = list((root / 'artifacts' / key).glob('*/audio.wav'))
    require(len(candidates) == 1, 'Missing or ambiguous final audio artifact')
    path = candidates[0]
    require(path.stat().st_size <= MAX_REFERENCE_BYTES and digest_file(path) == key,
            'Reference SHA256/size mismatch')
    original_rate, pcm, channels, _ = read_audio(path, MAX_REFERENCE_BYTES, MAX_REFERENCE_SECONDS)
    require(channels == m.get('channels') == 1 and original_rate == m.get('sampleRate')
            and len(pcm) == m.get('frameCount'), 'Reference PCM metadata mismatch')
    pcm = resample(pcm, original_rate, rate) if original_rate != rate else pcm
    active = np.flatnonzero(np.abs(pcm) > .01)
    require(len(active) > .05 * rate, 'Near-silent reference has no reliable acoustic identity')
    return pcm, int(active[0]), int(active[-1]) + 1, str(path), key


def locate(window, pcm, active_start, active_end, rate):
    """Unique full-context placement, then entire active span at that placement."""
    if len(window) < len(pcm):
        return None, 0., 0.
    energy = float(np.dot(pcm, pcm))
    require(energy > len(pcm) * 1e-8, 'Near-silent reference')
    dots = correlate(window, pcm, mode='valid', method='fft')
    cumulative = np.concatenate(([0.], np.cumsum(window * window)))
    powers = np.maximum(cumulative[len(pcm):] - cumulative[:-len(pcm)], 0)
    scores = np.zeros_like(dots)
    np.divide(dots, np.sqrt(powers * energy), out=scores,
              where=powers > max(len(pcm) * 1e-10, energy * 1e-6))
    require(np.isfinite(scores).all(), 'Nonfinite acoustic correlation')
    qualified = np.flatnonzero(scores >= THRESHOLD)
    if not len(qualified):
        return None, 0., float(scores.max())
    peak = int(np.argmax(scores))
    require(not np.any(np.abs(qualified - peak) > round(rate * .05)),
            'Ambiguous repeated waveform placements')
    active = pcm[active_start:active_end]
    emitted = window[peak + active_start:peak + active_end]
    denominator = math.sqrt(float(np.dot(active, active)) * float(np.dot(emitted, emitted)))
    score = float(np.dot(active, emitted)) / denominator if denominator else 0.
    return (peak if score >= THRESHOLD else None), score, float(scores[peak])


def analyze(capture_path, root, source, source_sha256, app_pid, minimum_seconds=1800):
    result = {'schema': 'readaloud-long-ordinary-acoustic-v1', 'passed': False,
              'acousticBoundedPassed': False, 'engineId': ENGINE, 'errors': [], 'matches': [],
              'minimumMatchedSeconds': minimum_seconds,
              'correlationThreshold': THRESHOLD, 'maximumExternalJoinMs': MAX_GAP_MS,
              'bounds': {'maximumCaptureSeconds': 7200, 'maximumReferenceSeconds': MAX_REFERENCE_SECONDS,
                         'initialSearchSeconds': SEARCH_SECONDS, 'nextSearchSeconds': NEXT_SEARCH_SECONDS,
                         'maximumUnobservedPrefixReferences': 31},
              'limits': ['Warm partial source coverage only; no queue or native playback receipt.',
                         'No semantic, voice-quality, startup, UI, physical-output or listening claim.',
                         'Scene publication is not evidence that a scene was played.']}
    try:
        root, source = Path(root), Path(source)
        require(SHA.fullmatch(source_sha256) and digest_file(source) == source_sha256,
                'Input source SHA256 mismatch')
        require(type(app_pid) is int and app_pid > 0 and 0 < minimum_seconds <= 7200,
                'Invalid expected PID/minimum duration')
        initial_source_stat = source_stat(source)
        result['source'] = {'path': str(source.resolve()), 'sha256': source_sha256}
        chain, excluded = scenes(root, source)
        result.update(referenceCount=len(chain), excludedMetadataCount=excluded)
        result['referenceChainChecksum'] = identity([s['metadataChecksum'] for s in chain])
        result['source']['fileStatRevision'] = chain[0]['metadata']['sourceId']
        captured = Capture(capture_path)
        result['capture'] = captured.summary()
        timing_path = Path(str(capture_path) + '.timing.json')
        finalized = timing_path.is_file()
        result['finalizedTiming'] = finalized
        result['measurementStatus'] = 'final' if finalized else 'provisional'
        if finalized:
            timing = load_json(timing_path)
            ready_path = Path(str(capture_path) + '.ready.json')
            ready = load_json(ready_path)
            require(ready.get('schema') == 'readaloud-process-capture-ready-v1'
                    and ready.get('appPid') == app_pid and ready.get('sampleRate') == captured.rate,
                    'Missing/mismatched initial tap session witness')
            validate_process_tap(timing, app_pid, captured.frames, captured.rate, ready.get('sessionID'))
            require(isinstance(ready.get('sessionID'), str), 'Missing initial tap session identity')
            require(captured.declared_bytes == captured.frames * captured.block,
                    'Finalized WAV header incomplete')
            result['timingSha256'] = digest_file(timing_path)
            result['readySha256'] = digest_file(ready_path)
            result['sessionID'] = timing.get('sessionID')
        cursor = None
        first_number = None
        stop_reason = None
        for number, scene in enumerate(chain):
            pcm, active_a, active_b, path, key = reference(root, scene, captured.rate)
            if cursor is None:
                require(number < 32, 'No complete initial anchor within first 32 references')
                begin = 0
                finish = min(captured.frames, len(pcm) + captured.rate * SEARCH_SECONDS)
            else:
                begin = max(0, cursor - round(captured.rate * .05))
                finish = min(captured.frames, cursor + len(pcm) + captured.rate * NEXT_SEARCH_SECONDS)
            index, active_score, context_score = locate(captured.read(begin, finish), pcm,
                                                       active_a, active_b, captured.rate)
            if index is None:
                if cursor is None:
                    continue
                # No partial source is credited. A tail is reported, never
                # silently excluded as a witnessed Pause/EOF or a successful join.
                stop_reason = {'referenceIndex': number, 'rawIdentity': scene['rawIdentity'],
                               'reason': 'No complete next waveform; missing/mismatched or unwitnessed tail',
                               'bestContextCorrelation': context_score,
                               'bestActiveCorrelation': active_score,
                               'expectedStartSeconds': cursor / captured.rate,
                               'remainingCaptureSeconds': (captured.frames - cursor) / captured.rate}
                break
            start = begin + index
            gap_ms = None if cursor is None else (start - cursor) / captured.rate * 1000
            if first_number is None:
                first_number = number
            result['matches'].append({'referenceIndex': number, 'rawIdentity': scene['rawIdentity'],
                                      'predecessor': scene['predecessor'], 'metadataPath': scene['metadataPath'],
                                      'metadataChecksum': scene['metadataChecksum'],
                                      'audioPath': path, 'audioSha256': key,
                                      'sourceContext': {
                                          k: scene['metadata']['dependencies']['raw'].get(k)
                                          for k in ('engineId', 'engineVersion', 'normalizationVersion',
                                                    'capabilityProfileId', 'synthesisIdentity',
                                                    'translationSignature', 'synthesisRate')},
                                      'rawDependencyDigest': scene['metadata']['rawDependencyDigest'],
                                      'dependencyDigest': scene['metadata']['dependencyDigest'],
                                      'boundaryPolicyVersion': scene['metadata']['provenance'].get('boundaryPolicyVersion'),
                                      'startWordIndex': scene['metadata']['startWordIndex'],
                                      'endWordIndex': scene['metadata']['endWordIndex'],
                                      'captureStartSeconds': start / captured.rate,
                                      'captureEndSeconds': (start + len(pcm)) / captured.rate,
                                      'sourceDurationSeconds': len(pcm) / captured.rate,
                                      'activeSpanSeconds': (active_b - active_a) / captured.rate,
                                      'fullActiveCorrelation': active_score,
                                      'fullReferenceCorrelation': context_score,
                                      'externalGapBeforeMs': gap_ms})
            if gap_ms is not None:
                require(abs(gap_ms) <= MAX_GAP_MS,
                        f'External join gap/overlap {gap_ms:.3f}ms at reference {number}')
            cursor = start + len(pcm)
        require(result['matches'], 'No complete emitted waveform coverage')
        matched = result['matches']
        interval = matched[-1]['captureEndSeconds'] - matched[0]['captureStartSeconds']
        result.update(completeReferenceSeconds=sum(m['sourceDurationSeconds'] for m in matched),
                      contiguousMatchedSeconds=interval,
                      unobservedPrefixReferences=first_number,
                      unobservedCapturePrefixSeconds=matched[0]['captureStartSeconds'],
                      unobservedCaptureTailSeconds=captured.frames / captured.rate - matched[-1]['captureEndSeconds'],
                      unmatchedNextReference=stop_reason,
                      preparedReferencesAfterMatches=len(chain) - matched[-1]['referenceIndex'] - 1)
        result['acousticBoundedPassed'] = True
        require(interval >= minimum_seconds,
                f'Fully matched contiguous interval {interval:.3f}s below required {minimum_seconds}s')
        require(source_stat(source) == initial_source_stat, 'Source changed during audit')
        require(finalized, 'Provisional growing capture: no finalized process-tap timing')
        final_stat = Path(capture_path).stat()
        require(final_stat.st_size == captured.stat.st_size and final_stat.st_mtime_ns == captured.stat.st_mtime_ns,
                'Capture changed during final audit')
        result['passed'] = True
        result['scope'] = 'Finalized process-tap integrity plus bounded contiguous full-waveform interval only'
    except (ValueError, KeyError, TypeError, OSError, IndexError, struct.error) as error:
        result['errors'].append(str(error))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('rendered_scenes', type=Path)
    parser.add_argument('source', type=Path)
    parser.add_argument('source_sha256')
    parser.add_argument('output', type=Path)
    parser.add_argument('--app-pid', type=int, required=True)
    parser.add_argument('--minimum-seconds', type=float, default=1800)
    args = parser.parse_args()
    require(not args.output.exists(), 'Output exists; preserve earlier evidence')
    result = analyze(args.capture, args.rendered_scenes, args.source, args.source_sha256,
                     args.app_pid, args.minimum_seconds)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    print(json.dumps({k: result.get(k) for k in ('passed', 'acousticBoundedPassed',
                     'contiguousMatchedSeconds', 'errors')}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
