"""Generated acoustic fixtures for the bounded cancellation analyzer."""
import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly

from analyze_packet_cancellation import analyze


class CancellationEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.rate = 48000
        self.origin = 1_000_000_000_000
        stamp = lambda seconds: self.origin + round(seconds * 1_000_000)
        source_rate = 44100
        t = np.arange(round(.2 * source_rate)) / source_rate
        # A varying speech-like envelope and chirp provide a distinctive local
        # waveform. This fixture proves capture matching, not speech content.
        self.source = (.15 * np.sin(2 * np.pi * (220 * t + 1300 * t * t)) *
                       np.minimum(t / .005, 1) * (.7 + .3 * np.sin(2 * np.pi * 19 * t)))
        self.reference = self.root / 'queued-0.wav'
        self.write_reference(self.source)
        self.capture = np.zeros(4 * self.rate)
        mixed = resample_poly(self.source, 160, 147)
        self.capture[72000:72000 + len(mixed)] = mixed
        self.capture_path = self.root / 'capture.wav'
        self.write_capture()
        scene = dict(completed=False, audioDurationMicros=0)
        active = dict(unknownActiveScene=True, spokenScenes=[scene],
                      completedOrdinaryScenes=0, completedExports=0)
        event = lambda name, second, **values: dict(event=name,
                                                  unixMicros=stamp(second), **values)
        self.receipt = dict(
            schema='readaloud-native-packet-cancellation-v1',
            passed=True, functionalPassed=True, resourceShutdownComplete=True,
            sceneIncompleteAtFirstPacket=True, shutdownErrors=[],
            nativeMainResponsiveness=dict(passed=True),
            finalNativeResources=dict(playerPlaying=False, pendingPlaybackPreparationTasks=0,
                                      playbackPins=0, resourcesReady=False),
            speechWorkActivity=dict(active=0, started=2, ended=2),
            playerStateOverflow=False, nativePlayerStoppedEventIndex=1,
            playerStateEvents=[dict(playing=True, unixMicros=stamp(1.4)),
                               dict(playing=False, unixMicros=stamp(1.752)),
                               dict(playing=False, unixMicros=stamp(2.8))],
            cancellationEvents=[
                event('native-cancel-intent-observed', .4, pendingIntent=False,
                      playerPlaying=False),
                event('cold-preparation-drained', .8),
                event('retry-play-request', 1),
                event('packet-pause-request', 1.75, playerPlaying=True, **active),
                event('packet-pause-returned', 1.752, playerPlaying=False),
                event('packet-pause-observation-ended', 2.8)],
            firstNativePacket=dict(unixMicros=stamp(1.4), nativeIndex=0, **active),
            nativePlaybackIntervalBeforePause=dict(sampledPositionTotalMs=185,
                playerPlaying=True, unknownActiveScene=True,
                completedOrdinaryScenes=0, completedExports=0),
            queuedAudio=[dict(queueIndex=0, path=str(self.reference),
                sha256=hashlib.sha256(self.reference.read_bytes()).hexdigest())],
            packetPauseCoverage='native packet before complete scene; paused',
            coldInputMode='external-native-input', coldCancelDrainMs=600,
            packetPauseDrainMs=2)
        self.runner = dict(passed=True, nativePassed=True, normalQuit=True,
                           appExitVerified=True, forcedCleanup=False,
                           remainingOwnedPids=[], ownedPidsAfterNormalQuit=[],
                           errors=[], captureExitStatus=0)
        self.timing = dict(sampleRate=self.rate, frames=len(self.capture),
                           firstPacketReceivedUnixMicros=self.origin,
                           firstSignalReceivedUnixMicros=stamp(1.5), firstSignalFrame=72000)
        self.native_input = dict(clickBeforeUnixMicros=stamp(.35),
                                 clickReturnedUnixMicros=stamp(.38))

    def write_reference(self, source):
        wavfile.write(self.reference, 44100, np.int16(np.clip(source, -1, 1) * 32767))

    def write_capture(self):
        wavfile.write(self.capture_path, self.rate, self.capture.astype(np.float32))

    def run_analysis(self):
        return analyze(self.receipt, self.runner, self.capture_path,
                       self.timing, self.native_input)

    def test_matches_short_prefix_and_keeps_input_wait_separate_from_drain(self):
        result = self.run_analysis()
        self.assertTrue(result['passed'])
        self.assertGreaterEqual(result['prefix']['correlation'], .98)
        self.assertEqual(result['prefix']['durationMs'], 40)
        self.assertEqual(result['coldCancellation']['drainAfterIntentMs'], 400)
        self.assertEqual(result['coldCancellation']['nativeInput'][
            'clickBeforeToIntentObservedMs'], 50)

    def test_silent_capture_cannot_prove_audible_prefix(self):
        self.capture[:] = 0
        self.write_capture()
        with self.assertRaisesRegex(ValueError, 'No first-packet'):
            self.run_analysis()

    def test_different_plausible_waveform_cannot_substitute_for_queued_prefix(self):
        t = np.arange(9600) / self.rate
        self.capture[72000:81600] = .2 * np.sin(2 * np.pi * 901 * t)
        self.write_capture()
        with self.assertRaisesRegex(ValueError, 'No first-packet'):
            self.run_analysis()

    def test_late_audio_and_pre_retry_audio_fail_independently(self):
        for sample, message in [(3 * self.rate, 'Late audio'), (1000, 'Audio before retry')]:
            with self.subTest(message=message):
                self.capture[sample] = .2
                self.write_capture()
                with self.assertRaisesRegex(ValueError, message):
                    self.run_analysis()
                self.capture[sample] = 0

    def test_native_resume_or_complete_scene_cannot_qualify(self):
        self.receipt['playerStateEvents'][-1]['playing'] = True
        with self.assertRaisesRegex(ValueError, 'resumed'):
            self.run_analysis()
        self.receipt['playerStateEvents'][-1]['playing'] = False
        self.receipt['firstNativePacket']['spokenScenes'] = [
            dict(completed=False, audioDurationMicros=200000)]
        with self.assertRaisesRegex(ValueError, 'unfinished source ownership'):
            self.run_analysis()

    def test_insufficient_tail_refuses(self):
        self.capture = self.capture[:round(2.3 * self.rate)]
        self.write_capture()
        self.timing['frames'] = len(self.capture)
        with self.assertRaisesRegex(ValueError, '500ms'):
            self.run_analysis()

    def test_reference_hash_and_external_input_order_are_authoritative(self):
        self.receipt['queuedAudio'][0]['sha256'] = 'wrong'
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.run_analysis()
        self.receipt['queuedAudio'][0]['sha256'] = hashlib.sha256(
            self.reference.read_bytes()).hexdigest()
        self.native_input['clickReturnedUnixMicros'] = self.origin + 900000
        with self.assertRaisesRegex(ValueError, 'timestamps out of order'):
            self.run_analysis()


if __name__ == '__main__':
    unittest.main()
