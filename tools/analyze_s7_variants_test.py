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

    def run_analysis(self, diagnostic_only=False):
        for name, obj in [('receipt.json', self.native), ('runner.json', self.runner),
                          ('capture.wav.timing.json', self.timing)]:
            (self.root / name).write_text(json.dumps(obj))
        wavfile.write(self.root / 'capture.wav', self.rate, self.capture.astype(np.float32))
        return analyze(self.root, diagnostic_only=diagnostic_only)

    def reference(self, name, pcm, rate=8000):
        path = self.root / name
        wavfile.write(path, rate, pcm)
        return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'bytes': path.stat().st_size, 'sampleRate': rate,
                'channels': 1, 'bitsPerSample': 16}

    def split_first_source_at_encoded_pause(self):
        _, pcm = wavfile.read(self.native['queuedAudio'][0]['reference']['path'])
        spans = [pcm[:32000], pcm[32000:36800], pcm[36800:]]
        original = self.native['queuedAudio'][0]
        split = []
        for number, span in enumerate(spans):
            row = copy.deepcopy(original)
            row['sourcePath'] = f'/production/split-{number}.wav'
            row['reference'] = self.reference(f'split-{number}.wav', span)
            split.append(row)
        for sample in self.native['playerSamples']:
            if sample['source'] == Path(original['sourcePath']).as_uri():
                position = sample['positionMs']
                part = 0 if position < 4000 else 1 if position < 4600 else 2
                sample['source'] = Path(split[part]['sourcePath']).as_uri()
                sample['positionMs'] -= [0, 4000, 4600][part]
        self.native['queuedAudio'][:1] = split

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
        self.assert_refused(self.run_analysis(), 'No complete ordered waveform')

    def test_mixed_player_snapshots_do_not_override_complete_acoustic_order(self):
        # Mirrors non-atomic sequence/index observations: briefly show a future
        # queued source, then the still-current source. Actual audio is ordered.
        sample = self.native['playerSamples'][120]
        sample['source'] = Path(self.queued[2]['sourcePath']).as_uri()
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        self.assertTrue(result['segments'][0]['playerSnapshotOrderAnomalies'])

    def test_prepared_tail_is_not_misreported_as_emitted_or_partial_audio(self):
        for i in range(12):
            row = copy.deepcopy(self.native['queuedAudio'][0])
            row['sourcePath'] = f'/production/unplayed-{i}.wav'
            self.native['queuedAudio'].append(row)
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        report = result['segments'][0]
        self.assertEqual(len(report['preparedTailOutsidePlaybackInterval']), 12)
        self.assertEqual(report['excludedFinalWaveform']['queueIndex'], 5)
        self.native['queuedAudio'][-1]['reference']['sha256'] = '0' * 64
        self.assert_refused(self.run_analysis(), 'SHA256 mismatch')

    def test_post_pause_source_witness_includes_only_final_partial(self):
        row = copy.deepcopy(self.native['queuedAudio'][0])
        row['sourcePath'] = '/production/unplayed.wav'
        self.native['queuedAudio'].append(row)
        pause = self.native['segments'][0]['pauseRequestedUnixMicros']
        self.native['segments'][0]['pauseReturnedUnixMicros'] = pause + 50000
        self.native['playerSamples'].append({
            'unixMicros': pause + 11000, 'engineIndex': 0, 'playing': False,
            'source': Path(self.queued[5]['sourcePath']).as_uri(), 'positionMs': 5061})
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        self.assertEqual(result['segments'][0]['pauseSourceWitness']['queueIndex'], 5)

    def test_silent_packets_use_anchored_duration_and_signal_not_waveform_credit(self):
        self.split_first_source_at_encoded_pause()
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        self.assertAlmostEqual(result['segments'][0]['completeReferenceSeconds'], 54.4, places=3)
        self.assertEqual(len(result['segments'][0]['encodedSilentPackets']), 1)
        # Extra speech in a source-encoded pause must be rejected even when
        # surrounding full waveforms and their timing still match exactly.
        self.capture[round(4.4 * self.rate):round(4.5 * self.rate)] = .5
        self.assert_refused(self.run_analysis(), 'Unexpected captured signal')

    def test_external_gap_within_source_silent_packet_is_still_refused(self):
        self.split_first_source_at_encoded_pause()
        split = round(4.5 * self.rate)
        self.capture = np.concatenate([self.capture[:split], np.zeros(960), self.capture[split:]])
        self.timing['frames'] = len(self.capture)
        self.assert_refused(self.run_analysis(), 'exceeds 10ms')

    def test_short_complete_packets_are_compared_in_full(self):
        # A full 40ms slice is valid identity evidence; a 100ms activity floor
        # would incorrectly reject real native streaming packets of this size.
        _, pcm = wavfile.read(self.native['queuedAudio'][0]['reference']['path'])
        original = self.native['queuedAudio'][0]
        split = []
        for number, span in enumerate([pcm[:320], pcm[320:]]):
            row = copy.deepcopy(original)
            row['sourcePath'] = f'/production/short-{number}.wav'
            row['reference'] = self.reference(f'short-{number}.wav', span)
            split.append(row)
        for sample in self.native['playerSamples']:
            if sample['source'] == Path(original['sourcePath']).as_uri():
                sample['source'] = Path(split[1]['sourcePath']).as_uri()
                sample['positionMs'] -= 40
        self.native['queuedAudio'][:1] = split
        # Supply the initial short packet's recorded native source observation.
        self.native['playerSamples'].insert(0, {
            'unixMicros': self.origin + 270000, 'engineIndex': 0, 'playing': True,
            'source': Path(split[0]['sourcePath']).as_uri(), 'positionMs': 20})
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        self.assertAlmostEqual(result['segments'][0]['matches'][0]['sourceDurationSeconds'], .04)

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
        self.native['queuedAudio'][0]['reference'] = self.reference(
            'silent-first.wav', np.zeros(11 * 8000, np.int16))
        self.capture[12000:12000 + 11 * self.rate] = 0
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

    def test_diagnostic_runtime_failure_retains_failed_verdict_and_raw_acoustics(self):
        self.native['passed'] = False
        self.native['nativeMainResponsiveness']['passed'] = False
        self.native['nativeMainResponsiveness']['maxRoundTripMs'] = 340
        self.runner['passed'] = False
        self.runner['nativePassed'] = False
        self.runner['errors'] = ['Emitted audio: Insufficient app-emitted signal during playback']
        self.runner['emittedSignal'] = None
        result = self.run_analysis(diagnostic_only=True)
        self.assertFalse(result['passed'])
        self.assertTrue(result['diagnosticOnly'])
        self.assertTrue(result['acousticCriteriaPassed'])
        self.assertIn('250ms responsiveness gate failed', result['runtimeFailures'])
        self.assertIn('Captured signal gate failed', result['runtimeFailures'])
        self.assertEqual(len(result['segments'][0]['matches']), 5)
        # The same unchanged receipt still refuses before matching by default.
        normal = self.run_analysis()
        self.assertFalse(normal['passed'])
        self.assertEqual(normal['segments'], [])

    def test_diagnostic_only_never_returns_accepted_even_for_valid_run(self):
        result = self.run_analysis(diagnostic_only=True)
        self.assertFalse(result['passed'])
        self.assertTrue(result['acousticCriteriaPassed'])
        self.assertEqual(result['runtimeFailures'], [])

    def test_diagnostic_continues_missing_audio_without_qualifying_it(self):
        # Audio disappears for one complete audible source while native time
        # advances; later captured speech resumes on the original timeline.
        start = 12000 + 11 * self.rate
        self.capture[start:start + 11 * self.rate] = 0
        result = self.run_analysis(diagnostic_only=True)
        self.assertFalse(result['passed'])
        self.assertFalse(result['acousticCriteriaPassed'])
        report = result['segments'][0]
        self.assertEqual([r['queueIndex'] for r in report['failedWaveforms']], [1])
        self.assertEqual([r['queueIndex'] for r in report['matches']], [0, 2, 3, 4])
        resumed = report['matches'][1]
        self.assertIsNone(resumed['externalGapBeforeMs'])
        self.assertEqual(resumed['failedReferenceSecondsBefore'], 11)
        self.assertLess(abs(resumed['aggregateTimingResidualAfterFailedReferencesMs']), .1)
        self.assert_refused(result, 'No complete ordered waveform #2')

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
