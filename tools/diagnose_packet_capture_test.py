"""Timing-only fixtures: no claim of speech quality or native acceptance."""
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy.io import wavfile

from diagnose_packet_capture import diagnose, match


class PacketCaptureDiagnosticTest(unittest.TestCase):
    def test_full_packets_and_ending_match_but_inserted_gap_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            # Distinct deterministic wide-band packets make a missing/repeated
            # portion detectable, unlike a periodic tone or silent fixture.
            pcm = np.random.default_rng(42).integers(-8000, 8001, 8000, dtype=np.int16)
            wavfile.write(root / 'scene.wav', 8000, pcm)
            wavfile.write(root / 'packet-0000.wav', 8000, pcm[:4000])
            wavfile.write(root / 'packet-0001.wav', 8000, pcm[4000:])
            prefix = np.zeros(1600, dtype=np.int16)
            wavfile.write(root / 'capture.wav', 8000, np.concatenate([prefix, pcm, prefix]))
            complete = diagnose(root / 'capture.wav', root / 'scene.wav', root)
            self.assertTrue(complete['packetPcmExactlyReconstructsFinalScene'])
            self.assertGreaterEqual(complete['minimumFullActivePacketCorrelation'], .98)
            self.assertEqual(complete['packetsBelowStrictThreshold'], [])
            # Insert 40ms inside the last packet. Its full active waveform,
            # including the ending, must fail the unchanged strict threshold.
            broken = np.concatenate([prefix, pcm[:6000], np.zeros(320, np.int16), pcm[6000:], prefix])
            wavfile.write(root / 'capture.wav', 8000, broken)
            failed = diagnose(root / 'capture.wav', root / 'scene.wav', root)
            self.assertIn('packet-0001.wav', failed['packetsBelowStrictThreshold'])

    def test_short_capture_cannot_claim_full_waveform(self):
        with self.assertRaisesRegex(ValueError, 'full active waveform'):
            match(np.ones(100), np.ones(200))


if __name__ == '__main__':
    unittest.main()
