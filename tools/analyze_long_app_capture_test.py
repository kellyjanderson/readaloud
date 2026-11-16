"""Acoustic identity/join refusal tests; no native or semantic speech claims.

Changing harmonics and filtered nonperiodic noise identify each reference.
Each contains a long interior pause; joining complete artifacts preserves it.
Wrong middle/end PCM, inserted external silence and repeated placements must
refuse coverage. Metadata filenames deliberately oppose predecessor order.
"""
import copy
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, resample_poly, sosfilt

from analyze_long_app_capture import Capture, analyze, digest_file, identity, locate, scenes, source_stat
from process_tap_validation_test import clean_tap_timing


class LongCaptureTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scenes').mkdir()
        self.source = self.root / 'book.md'
        self.source.write_text('A bounded input fixture, not a speech transcript test.')
        self.source_hash = digest_file(self.source)
        self.rate = 8000
        self.pcm = []
        self.metadata = []
        predecessor = None
        source_id = 'file-stat-v2:' + json.dumps([str(self.source.resolve()), source_stat(self.source)])
        for i in range(3):
            t = np.arange(2 * self.rate) / self.rate
            rng = np.random.default_rng(77 + i)
            phase = 2 * np.pi * np.cumsum(120 + 30 * np.sin(t * (3 + i))) / self.rate
            voice = sum(np.sin(phase * h) / h for h in range(1, 10))
            noise = sosfilt(butter(3, [300, 3200], btype='bandpass', fs=self.rate, output='sos'),
                            rng.normal(size=len(t)))
            pcm = .13 * (voice + noise) * (.2 + .8 * np.sin(t * (4 + i)) ** 2)
            pcm[self.rate // 2:self.rate] = 0  # natural source-local half-second pause
            pcm[:160] = 0
            pcm[-240:] = 0
            self.pcm.append(pcm.astype(np.float32))
            raw_key = 'wav-sha256:' + str(i + 1) * 64
            raw = {'engineId': 'fish_drama3_8bit', 'text': f'scene {i}'}
            dependencies = {'raw': raw, 'predecessorRawArtifactIdentity': predecessor}
            m = {'schema': 1, 'sourceId': source_id, 'dependencies': dependencies,
                 'dependencyDigest': identity(dependencies), 'rawDependencyDigest': identity(raw),
                 'startWordIndex': i * 10, 'endWordIndex': (i + 1) * 10,
                 'sceneId': identity(['rendered-source-span-v1', source_id, i * 10, (i + 1) * 10]),
                 'provenance': {'rawArtifactIdentity': raw_key,
                                'predecessorRawArtifactIdentity': predecessor},
                 'sampleRate': self.rate, 'channels': 1, 'frameCount': len(pcm)}
            wav = self.root / 'reference.wav'
            wavfile.write(wav, self.rate, self.pcm[-1])
            key = digest_file(wav)
            folder = self.root / 'artifacts' / key / 'generation'
            folder.mkdir(parents=True)
            wav.rename(folder / 'audio.wav')
            m['audioArtifactIdentity'] = key
            self.metadata.append(m)
            predecessor = raw_key
        self.capture = np.concatenate([np.zeros(400), *self.pcm, np.zeros(300)])
        self.capture_path = self.root / 'capture.wav'

    def write_metadata(self):
        for i, m in enumerate(self.metadata):
            (self.root / 'scenes' / f'{99-i}.json').write_text(json.dumps(
                {'metadata': m, 'checksum': identity(m)}))

    def run_audit(self, minimum=5):
        self.write_metadata()
        wavfile.write(self.capture_path, self.rate, self.capture.astype(np.float32))
        return analyze(self.capture_path, self.root, self.source, self.source_hash, 123, minimum)

    def final_timing_audit(self, mutation=None):
        self.write_metadata()
        pcm = resample_poly(self.capture, 6, 1).astype(np.float32)
        wavfile.write(self.capture_path, 48000, pcm)
        timing = clean_tap_timing({'schema': 'readaloud-app-capture-timing-v1',
                                  'appPid': 123, 'frames': len(pcm), 'sampleRate': 48000})
        ready = {'schema': 'readaloud-process-capture-ready-v1', 'appPid': 123,
                 'sampleRate': 48000, 'sessionID': timing['sessionID']}
        if mutation:
            mutation(timing, ready)
        Path(str(self.capture_path) + '.timing.json').write_text(json.dumps(timing))
        Path(str(self.capture_path) + '.ready.json').write_text(json.dumps(ready))
        return analyze(self.capture_path, self.root, self.source, self.source_hash, 123, 5)

    def test_finalized_exact_pid_session_and_pcm(self):
        result = self.final_timing_audit()
        self.assertTrue(result['passed'], result)
        self.assertAlmostEqual(result['contiguousMatchedSeconds'], 6)

    def test_wrong_final_pid_or_session_or_loss_refuses(self):
        mutations = [lambda t, r: t.update(appPid=124),
                     lambda t, r: r.update(sessionID='00000000-0000-0000-0000-000000000000'),
                     lambda t, r: t.update(droppedBuffers=1),
                     lambda t, r: t.update(framesReceived=t['frames'] - 1)]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                result = self.final_timing_audit(mutation)
                self.assertFalse(result['passed'])
                self.assertTrue(result['errors'])

    def test_ordered_full_waveforms_and_internal_pauses(self):
        result = self.run_audit()
        self.assertTrue(result['acousticBoundedPassed'], result)
        self.assertFalse(result['passed'])  # absent final timing always refuses final qualification
        self.assertIn('Provisional', result['errors'][0])
        self.assertEqual([m['startWordIndex'] for m in result['matches']], [0, 10, 20])
        self.assertAlmostEqual(result['contiguousMatchedSeconds'], 6)
        self.assertTrue(all(abs(m['externalGapBeforeMs'] or 0) < .2 for m in result['matches']))

    def test_changed_middle_with_same_prefix_and_ending_refuses(self):
        start = 400 + 3 * self.rate
        self.capture[start + 800:start + 4000] = self.pcm[2][800:4000]
        result = self.run_audit()
        self.assertFalse(result['passed'])
        self.assertEqual(len(result['matches']), 1)
        self.assertIsNotNone(result['unmatchedNextReference'])

    def test_full_context_cannot_substitute_for_active_span_identity(self):
        # Almost all energy is low-level context, so it can still score >.98
        # when a short audible event is replaced. The separate fixed-placement
        # active-span score must reject that replacement.
        rng = np.random.default_rng(91)
        pcm = .009 * rng.choice([-1., 1.], size=10 * self.rate)
        a, b = 3 * self.rate, 3 * self.rate + 480
        pcm[a:b] = .012 * rng.choice([-1., 1.], size=b-a)
        emitted = pcm.copy()
        emitted[a:b] = .012 * rng.choice([-1., 1.], size=b-a)
        index, active, context = locate(emitted, pcm, a, b, self.rate)
        self.assertGreater(context, .98)
        self.assertLess(active, .1)
        self.assertIsNone(index)

    def test_missing_reference_is_not_skipped(self):
        self.metadata.pop(1)
        result = self.run_audit()
        self.assertIn('Missing predecessor', result['errors'][0])
        self.assertFalse(result['passed'])

    def test_external_gap_is_not_source_internal_pause(self):
        self.capture = np.concatenate([np.zeros(400), self.pcm[0], np.zeros(800), *self.pcm[1:]])
        result = self.run_audit()
        self.assertIn('External join gap', result['errors'][0])
        self.assertFalse(result['acousticBoundedPassed'])
        self.assertAlmostEqual(result['matches'][1]['externalGapBeforeMs'], 100)

    def test_repeated_full_waveform_is_ambiguous(self):
        self.capture = np.concatenate([np.zeros(400), self.pcm[0], self.pcm[0], *self.pcm[1:]])
        result = self.run_audit()
        self.assertIn('Ambiguous repeated waveform', result['errors'][0])
        self.assertFalse(result['passed'])

    def test_ambiguous_fork_does_not_use_filename_or_clock(self):
        self.metadata[2]['provenance']['predecessorRawArtifactIdentity'] = self.metadata[0]['provenance']['rawArtifactIdentity']
        self.metadata[2]['dependencies']['predecessorRawArtifactIdentity'] = self.metadata[0]['provenance']['rawArtifactIdentity']
        self.metadata[2]['dependencyDigest'] = identity(self.metadata[2]['dependencies'])
        result = self.run_audit()
        self.assertIn('Missing predecessor', result['errors'][0])

    def test_same_raw_utterance_at_distinct_spans_has_unambiguous_lineage(self):
        # Identical speech can occur again later with a distinct predecessor
        # and different final boundary padding. Raw ID is not a unique node ID.
        self.metadata[2]['provenance']['rawArtifactIdentity'] = self.metadata[0]['provenance']['rawArtifactIdentity']
        self.write_metadata()
        chain, _ = scenes(self.root, self.source)
        self.assertEqual([s['metadata']['startWordIndex'] for s in chain], [0, 10, 20])
        self.assertEqual(chain[0]['rawIdentity'], chain[2]['rawIdentity'])

    def test_multiple_versions_of_same_span_refuse(self):
        self.metadata.append(copy.deepcopy(self.metadata[1]))
        result = self.run_audit()
        self.assertIn('Ambiguous duplicate reference/span', result['errors'][0])

    def test_metadata_checksum_mismatch_refuses(self):
        self.write_metadata()
        path = self.root / 'scenes' / '99.json'
        x = json.loads(path.read_text())
        x['metadata']['dependencies']['raw']['text'] = 'wrong scene'
        path.write_text(json.dumps(x))
        wavfile.write(self.capture_path, self.rate, self.capture.astype(np.float32))
        result = analyze(self.capture_path, self.root, self.source, self.source_hash, 123, 5)
        self.assertIn('Scene metadata checksum mismatch', result['errors'][0])

    def test_old_source_stat_cannot_bind_current_file_hash(self):
        for m in self.metadata:
            m['sourceId'] = 'file-stat-v2:' + json.dumps([str(self.source.resolve()), 'old-stat'])
        result = self.run_audit()
        self.assertIn('Scene source stat revision mismatch', result['errors'][0])

    def test_zero_reference_cannot_establish_identity(self):
        path = self.root / 'silent.wav'
        wavfile.write(path, self.rate, np.zeros(2 * self.rate, dtype=np.float32))
        key = digest_file(path)
        folder = self.root / 'artifacts' / key / 'generation'
        folder.mkdir(parents=True)
        path.rename(folder / 'audio.wav')
        self.metadata[1]['audioArtifactIdentity'] = key
        result = self.run_audit()
        self.assertIn('Near-silent reference', result['errors'][0])
        self.assertFalse(result['passed'])

    def test_nonfinite_capture_is_not_accepted_as_quiet(self):
        self.capture[-1] = np.nan
        result = self.run_audit()
        self.assertIn('Nonfinite/out-of-range capture PCM', result['errors'][0])

    def test_pcm_reader_rejects_unbounded_read(self):
        self.run_audit()
        wav = bytearray(self.capture_path.read_bytes())
        pos = wav.index(b'data')
        wav[pos + 4:pos + 8] = b'\0' * 4
        self.capture_path.write_bytes(wav)
        with self.capture_path.open('r+b') as stream:
            stream.truncate(pos + 8 + 160 * self.rate * 4)
        capture = Capture(self.capture_path)
        with self.assertRaisesRegex(ValueError, 'bounded search window'):
            capture.read(0, 160 * self.rate)

    def test_tap_clock_and_silent_tail_do_not_supply_duration(self):
        self.capture = np.concatenate([self.capture, np.zeros(self.rate * 20)])
        result = self.run_audit(minimum=20)
        self.assertIn('below required', result['errors'][0])
        self.assertAlmostEqual(result['contiguousMatchedSeconds'], 6)
        self.assertFalse(result['passed'])

    def test_incomplete_tail_is_not_credited(self):
        self.capture = self.capture[:400 + 5 * self.rate]
        result = self.run_audit()
        self.assertEqual(len(result['matches']), 2)
        self.assertIsNotNone(result['unmatchedNextReference'])
        self.assertAlmostEqual(result['contiguousMatchedSeconds'], 4)
        self.assertFalse(result['passed'])

    def test_corrupt_reference_refuses(self):
        key = self.metadata[1]['audioArtifactIdentity']
        wavfile.write(next((self.root / 'artifacts' / key).glob('*/audio.wav')),
                      self.rate, self.pcm[2])
        result = self.run_audit()
        self.assertIn('Reference SHA256', result['errors'][0])

    def test_source_revision_mismatch_refuses(self):
        self.source.write_text('Different source')
        result = self.run_audit()
        self.assertIn('Input source SHA256', result['errors'][0])

    def test_exact_engine_filter(self):
        other = copy.deepcopy(self.metadata[0])
        other['dependencies']['raw']['engineId'] = 'kokoro'
        # Invalid irrelevant engine metadata cannot become a Fish source.
        (self.root / 'scenes' / 'kokoro.json').write_text(json.dumps({'metadata': other}))
        result = self.run_audit()
        self.assertEqual(result['excludedMetadataCount'], 1)
        self.assertEqual(len(result['matches']), 3)

    def test_open_zero_data_header_snapshot(self):
        self.run_audit()
        wav = bytearray(self.capture_path.read_bytes())
        pos = wav.index(b'data')
        wav[pos + 4:pos + 8] = b'\0' * 4
        self.capture_path.write_bytes(wav)
        capture = Capture(self.capture_path)
        self.assertEqual(capture.frames, len(self.capture))
        self.assertEqual(len(capture.read(0, 160)), 160)


if __name__ == '__main__':
    unittest.main()
