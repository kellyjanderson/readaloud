"""Offline identity/join/quiet-gate fixtures, never native/listening evidence."""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.io import wavfile

from analyze_s7_queue_replay import analyze


class QueueReplayTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.rate, cls.origin = 44100, 1_800_000_000_000_000
        cls.pcm, cls.rows, original = [], [], []
        for index in range(7):
            # Distinct nonperiodic speech-shaped noise has an identifiable full
            # waveform and ending. This fixture claims no intelligible speech.
            rng = np.random.default_rng(900 + index)
            t = np.arange(cls.rate * 10) / cls.rate
            pcm = (3000 * rng.normal(size=len(t)) * (.3 + .7 * np.sin(t * 4.3) ** 2)).astype('<i2')
            path = cls.root / f'packet-{index}.wav'
            wavfile.write(path, cls.rate, pcm)
            ref = cls.reference(path, pcm)
            cls.rows.append({'sourcePath': str(path), 'originalReferencePath': str(path),
                             'sourceReceiptIndex': index, 'startFrame': index * 10 * cls.rate,
                             'frameCount': len(pcm), 'reference': ref})
            original.append({'reference': ref})
            cls.pcm.append(pcm)
        cls.joined_pcm = np.concatenate(cls.pcm)
        joined_path = cls.root / 'joined.wav'
        wavfile.write(joined_path, cls.rate, cls.joined_pcm)
        cls.joined = cls.reference(joined_path, cls.joined_pcm)
        input_path = cls.root / 'input.json'
        input_path.write_text(json.dumps({'queuedAudio': original}))
        cls.provenance = {'inputReceipt': str(input_path),
                          'inputReceiptSha256': hashlib.sha256(input_path.read_bytes()).hexdigest(),
                          'expectedPackets': cls.rows, 'totalFrames': len(cls.joined_pcm),
                          'pcmSha256': hashlib.sha256(cls.joined_pcm.tobytes()).hexdigest(),
                          'joined': cls.joined}

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    @classmethod
    def reference(cls, path, pcm):
        return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'bytes': path.stat().st_size, 'sampleRate': cls.rate,
                'channels': 1, 'bitsPerSample': 16, 'pcmBytes': len(pcm) * 2}

    def setUp(self):
        self.run = tempfile.TemporaryDirectory()
        self.directory = Path(self.run.name)
        self.addCleanup(self.run.cleanup)
        self.native = {'queueReplayDiagnostic': True, 'replayMode': 'joined', 'passed': False,
                       'replayCompleted': True, 'replayCleanupComplete': True,
                       'shutdownErrors': [], 'observationErrors': [],
                       'maxUiHeartbeatDelayMs': 5, 'sourceProvenance': copy.deepcopy(self.provenance),
                       'nativeMainResponsiveness': {'passed': True, 'error': None, 'samples': 600,
                                                   'applicationActiveSamples': 500, 'maxRoundTripMs': 20},
                       'segments': [{'requiredWallPlaybackMs': 60000,
                                     'playRequestedUnixMicros': self.origin + 200_000,
                                     'firstPositionUnixMicros': self.origin + 400_000,
                                     'pauseRequestedUnixMicros': self.origin + 60_400_000,
                                     'pauseReturnedUnixMicros': self.origin + 60_410_000,
                                     'terminal': None, 'observedPositionAdvanceMs': 60100,
                                     'positionEvidence': {'overflow': False}}]}
        self.runner = {'queueReplayDiagnostic': True, 'replayMode': 'joined', 'passed': False,
                       'normalQuit': True, 'appExitVerified': True, 'forcedCleanup': False,
                       'remainingOwnedPids': [], 'captureExitStatus': 0, 'appExitStatus': 0,
                       'errors': ['Queue replay diagnosis only; model and product qualification not applicable'],
                       'maxMlxChildren': 0, 'observedMlxSamples': 0,
                       'processEvents': [{'pids': []}], 'pid': 123}
        self.set_mode('joined')
        prefix = np.zeros(round(.3 * self.rate), dtype='<i2')
        self.capture = np.concatenate([prefix, self.joined_pcm[:round(60.1 * self.rate)],
                                       np.zeros(round(1.5 * self.rate), dtype='<i2')])

    def set_mode(self, mode):
        self.native['replayMode'] = self.runner['replayMode'] = mode
        self.native['queuedAudio'] = ([{'reference': self.joined, 'sourcePath': self.joined['path']}]
                                      if mode == 'joined' else copy.deepcopy(self.rows))
        self.native['playerSamples'] = []
        for tick in range(602):
            position = tick / 10
            index = min(int(position / 10), 6)
            path = self.joined['path'] if mode == 'joined' else self.rows[index]['sourcePath']
            self.native['playerSamples'].append({'unixMicros': self.origin + 300_000 + tick * 100_000,
                'playing': True, 'positionMs': round(position * 1000) if mode == 'joined'
                else round((position - index * 10) * 1000), 'source': Path(path).as_uri()})

    def result(self):
        for name, value in [('receipt.json', self.native), ('runner.json', self.runner),
                            ('capture.wav.timing.json', {'schema': 'readaloud-app-capture-timing-v1',
                             'appPid': 123, 'sampleRate': self.rate, 'frames': len(self.capture),
                             'firstPacketReceivedUnixMicros': self.origin})]:
            (self.directory / name).write_text(json.dumps(value))
        wavfile.write(self.directory / 'capture.wav', self.rate, self.capture)
        return analyze(self.directory)

    def test_identical_pcm_both_actual_queue_shapes(self):
        for mode in ('joined', 'packets'):
            self.set_mode(mode)
            result = self.result()
            self.assertTrue(result['acousticCriteriaMet'], result)
            self.assertTrue(result['runtimeCriteriaMet'], result)
            self.assertFalse(result['passed'])
            self.assertGreaterEqual(result['completeReferenceSeconds'], 50)
            self.assertIsNotNone(result['excludedFinalWaveform'])

    def test_missing_middle_waveform_fails(self):
        self.capture[round(20.3 * self.rate):round(30.3 * self.rate)] = 0
        result = self.result()
        self.assertFalse(result['acousticCriteriaMet'])
        self.assertTrue(any('No complete ordered waveform' in error for error in result['errors']), result)

    def test_external_gap_fails_unchanged_gate(self):
        at = round(20.3 * self.rate)
        self.capture = np.concatenate([self.capture[:at], np.zeros(round(.05 * self.rate), dtype='<i2'),
                                       self.capture[at:]])
        result = self.result()
        self.assertFalse(result['acousticCriteriaMet'])
        self.assertTrue(any('exceeds 10ms' in error for error in result['errors']), result)

    def test_bad_hash_and_source_map_refused(self):
        self.native['sourceProvenance']['expectedPackets'][2]['reference']['sha256'] = '0' * 64
        result = self.result()
        self.assertFalse(result['acousticCriteriaMet'])
        self.assertTrue(any('differs from source receipt' in error for error in result['errors']), result)

    def test_joined_native_uri_must_be_actual(self):
        self.native['playerSamples'][300]['source'] = Path(self.rows[3]['sourcePath']).as_uri()
        result = self.result()
        self.assertFalse(result['acousticCriteriaMet'])
        self.assertIn('Native observation absent from actual queue', result['errors'])

    def test_quiet_tail_requires_captured_silence(self):
        self.capture[-self.rate:] = 500
        result = self.result()
        self.assertFalse(result['acousticCriteriaMet'])
        self.assertTrue(any('quiet interval' in error for error in result['errors']), result)

    def test_native_hang_reported_independently(self):
        self.native['nativeMainResponsiveness'].update(passed=False, maxRoundTripMs=690)
        result = self.result()
        self.assertTrue(result['acousticCriteriaMet'], result)
        self.assertFalse(result['runtimeCriteriaMet'])
        self.assertIn('Unchanged 250ms native/UI responsiveness gate failed', result['runtimeFailures'])

    def test_any_mlx_child_fails_runtime(self):
        self.runner['maxMlxChildren'] = 1
        result = self.result()
        self.assertFalse(result['runtimeCriteriaMet'])
        self.assertFalse(result['passed'])


if __name__ == '__main__':
    unittest.main()
