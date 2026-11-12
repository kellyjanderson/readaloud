"""Synthetic full-waveform and coverage diagnostics; no native/audio acceptance.

Distinct nonperiodic speech-shaped sources contain changing harmonics and noise,
including complete active endings. Missing/swapped sources and truncated endings
must fail identity. Real capture origins/frames bound coverage independently of
source placement hints; omitted time must never become silence or a match.
"""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly

from compare_s7_captures import compare


class DualCaptureDiagnosticTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.origin = 1_800_000_000_000_000
        self.rate = 48000
        self.duration = .4
        self.queued = []
        self.sources = []
        for i in range(4):
            t = np.arange(3200) / 8000
            phase = 2 * np.pi * np.cumsum(120 + 25 * np.sin(t * (7 + i))) / 8000
            rng = np.random.default_rng(i + 42)
            wave = .15 * (np.sin(phase) + .4 * np.sin(phase * 3) + .3 * rng.normal(size=len(t)))
            pcm = (wave * 32768).astype(np.int16)
            path = self.root / f'ref-{9-i}.wav'  # Filenames are not queue authority.
            wavfile.write(path, 8000, pcm)
            self.sources.append(resample_poly(pcm.astype(np.float64) / 32768, 6, 1))
            self.queued.append({'sourcePath': f'/production/{i}.wav', 'queuedUnixMicros': self.origin,
                                'reference': {'path': str(path), 'bytes': path.stat().st_size,
                                              'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                              'sampleRate': 8000, 'channels': 1, 'bitsPerSample': 16}})
        self.pcm = np.concatenate([np.zeros(9600), *self.sources, np.zeros(9600)])
        self.sck = self.pcm.copy()
        self.tap = self.pcm.copy()
        self.timing = {'schema': 'readaloud-app-capture-timing-v1', 'appPid': 123,
                       'firstPacketReceivedUnixMicros': self.origin,
                       'sampleRate': self.rate, 'frames': len(self.pcm), 'maxPacketGapSeconds': 0.}
        self.tap_timing = dict(self.timing, mechanism='CoreAudioProcessTap', status='complete', errors=[],
                               processAudioObjectID=124, privateTap=True, privateAggregate=True,
                               muteBehavior='unmuted',
                               sessionID='ca751a73-9705-475b-ac94-ac86ab7e6f8d',
                               droppedBuffers=0, poolOverflows=0, deviceOverloads=0,
                               timestampDiscontinuities=0, formatChanges=0, callbackStalls=0,
                               writerDiscardedBuffers=0, framesReceived=len(self.pcm),
                               framesSubmitted=len(self.pcm), buffersSubmitted=20, buffersWritten=20, callbacks=20)
        self.primary = {'passed': False, 'runtimeFailures': ['native responsiveness failed'], 'errors': [],
                        'segments': [{'matches': [dict(q, queueIndex=i, captureStartSeconds=.2 + i * .4)
                                                  for i, q in enumerate(self.queued)],
                                      'failedWaveforms': [], 'preparedTailOutsidePlaybackInterval': []}]}
        self.native = {'schema': 'readaloud-native-variant-v1', 'passed': False, 'queuedAudio': self.queued}
        self.runner = {'schema': 'readaloud-native-variant-runner-v1', 'passed': False, 'pid': 123}

    def run_comparison(self):
        for name, value in [('receipt.json', self.native), ('runner.json', self.runner),
                             ('capture.wav.timing.json', self.timing), ('coreaudio.wav.timing.json', self.tap_timing)]:
            (self.root / name).write_text(json.dumps(value))
        wavfile.write(self.root / 'capture.wav', self.rate, self.sck.astype(np.float32))
        wavfile.write(self.root / 'coreaudio.wav', self.rate, self.tap.astype(np.float32))
        # Unit boundary: primary placements are explicit hints. Both saved PCM
        # paths are independently matched in full by the tool under test.
        with patch('compare_s7_captures.primary_analyze', return_value=self.primary):
            return compare(self.root)

    def classifications(self, result):
        self.assertEqual(result['errors'], [], result)
        self.assertFalse(result['passed'])
        self.assertTrue(result['diagnosticOnly'])
        return [p['classification'] for p in result['packets']]

    def test_agreement_preserves_failed_runtime_and_unchanged_policy(self):
        result = self.run_comparison()
        self.assertEqual(self.classifications(result), ['agreement-matched'] * 4)
        self.assertEqual(result['primaryDiagnostic']['runtimeFailures'], ['native responsiveness failed'])
        self.assertEqual(result['policy'], {'fullActiveCorrelationMinimum': .98, 'phaseMultiplier': 4,
                                             'fullReferencePlacementCorrelationMinimum': .98,
                                             'maximumAbsoluteExternalJoinMs': 10.})
        self.assertEqual(result['timingViolations'], [])
        self.assertTrue(all(p['coreaudio']['bestFullActiveCorrelation'] >= .98 for p in result['packets']))

    def low_information_first_source(self, wrong_tap_context=False, decoy=True):
        rng = np.random.default_rng(409)
        pcm = rng.integers(-20, 21, round(self.duration * self.rate), dtype=np.int16)
        spike = np.array([130, 300, 394, 220, 50], dtype=np.int16)
        pcm[1000:1005] = spike
        ref = self.queued[0]['reference']
        path = Path(ref['path'])
        wavfile.write(path, self.rate, pcm)
        ref.update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                   bytes=path.stat().st_size, sampleRate=self.rate)
        self.sck[9600:28800] = pcm.astype(np.float64) / 32768
        emitted = (rng.integers(-20, 21, len(pcm), dtype=np.int16)
                   if wrong_tap_context else pcm.copy())
        emitted[1000:1005] = spike
        self.tap[9600:28800] = emitted.astype(np.float64) / 32768
        # Keep the following packet's onset quiet so resampler boundary bleed
        # from an abrupt loud synthetic start cannot mask the tiny reference.
        following_ref = self.queued[1]['reference']
        following_path = Path(following_ref['path'])
        following_rate, following = wavfile.read(following_path)
        following[:16] = 0
        wavfile.write(following_path, following_rate, following)
        following_ref['sha256'] = hashlib.sha256(following_path.read_bytes()).hexdigest()
        self.sck[28800:48000] = self.tap[28800:48000] = resample_poly(
            following.astype(np.float64) / 32768, 6, 1)
        if decoy:
            self.sck[7480:7485] = self.tap[7480:7485] = spike.astype(np.float64) / 32768

    def test_microtransient_context_selects_same_placement_in_both_captures(self):
        self.low_information_first_source()
        result = self.run_comparison()
        self.assertEqual(self.classifications(result), ['agreement-matched'] * 4)
        for name in ('capture', 'coreaudio'):
            first = result['packets'][0][name]
            self.assertAlmostEqual(first['captureStartSeconds'], .2, delta=1 / (self.rate * 4))
            self.assertLess(first['activeComparisonFrames'], 25)
            self.assertGreater(first['fullReferenceComparisonFrames'], 75000)
            self.assertGreaterEqual(first['fullReferenceCorrelation'], .98)
            self.assertGreaterEqual(first['bestFullActiveCorrelation'], .98)
        self.assertEqual(result['timingViolations'], [])

    def test_same_microtransient_with_wrong_tap_context_is_missing(self):
        self.low_information_first_source(wrong_tap_context=True, decoy=False)
        result = self.run_comparison()
        self.assertEqual(self.classifications(result)[0], 'sck-matches-tap-missing')
        self.assertLess(result['packets'][0]['coreaudio']['fullReferenceCorrelation'], .98)

    def test_swapped_tap_stream_cannot_use_names_or_primary_matches_as_identity(self):
        self.tap[9600:48000] = np.concatenate(self.sources[1::-1])
        result = self.run_comparison()
        self.assertEqual(self.classifications(result)[:2], ['agreement-matched', 'sck-matches-tap-missing'])
        self.assertAlmostEqual(result['packets'][0]['tapMinusSckReceiptMappedStartMs'], 400., delta=.1)

    def test_missing_sck_and_both_missing_then_original_timeline_resumes(self):
        self.sck[28800:48000] = 0
        self.sck[48000:67200] = 0
        self.tap[48000:67200] = 0
        report = self.primary['segments'][0]
        report['failedWaveforms'] = [dict(q, queueIndex=i, expectedStartSeconds=.2 + i * .4)
                                     for i, q in enumerate(self.queued) if i in (1, 2)]
        report['matches'] = [r for r in report['matches'] if r['queueIndex'] not in (1, 2)]
        result = self.run_comparison()
        self.assertEqual(self.classifications(result), ['agreement-matched', 'sck-missing-tap-matches',
                                                       'both-missing-full-waveform', 'agreement-matched'])
        resumed = result['packets'][3]['capture']
        self.assertIsNone(resumed['externalGapBeforeMs'])
        self.assertAlmostEqual(resumed['failedOrUnobservedReferenceSecondsBefore'], .8)
        self.assertLess(abs(resumed['orderedTimingResidualMs']), .1)
        self.assertEqual(result['packets'][1]['placementAuthority'], 'Primary native/ordered search hint')

    def test_source_encoded_silence_is_explicit_and_receives_no_waveform_credit(self):
        ref = self.queued[1]['reference']
        path = Path(ref['path'])
        wavfile.write(path, 8000, np.zeros(3200, np.int16))
        ref['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.sck[28800:48000] = self.tap[28800:48000] = 0
        report = self.primary['segments'][0]
        report['matches'] = [r for r in report['matches'] if r['queueIndex'] != 1]
        report['encodedSilentPackets'] = [dict(self.queued[1], queueIndex=1)]
        result = self.run_comparison()
        self.assertEqual(self.classifications(result)[1], 'source-silent')
        self.assertEqual(result['perCaptureSummary']['coreaudio']['completeMatchedAudiblePackets'], 3)

    def test_late_tap_and_short_final_capture_remain_unobserved_without_padding(self):
        # Tap actually starts halfway through packet 0 and ends halfway through
        # packet 3. Frame duration, not requested duration, defines coverage.
        self.tap = self.tap[round(.4 * self.rate):round(1.6 * self.rate)]
        self.tap_timing['firstPacketReceivedUnixMicros'] += 400_000
        for key in ('frames', 'framesReceived', 'framesSubmitted'):
            self.tap_timing[key] = len(self.tap)
        result = self.run_comparison()
        self.assertEqual(self.classifications(result), ['unobserved', 'agreement-matched',
                                                       'agreement-matched', 'unobserved'])
        self.assertAlmostEqual(result['sharedObservedInterval']['durationSeconds'], 1.2)
        self.assertEqual(result['packets'][0]['coreaudio']['status'], 'unobserved')

    def test_truncated_interior_ending_does_not_receive_prefix_credit(self):
        # Preserve the capture duration and plausible following speech, while
        # replacing the last 100ms of packet 1 by unrelated packet audio.
        self.tap[round(.9 * self.rate):round(1.0 * self.rate)] = self.sources[2][:4800]
        result = self.run_comparison()
        self.assertEqual(self.classifications(result)[1], 'sck-matches-tap-missing')
        self.assertLess(result['packets'][1]['coreaudio']['bestFullActiveCorrelation'], .98)

    def test_invalid_reference_sha_including_unplayed_tail_refuses_comparison(self):
        self.primary['segments'][0]['matches'].pop()
        self.primary['segments'][0]['preparedTailOutsidePlaybackInterval'] = [{'queueIndex': 3}]
        self.queued[-1]['reference']['sha256'] = '0' * 64
        result = self.run_comparison()
        self.assertIn('SHA256 mismatch', str(result['errors']))
        self.assertEqual(result['packets'], [])

    def test_wrong_pid_unfinished_loss_timing_and_frame_gaps_are_invalid_evidence(self):
        cases = [('appPid', 124), ('status', 'capturing'), ('errors', ['writer failed']),
                 ('sessionID', None), ('sessionID', 'invalid-session'),
                 ('droppedBuffers', 1), ('timestampDiscontinuities', 1), ('writerDiscardedBuffers', 1),
                 ('maxPacketGapSeconds', .02), ('framesSubmitted', len(self.tap) - 1),
                 ('frames', len(self.tap) - 1)]
        for key, value in cases:
            with self.subTest(key=key):
                old = self.tap_timing[key]
                self.tap_timing[key] = value
                result = self.run_comparison()
                self.assertTrue(result['errors'])
                self.assertTrue(all(p['classification'] == 'invalid-capture-evidence' for p in result['packets']))
                self.tap_timing[key] = old
        self.timing['maxPacketGapSeconds'] = .02
        self.assertIn('capture', self.run_comparison()['captureErrors'])

    def test_absent_stream_is_invalid_evidence_not_both_missing_audio(self):
        self.run_comparison()
        (self.root / 'coreaudio.wav').unlink()
        result = compare(self.root)
        self.assertIn('coreaudio', result['captureErrors'])
        self.assertTrue(all(p['classification'] == 'invalid-capture-evidence' for p in result['packets']))

    def test_actual_twenty_ms_external_gap_remains_a_timing_violation(self):
        split = 28800
        self.tap = np.concatenate([self.tap[:split], np.zeros(960), self.tap[split:]])
        for key in ('frames', 'framesReceived', 'framesSubmitted'):
            self.tap_timing[key] = len(self.tap)
        result = self.run_comparison()
        self.assertEqual(self.classifications(result), ['agreement-matched'] * 4)
        violations = [v for v in result['timingViolations'] if v['capture'] == 'coreaudio']
        self.assertEqual(len(violations), 1)
        self.assertAlmostEqual(violations[0]['residualMs'], 20., delta=.1)


if __name__ == '__main__':
    unittest.main()
