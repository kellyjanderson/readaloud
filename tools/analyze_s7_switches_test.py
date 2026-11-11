"""Focused synthetic identity/order/silence refusal fixtures, not native acceptance.

Packets have distinct changing harmonics, shaped noise and encoded pauses.
Each route contains two complete audible packets, one anchored silent packet,
one Pause-interrupted packet, and one unplayed prepared packet per engine.
Changing ordering, an ending, or silent-gap speech must change the verdict.
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

from analyze_s7_switches import analyze
from analyze_s7_variants import MIN_COMPLETE_SECONDS as SUSTAINED_MINIMUM


class S7SwitchAcceptanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.origin, cls.rate = 1_800_000_000_000_000, 48000
        cls.capture = np.zeros(round(18.5 * cls.rate))
        cls.queued, samples, segments, cls.packets = [], [], [], []
        for segment_index, (label, engine_id, engine_index, offset) in enumerate([
                ('initial-A8', 'fish_drama3_8bit', 0, 0.),
                ('B4', 'fish_drama3_4bit', 3, 7.),
                ('returned-A8', 'fish_drama3_8bit', 4, 14.)]):
            packets = []
            for number, duration in enumerate([.8, .25, .8, 1.7, .4]):
                rate = 8000
                t = np.arange(round(duration * rate)) / rate
                rng = np.random.default_rng(segment_index * 31 + number + 11)
                pitch = 120 + 45 * np.sin(t * (13 + number + segment_index * 2))
                phase = 2 * np.pi * np.cumsum(pitch) / rate
                voiced = sum(np.sin(phase * h) / h for h in range(1, 13))
                noise = sosfilt(butter(3, [300, 3200], btype='bandpass', fs=rate, output='sos'),
                                rng.normal(size=len(t)))
                pcm = (1800 * (.25 + .75 * np.sin(t * 17) ** 2) * (voiced + noise)).astype(np.int16)
                # Silence is the actual reference condition, never identity proof.
                if number == 1:
                    pcm[:] = 0
                elif number == 0:
                    pcm[2400:3600] = 0  # natural pause inside a complete waveform
                path = cls.root / f'copied-{99 - len(cls.queued)}.wav'
                wavfile.write(path, rate, pcm)
                cls.queued.append({
                    'engineIndex': engine_index, 'engineId': engine_id,
                    'sourcePath': f'/production/engine-{engine_index}/source-{number}.wav',
                    'queuedUnixMicros': cls.origin + round((offset + .1) * 1e6),
                    'reference': {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                  'bytes': path.stat().st_size, 'sampleRate': rate,
                                  'channels': 1, 'bitsPerSample': 16}})
                packets.append(resample_poly(pcm.astype(np.float64) / 32768, 6, 1))
            cls.packets.append(packets)
            onset = offset + .25
            start, stop = round(onset * cls.rate), round((offset + 3.3) * cls.rate)
            cls.capture[start:stop] = np.concatenate(packets)[:stop - start]
            for stamp in np.arange(offset + .3, offset + 3.3, .1):
                elapsed = stamp - onset
                number = 0 if elapsed < .8 else 1 if elapsed < 1.05 else 2 if elapsed < 1.85 else 3
                position = elapsed - [0, .8, 1.05, 1.85][number]
                samples.append({'unixMicros': cls.origin + round(stamp * 1e6),
                                'engineIndex': engine_index, 'playing': True,
                                'source': Path(cls.queued[segment_index * 5 + number]['sourcePath']).as_uri(),
                                'positionMs': round(position * 1000)})
            # Accurate paused source witness may arrive during Pause completion.
            samples.append({'unixMicros': cls.origin + round((offset + 3.31) * 1e6),
                            'engineIndex': engine_index, 'playing': False,
                            'source': Path(cls.queued[segment_index * 5 + 3]['sourcePath']).as_uri(),
                            'positionMs': 1200})
            segments.append({'label': label, 'engineId': engine_id, 'engineIndex': engine_index,
                             'playRequestedUnixMicros': cls.origin + round((offset + .1) * 1e6),
                             'firstPositionUnixMicros': cls.origin + round((offset + .3) * 1e6),
                             'pauseRequestedUnixMicros': cls.origin + round((offset + 3.3) * 1e6),
                             'pauseReturnedUnixMicros': cls.origin + round((offset + 3.32) * 1e6),
                             'requiredWallPlaybackMs': 3000, 'observedPositionAdvanceMs': 3000,
                             'terminal': None, 'positionEvidence': {'overflow': False}})
        cls.native = {
            'schema': 'readaloud-native-variant-v1', 'mode': 'cached-aba',
            'offline': True, 'managedModelPathOverride': False,
            'passed': True, 'functionalPassed': True, 'resourceShutdownComplete': True,
            'shutdownErrors': [], 'observationErrors': [], 'maxUiHeartbeatDelayMs': 100,
            'nativeMainResponsiveness': {'passed': True, 'error': None, 'samples': 100,
                                        'applicationActiveSamples': 95, 'maxRoundTripMs': 120},
            'rapidLatestSelectionValidated': True, 'retainedAnchor': 29, 'returnAnchor': 29,
            'queuedAudio': cls.queued, 'playerSamples': samples, 'segments': segments}
        cls.runner = {
            'schema': 'readaloud-native-variant-runner-v1', 'mode': 'cached-aba',
            'passed': True, 'nativePassed': True, 'normalQuit': True, 'appExitVerified': True,
            'forcedCleanup': False, 'remainingOwnedPids': [], 'captureExitStatus': 0,
            'appExitStatus': 0, 'errors': [], 'maxMlxChildren': 1,
            'observedMlxSamples': 100, 'pid': 1234,
            'processEvents': [{'pids': []}, {'pids': [1235]}, {'pids': []}],
            'emittedSignal': [{'passed': True} for _ in segments]}
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
        self.timing['frames'] = len(self.capture)
        for name, value in [('receipt.json', self.native), ('runner.json', self.runner),
                            ('capture.wav.timing.json', self.timing)]:
            (self.root / name).write_text(json.dumps(value))
        wavfile.write(self.root / 'capture.wav', self.rate, self.capture.astype(np.float32))
        return analyze(self.root)

    def assert_refused(self, text):
        result = self.run_analysis()
        self.assertFalse(result['passed'], result)
        self.assertIn(text, str(result['errors']))

    def test_complete_three_segment_identity_order_encoded_pauses_and_tail_scopes(self):
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        self.assertEqual(SUSTAINED_MINIMUM, 50.)
        for index, report in enumerate(result['segments']):
            self.assertAlmostEqual(report['completeReferenceSeconds'], 1.6)
            self.assertEqual([m['queueIndex'] for m in report['matches']], [index * 5, index * 5 + 2])
            self.assertEqual(report['excludedFinalWaveform']['queueIndex'], index * 5 + 3)
            self.assertEqual([r['queueIndex'] for r in report['preparedTailOutsidePlaybackInterval']], [index * 5 + 4])
            self.assertEqual(len(report['encodedSilentPackets']), 1)
            self.assertLess(report['maximumAbsoluteExternalJoinMs'], .1)
        self.assertEqual(len(result['quietIntervals']), 3)
        self.assertGreaterEqual(result['quietIntervals'][-1]['durationSeconds'], .75)

    def test_online_real_progress_double_cancel_retry(self):
        self.native.update(mode='online-cancel-retry', offline=False, doubleCancelValidated=True,
                           downloadRetiredWithoutLateActivation=True, retryValidated=True,
                           downloadBaselineBytes=1000,
                           downloadInterruptedAt={'event': 'download-interruption', 'resourceProgress': {
                               'stage': 'Downloading', 'unit': 'bytes', 'completed': 2000}})
        self.runner['mode'] = 'online-cancel-retry'
        self.assertTrue(self.run_analysis()['passed'])
        self.native['downloadInterruptedAt']['resourceProgress']['completed'] = 1000
        self.assert_refused('No actual advancing download')

    def test_plausible_wrong_waveform_refused(self):
        self.capture[12000:12000 + len(self.packets[0][0])] = self.packets[1][0]
        self.assert_refused('No complete ordered waveform #1')

    def test_reversed_audible_packet_order_refused(self):
        start = 12000
        self.capture[start:start + round(1.85 * self.rate)] = np.concatenate([
            self.packets[0][2], self.packets[0][1], self.packets[0][0]])
        self.assert_refused('No complete ordered waveform #1')

    def test_queue_order_cannot_be_replaced_by_source_names_or_player_order(self):
        rows = self.native['queuedAudio']
        rows[0], rows[2] = rows[2], rows[0]
        self.assert_refused('No complete ordered waveform')

    def test_truncated_interior_waveform_not_prefix_qualified(self):
        start = round((.25 + 1.05 + .55) * self.rate)
        self.capture[start:start + round(.25 * self.rate)] = 0
        self.assert_refused('No complete ordered waveform #3')

    def test_stale_speech_in_otherwise_legitimate_between_play_gap_refused(self):
        start = round(5 * self.rate)
        self.capture[start:start + len(self.packets[0][0])] = self.packets[0][0]
        self.assert_refused('Unexpected speech/signal in quiet interval initial-A8-to-B4')

    def test_stale_speech_after_final_pause_refused(self):
        start = round(17.7 * self.rate)
        self.capture[start:start + round(.3 * self.rate)] = self.packets[0][0][:round(.3 * self.rate)]
        self.assert_refused('Unexpected speech/signal in quiet interval after-final-Pause')

    def test_extra_signal_inside_source_encoded_silence_refused(self):
        self.capture[round(1.1 * self.rate):round(1.2 * self.rate)] = .2
        self.assert_refused('Unexpected captured signal in source-encoded silent packet')

    def test_external_gap_inside_encoded_silent_packet_refused(self):
        split, stop = round(1.2 * self.rate), round(3.3 * self.rate)
        self.capture[split:stop] = np.concatenate([np.zeros(960), self.capture[split:stop]])[:stop - split]
        self.assert_refused('exceeds 10ms')

    def test_non_atomic_sample_does_not_override_queue_order(self):
        sample = self.native['playerSamples'][4]
        sample['source'] = Path(self.queued[2]['sourcePath']).as_uri()
        result = self.run_analysis()
        self.assertTrue(result['passed'], result)
        self.assertTrue(result['segments'][0]['playerSnapshotOrderAnomalies'])

    def test_short_final_quiet_capture_refused(self):
        self.capture = self.capture[:round(18 * self.rate)]
        self.assert_refused('Insufficient bounded quiet capture: after-final-Pause')

    def test_prepared_unplayed_reference_still_requires_real_digest(self):
        self.native['queuedAudio'][-1]['reference']['sha256'] = ''
        self.assert_refused('SHA256 mismatch')

    def test_encoded_silence_and_final_partial_cannot_supply_one_second_coverage(self):
        path = self.root / 'silent-first.wav'
        wavfile.write(path, 8000, np.zeros(6400, dtype=np.int16))
        ref = self.native['queuedAudio'][0]['reference']
        ref.update(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                   bytes=path.stat().st_size)
        self.capture[12000:12000 + round(.8 * self.rate)] = 0
        self.assert_refused('Insufficient full-waveform coverage')

    def test_responsiveness_over_250ms_refused(self):
        self.native['nativeMainResponsiveness']['maxRoundTripMs'] = 251
        self.assert_refused('250ms responsiveness gate failed')

    def test_no_runtime_or_route_gate_waivers(self):
        cases = [('native', 'rapidLatestSelectionValidated', False, 'Rapid latest-selection'),
                 ('runner', 'normalQuit', False, 'Runner gate failed'),
                 ('runner', 'remainingOwnedPids', [1235], 'orphan process'),
                 ('runner', 'maxMlxChildren', 2, 'exactly one observed')]
        for owner, field, value, expected in cases:
            with self.subTest(field=field):
                target = self.native if owner == 'native' else self.runner
                previous = target[field]
                target[field] = value
                self.assert_refused(expected)
                target[field] = previous


if __name__ == '__main__':
    unittest.main()
