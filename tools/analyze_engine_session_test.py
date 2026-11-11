"""Synthetic positive and refusal controls, not native/model acceptance."""
import copy
import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.io import wavfile

from analyze_engine_session import analyze


class EngineSessionEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.rate = 48000
        source = np.zeros(round(.32 * self.rate), dtype=np.float32)
        source[960:] = np.random.default_rng(5).normal(0, .06, len(source) - 960)
        self.reference = self.root / 'reference.wav'
        wavfile.write(self.reference, self.rate, source)
        self.capture = np.zeros(3 * self.rate, dtype=np.float32)
        self.capture[9600:9600 + len(source)] = source * .75
        self.path = self.root / 'capture.wav'
        wavfile.write(self.path, self.rate, self.capture)
        self.timing = dict(sampleRate=self.rate, frames=len(self.capture),
                           firstPacketReceivedUnixMicros=1000000,
                           firstSignalReceivedUnixMicros=1220000,
                           firstSignalFrame=10560)
        self.receipt = dict(
            schema='readaloud-native-engine-session-v1', passed=True,
            functionalPassed=True, resourceShutdownComplete=True, offline=True,
            shutdownErrors=[], nativeMainResponsiveness=dict(passed=True, maxRoundTripMs=200),
            maxUiHeartbeatDelayMs=10, speechWorkActivity=dict(active=0, started=4, ended=4),
            retainedAnchor=9, positivePauseRequestedUnixMicros=1650000,
            positivePauseReturnedUnixMicros=1652000,
            positiveReference=dict(path=str(self.reference),
                sha256=hashlib.sha256(self.reference.read_bytes()).hexdigest()),
            events=[dict(event='offline-failed', selected='fish_drama3_8bit', active=None,
                         lastWorking='fish_drama3', sessionPhase='failed'),
                    dict(event='complete', selected='fish_drama3', active='fish_drama3',
                         lastWorking='fish_drama3', sessionPhase='active',
                         startupError=None, pendingPlay=False, playing=False, word=9)])
        self.runner = dict(passed=True, nativePassed=True, normalQuit=True,
                           appExitVerified=True, ownedAliasAbsent=True,
                           forcedCleanup=False, remainingOwnedPids=[], errors=[],
                           captureExitStatus=0, maxMlxChildren=1, observedMlxSamples=10)

    def run_analysis(self):
        return analyze(self.receipt, self.runner, self.timing, self.path)

    def test_positive_prefix_and_switch_silence(self):
        result = self.run_analysis()
        self.assertTrue(result['passed'])
        self.assertGreaterEqual(result['prefixCorrelation'], .98)
        self.assertEqual(result['postPausePeak'], 0)

    def test_refuses_late_audio(self):
        self.capture[2 * self.rate:2 * self.rate + 200] = .02
        wavfile.write(self.path, self.rate, self.capture)
        with self.assertRaisesRegex(ValueError, 'Obsolete audio'):
            self.run_analysis()

    def test_refuses_wrong_positive_audio(self):
        self.capture[9600:9600 + 15360] = np.random.default_rng(9).normal(0, .04, 15360)
        wavfile.write(self.path, self.rate, self.capture)
        with self.assertRaisesRegex(ValueError, 'Positive prefix'):
            self.run_analysis()

    def test_refuses_unavailable_active_variant(self):
        self.receipt['events'][0]['active'] = 'fish_drama3_8bit'
        with self.assertRaises(ValueError):
            self.run_analysis()

    def test_refuses_missing_anchor_and_pending_play(self):
        self.receipt['events'][-1]['pendingPlay'] = True
        with self.assertRaises(ValueError):
            self.run_analysis()

    def test_refuses_overlap_or_incomplete_cleanup(self):
        valid = copy.deepcopy(self.runner)
        for key, value in [('maxMlxChildren', 2), ('remainingOwnedPids', [123]),
                           ('forcedCleanup', True), ('ownedAliasAbsent', False)]:
            self.runner = {**valid, key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.run_analysis()


if __name__ == '__main__':
    unittest.main()
