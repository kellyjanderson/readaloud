"""Metadata integrity controls; these make no acoustic acceptance claim."""
import unittest

from process_tap_validation import LOSS_COUNTERS, validate_process_tap


def clean_tap_timing(timing):
    """Complete deterministic helper receipt for analyzer fixtures."""
    return dict(timing, mechanism='CoreAudioProcessTap', status='complete', errors=[],
                processAudioObjectID=124, privateTap=True, privateAggregate=True,
                muteBehavior='unmuted',
                sessionID='ca751a73-9705-475b-ac94-ac86ab7e6f8d',
                **{key: 0 for key in LOSS_COUNTERS},
                framesReceived=timing['frames'], framesSubmitted=timing['frames'],
                buffersSubmitted=20, buffersWritten=20, callbacks=20,
                maxPacketGapSeconds=0.)


class ProcessTapIntegrityTest(unittest.TestCase):
    def setUp(self):
        self.timing = clean_tap_timing({'schema': 'readaloud-app-capture-timing-v1',
                                       'appPid': 123, 'frames': 1000, 'sampleRate': 48000})

    def validate(self, **kwargs):
        return validate_process_tap(self.timing, 123, 1000, 48000, **kwargs)

    def test_clean_exact_session(self):
        self.assertEqual(self.validate(session_id=self.timing['sessionID']), self.timing['sessionID'])

    def test_each_missing_loss_counter_refuses(self):
        for key in LOSS_COUNTERS:
            with self.subTest(key=key):
                value = self.timing.pop(key)
                with self.assertRaises(ValueError):
                    self.validate()
                self.timing[key] = value

    def test_missing_or_malformed_capture_source_properties_refuse(self):
        mutations = {
            'processAudioObjectID': (None, 0, -1, True, '124', 124.),
            'privateTap': (None, False, 1, 'true'),
            'privateAggregate': (None, False, 1, 'true'),
            'muteBehavior': (None, True, 'muted', 'Unmuted'),
        }
        for key, values in mutations.items():
            original = self.timing[key]
            for value in values:
                with self.subTest(key=key, value=value):
                    self.timing[key] = value
                    with self.assertRaises(ValueError):
                        self.validate()
            self.timing.pop(key)
            with self.subTest(key=key, value='missing'):
                with self.assertRaises(ValueError):
                    self.validate()
            self.timing[key] = original

    def test_dirty_missing_mismatched_and_nonfinite_metadata_refuses(self):
        mutations = {'appPid': 124, 'sessionID': None, 'framesReceived': 999,
                     'framesSubmitted': 999, 'buffersWritten': 19, 'callbacks': 19,
                     'status': 'capturing', 'errors': ['failure'],
                     'maxPacketGapSeconds': float('nan'), 'droppedBuffers': True}
        for key, value in mutations.items():
            with self.subTest(key=key):
                original = self.timing[key]
                self.timing[key] = value
                with self.assertRaises(ValueError):
                    self.validate()
                self.timing[key] = original
        with self.assertRaises(ValueError):
            self.validate(session_id='b224835a-0255-41b7-af66-b7cfbf893bb7')


if __name__ == '__main__':
    unittest.main()
