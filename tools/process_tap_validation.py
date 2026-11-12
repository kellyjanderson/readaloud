"""Final exact-PID process-tap integrity contract, shared by offline tools.

This validates saved metadata, never expected content or unobserved time.
No dependency on analyzers: their acoustic policies remain separate.
"""
import math
import uuid


LOSS_COUNTERS = ('droppedBuffers', 'poolOverflows', 'deviceOverloads',
                 'timestampDiscontinuities', 'formatChanges', 'callbackStalls',
                 'writerDiscardedBuffers')


def validate_process_tap(timing, pid, frames, rate, session_id=None):
    def require(condition, message):
        if not condition:
            raise ValueError(f'CoreAudio process tap: {message}')

    def integer(value):
        return isinstance(value, int) and not isinstance(value, bool)

    require(integer(pid) and pid > 0 and integer(timing.get('appPid')) and timing['appPid'] == pid,
            'capture app identity mismatch')
    require(timing.get('schema') == 'readaloud-app-capture-timing-v1'
            and timing.get('mechanism') == 'CoreAudioProcessTap'
            and timing.get('status') == 'complete' and timing.get('errors') == [],
            'timing is not final/clean')
    actual_session = timing.get('sessionID')
    try:
        valid_session = isinstance(actual_session, str) and str(uuid.UUID(actual_session)) == actual_session.lower()
    except (ValueError, AttributeError):
        valid_session = False
    require(valid_session and (session_id is None or actual_session == session_id),
            'missing/invalid/mismatched session identity')
    require(rate in (44100, 48000) and timing.get('sampleRate') == rate
            and integer(frames) and frames > 0
            and all(integer(timing.get(k)) and timing[k] == frames
                    for k in ('frames', 'framesReceived', 'framesSubmitted')),
            'incomplete received/submitted/written frames')
    for field in LOSS_COUNTERS:
        require(integer(timing.get(field)) and timing[field] == 0,
                f'nonzero/missing {field}')
    require(integer(timing.get('buffersSubmitted')) and timing['buffersSubmitted'] > 0
            and integer(timing.get('buffersWritten'))
            and timing['buffersWritten'] == timing['buffersSubmitted']
            and integer(timing.get('callbacks')) and timing['callbacks'] >= timing['buffersSubmitted'],
            'incomplete buffers')
    gap = timing.get('maxPacketGapSeconds')
    require(isinstance(gap, (int, float)) and not isinstance(gap, bool)
            and math.isfinite(gap) and 0 <= gap <= .010,
            'packet timing gap exceeds 10ms')
    return actual_session
