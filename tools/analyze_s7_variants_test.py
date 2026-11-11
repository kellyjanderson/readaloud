"""Synthetic waveform identity/timing tests; not native or human audio acceptance.

Distinct speech-shaped packets contain changing harmonics, shaped noise and
encoded natural pauses. Their identity, complete ending and relative placement
are the feature under test; no transcript or perceived speech claim is made.
"""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, resample_poly, sosfilt

from analyze_s7_variants import analyze, load_json, read_audio


class S7VariantAcceptanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.origin = 1_800_000_000_000_000
        cls.rate = 48000
        cls.sources = []
        cls.queued = []
        source_rate = 8000
        for number, duration in enumerate([11, 11, 11, 11, 11, 10]):
            rng = np.random.default_rng(number + 23)
            t = np.arange(duration * source_rate) / source_rate
            # Nonperiodic phoneme-like changes prevent a tone/prefix from
            # matching an unrelated packet or a missing/repeated ending.
            pitch = 110 + 35 * np.sin(t * (1.4 + number * .1)) + 9 * np.sin(t * 7.3)
            phase = 2 * np.pi * np.cumsum(pitch) / source_rate
            voiced = sum(np.sin(phase * h) / h for h in range(1, 14))
            noise = sosfilt(butter(3, [300, 3200], btype='bandpass', fs=source_rate, output='sos'),
                            rng.normal(size=len(t)))
            envelope = .25 + .75 * np.sin(t * (5.2 + number * .13)) ** 2
            pcm = (1800 * envelope * (voiced + noise)).astype(np.int16)
            # A natural 600ms pause belongs to the source and is not an external
            # join. Active waveform matching still spans both sides of it.
            pcm[4 * source_rate:round(4.6 * source_rate)] = 0
            path = cls.root / f'copied-{99 - number}.wav'  # filenames oppose queue order
            wavfile.write(path, source_rate, pcm)
            cls.sources.append(resample_poly(pcm.astype(np.float64) / 32768, 6, 1))
            cls.queued.append({
                'engineIndex': 0, 'engineId': 'fish_drama3_8bit',
                'sourcePath': f'/production/path/source-{number}.wav',
                'queuedUnixMicros': cls.origin + 100_000,
                'reference': {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                              'bytes': path.stat().st_size, 'sampleRate': source_rate,
                              'channels': 1, 'bitsPerSample': 16},
            })
        samples = []
        for sample_time in np.arange(.35, 60.3, .1):
            played = sample_time - .25
            number = min(int(played // 11), 5)
            samples.append({'unixMicros': cls.origin + round(sample_time * 1e6),
                            'engineIndex': 0, 'playing': True,
                            'source': Path(cls.queued[number]['sourcePath']).as_uri(),
                            'positionMs': round((played - number * 11) * 1000)})
        cls.native = {
            'schema': 'readaloud-native-variant-v1', 'mode': 'cached-8bit',
            'passed': True, 'functionalPassed': True, 'resourceShutdownComplete': True,
            'shutdownErrors': [], 'observationErrors': [], 'maxUiHeartbeatDelayMs': 100,
            'nativeMainResponsiveness': {'passed': True, 'error': None, 'samples': 600,
                                        'applicationActiveSamples': 550, 'maxRoundTripMs': 120},
            'queuedAudio': cls.queued, 'playerSamples': samples,
            'segments': [{'label': 'sustained-fish_drama3_8bit', 'engineIndex': 0,
                          'engineId': 'fish_drama3_8bit', 'playRequestedUnixMicros': cls.origin + 100_000,
                          'firstPositionUnixMicros': cls.origin + 300_000,
                          'pauseRequestedUnixMicros': cls.origin + 60_300_000,
                          'requiredWallPlaybackMs': 60000, 'observedPositionAdvanceMs': 59000,
                          'positionEvidence': {'overflow': False}, 'terminal': None}],
        }
        cls.runner = {'schema': 'readaloud-native-variant-runner-v1', 'mode': 'cached-8bit',
                      'passed': True, 'nativePassed': True, 'normalQuit': True,
                      'appExitVerified': True, 'forcedCleanup': False, 'remainingOwnedPids': [],
                      'captureExitStatus': 0, 'appExitStatus': 0, 'errors': [],
                      'maxMlxChildren': 1, 'observedMlxSamples': 600, 'pid': 1234,
                      'processEvents': [{'pids': []}, {'pids': [1235]}, {'pids': []}],
                      'emittedSignal': [{'passed': True}]}
        cls.capture = np.concatenate([np.zeros(12000), *cls.sources])[:round(60.3 * cls.rate)]
        cls.capture = np.concatenate([cls.capture, np.zeros(cls.rate)])
        cls.timing = {'schema': 'readaloud-app-capture-timing-v1', 'appPid': 1234,
                      'firstPacketReceivedUnixMicros': cls.origin,
                      'firstSignalReceivedUnixMicros': cls.origin + 250_000,
                      'sampleRate': cls.rate, 'frames': len(cls.capture)}

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.native = copy.deepcopy(self.__class__.native)
        self.runner = copy.deepcopy(self.__class__.runner)
        self.timing = copy.deepcopy(self.__class__.timing)
        self.capture = self.__class__.capture.copy()

    def run_analysis(self):
        for name, obj in [('receipt.json', self.native), ('runner.json', self.runner),
                          ('capture.wav.timing.json', self.timing)]:
            (self.root / name).write_text(json.dumps(obj))
        wavfile.write(self.root / 'capture.wav', self.rate, self.capture.astype(np.float32))
        return analyze(self.root)

    def assert_refused(self, result, text=None):
        self.assertFalse(result['passed'], result)
        if text:
            diagnostics = str(result['errors']) + str([s['errors'] for s in result['segments']])
            self.assertIn(text, diagnostics)

    def test_complete_waveforms_natural_pauses_and_only_final_interruption(self):
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        report = result['segments'][0]
        self.assertAlmostEqual(report['completeReferenceSeconds'], 55, places=3)
        self.assertEqual([m['queueIndex'] for m in report['matches']], list(range(5)))
        self.assertEqual(report['excludedFinalWaveform']['queueIndex'], 5)
        self.assertGreaterEqual(min(m['fullActiveCorrelation'] for m in report['matches']), .98)
        self.assertLess(report['maximumAbsoluteExternalJoinMs'], .1)
        self.assertLess(max(m['searchWindowSeconds'] for m in report['matches']), 14)
        self.assertEqual(result['comparisonSampleRate'], 192000)

    def test_wrong_plausible_waveform_is_refused(self):
        start = 12000
        self.capture[start:start + len(self.sources[0])] = self.sources[1]
        self.assert_refused(self.run_analysis(), 'No complete ordered waveform #1')

    def test_acoustic_order_reversal_is_refused(self):
        self.capture[12000:12000 + 22 * self.rate] = np.concatenate(self.sources[1::-1])
        self.assert_refused(self.run_analysis(), 'No complete ordered waveform #1')

    def test_queue_order_cannot_be_replaced_by_names_or_sample_order(self):
        self.native['queuedAudio'][0:2] = self.native['queuedAudio'][1::-1]
        self.assert_refused(self.run_analysis(), 'contradict queued source order')

    def test_inserted_external_gap_fails_unchanged_ten_ms_gate(self):
        split = 12000 + 11 * self.rate
        self.capture = np.concatenate([self.capture[:split], np.zeros(960), self.capture[split:]])
        self.timing['frames'] = len(self.capture)
        self.assert_refused(self.run_analysis(), 'exceeds 10ms')

    def test_truncated_interior_ending_is_not_prefix_qualified(self):
        # Remove the final 2s of the second WAV, then continue plausible speech.
        cut = 12000 + 20 * self.rate
        self.capture = np.concatenate([self.capture[:cut], self.capture[cut + 2 * self.rate:]])
        self.timing['frames'] = len(self.capture)
        self.assert_refused(self.run_analysis(), 'Capture misses playback interval')
        # Preserve capture interval duration to prove full-waveform matching,
        # rather than merely the container-duration gate, rejects the ending.
        self.capture = np.concatenate([self.capture, np.zeros(2 * self.rate)])
        self.timing['frames'] = len(self.capture)
        self.assert_refused(self.run_analysis(), 'No complete ordered waveform #2')

    def test_silence_is_not_waveform_evidence(self):
        self.capture[:] = 0
        self.assert_refused(self.run_analysis(), 'No complete ordered waveform')

    def test_insufficient_complete_coverage_fails_even_with_interrupted_final(self):
        self.native['queuedAudio'] = self.native['queuedAudio'][:2]
        self.native['playerSamples'] = [s for s in self.native['playerSamples']
                                        if s['source'] in {Path(q['sourcePath']).as_uri()
                                                           for q in self.native['queuedAudio']}]
        self.assert_refused(self.run_analysis(), 'Insufficient full-waveform coverage')

    def test_hash_and_size_are_authority(self):
        for key, value, message in [('sha256', '0' * 64, 'SHA256 mismatch'),
                                    ('bytes', 10, 'byte count/bound mismatch')]:
            with self.subTest(key=key):
                self.native = copy.deepcopy(self.__class__.native)
                self.native['queuedAudio'][0]['reference'][key] = value
                self.assert_refused(self.run_analysis(), message)

    def test_runtime_failures_cannot_hide_behind_passed_boolean(self):
        cases = [('runner', 'normalQuit', False), ('runner', 'forcedCleanup', True),
                 ('runner', 'remainingOwnedPids', [8]), ('runner', 'maxMlxChildren', 2),
                 ('runner', 'observedMlxSamples', 0), ('runner', 'emittedSignal', []),
                 ('native', 'maxUiHeartbeatDelayMs', 251)]
        for owner, field, value in cases:
            with self.subTest(field=field):
                self.setUp()
                getattr(self, owner)[field] = value
                self.assert_refused(self.run_analysis())
        self.setUp()
        self.native['nativeMainResponsiveness']['maxRoundTripMs'] = 251
        self.assert_refused(self.run_analysis(), '250ms responsiveness')

    def test_only_one_final_pause_interruption_can_be_excluded(self):
        self.capture[12000 + 44 * self.rate:] = 0
        self.assert_refused(self.run_analysis(), 'No complete ordered waveform #5')

    def test_no_aba_prefix_as_sustained_acceptance(self):
        self.native['mode'] = self.runner['mode'] = 'cached-aba'
        self.assert_refused(self.run_analysis(), 'Sustained acceptance requires')

    def test_nonfinite_and_oversized_inputs_fail_before_matching(self):
        self.capture[100] = np.nan
        self.assert_refused(self.run_analysis(), 'Nonfinite/out-of-range PCM')
        self.setUp()
        self.native['maxUiHeartbeatDelayMs'] = float('inf')
        with self.assertRaisesRegex(ValueError, 'Nonfinite JSON'):
            self.run_analysis()
        bad = self.root / 'oversized.wav'
        with bad.open('wb') as stream:
            stream.truncate(120_000_001)
        with self.assertRaisesRegex(ValueError, 'Oversized/empty WAV'):
            read_audio(bad, 120_000_000, 300)
        bad.unlink()


if __name__ == '__main__':
    unittest.main()
