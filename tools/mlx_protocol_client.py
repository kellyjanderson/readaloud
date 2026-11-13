"""Bounded synchronous client for the production MLX JSON-lines protocol.

The caller owns this client and one child, with one request active at a time.
selectors drains both pipes; there is no job queue or shared result bus. Timeout,
cancel, protocol failure and callback failure retire/reap the child before return.
No partial output is promoted to a successful result. Request IDs are per child.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


class ProtocolError(RuntimeError):
    pass


class RequestCancelled(ProtocolError):
    pass


class MlxClient:
    MAX_LINE = 1024 * 1024
    MAX_OUTPUT = 16 * 1024 * 1024
    MAX_EVENTS = 16384
    STDERR_TAIL = 16384

    def __init__(self, command=None, *, shutdown_timeout=5):
        # Probes use explicit local checkpoints and already prepared references.
        # Keep Hugging Face/provider resolution offline in this owned child;
        # never mutate the application's or caller's process environment.
        environment = dict(os.environ, HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1')
        self.child = subprocess.Popen(command or [sys.executable, '-u', str(ROOT / 'assets/mlx_tts_worker.py')],
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, bufsize=0, env=environment)
        self.selector = selectors.DefaultSelector()
        for pipe, name in ((self.child.stdout, 'stdout'), (self.child.stderr, 'stderr')):
            os.set_blocking(pipe.fileno(), False)
            self.selector.register(pipe, selectors.EVENT_READ, name)
        os.set_blocking(self.child.stdin.fileno(), False)
        self.buffer = bytearray()
        self.stderr = bytearray()
        self.sequence = 0
        self.active = False
        self.closed = False
        self.shutdown_timeout = shutdown_timeout

    def __enter__(self):
        return self

    def __exit__(self, kind, value, traceback):
        if kind:
            self.retire()
        else:
            self.close()

    def retire(self):
        """Hard cancellation, including an uncooperative inference producer."""
        if not self.closed:
            try:
                if self.child.poll() is None:
                    self.child.terminate()
                    try:
                        self.child.wait(timeout=1)
                    except subprocess.TimeoutExpired:
                        self.child.kill()
                self.child.wait(timeout=2)
            finally:
                self._dispose()
        if self.child.poll() is None:
            raise ProtocolError('Owned MLX child did not exit')

    def _dispose(self):
        self.closed = True
        self.selector.close()
        for pipe in (self.child.stdin, self.child.stdout, self.child.stderr):
            pipe.close()
        self.buffer.clear()

    def request(self, command, *, timeout=600, cancel=None, on_event=None, **payload):
        if self.closed or self.active:
            raise ProtocolError('Client is closed or already owns a request')
        if 'id' in payload or 'command' in payload:
            raise ValueError('Request envelope fields are owned by the client')
        if timeout <= 0:
            raise ValueError('Timeout must be positive')
        self.active = True
        self.sequence += 1
        request_id = str(self.sequence)
        packet_count = 0
        frame_count = 0
        packet_rate = None
        events = 0
        output_bytes = 0
        deadline = time.monotonic() + timeout
        try:
            data = json.dumps(dict(payload, id=request_id, command=command), allow_nan=False).encode() + b'\n'
            if len(data) > self.MAX_LINE:
                raise ProtocolError('Request exceeded line bound')
            self.selector.register(self.child.stdin, selectors.EVENT_WRITE, 'stdin')
            offset = 0
            while True:
                if cancel is not None and cancel.is_set():
                    raise RequestCancelled('MLX request cancelled; child retired')
                if time.monotonic() >= deadline:
                    raise TimeoutError(f'MLX {command} timed out; child retired')
                while b'\n' in self.buffer:
                    if cancel is not None and cancel.is_set():
                        raise RequestCancelled('MLX request cancelled; child retired')
                    if time.monotonic() >= deadline:
                        raise TimeoutError(f'MLX {command} timed out; child retired')
                    line, _, rest = self.buffer.partition(b'\n')
                    self.buffer = bytearray(rest)
                    if len(line) > self.MAX_LINE:
                        raise ProtocolError('Response exceeded line bound')
                    try:
                        message = json.loads(line, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
                    except (ValueError, UnicodeError) as error:
                        raise ProtocolError('Malformed MLX JSON response') from error
                    if not isinstance(message, dict):
                        raise ProtocolError('MLX response must be an object')
                    events += 1
                    if events > self.MAX_EVENTS:
                        raise ProtocolError('MLX response exceeded event bound')
                    kind = message.get('type')
                    if kind == 'memory' and message.get('id') == '' and 'ok' not in message:
                        # Process-scoped telemetry is explicitly outside request routing.
                        continue
                    if message.get('id') != request_id:
                        raise ProtocolError('Stale or mismatched MLX response ID')
                    if kind in ('progress', 'audioPacket') and 'ok' not in message:
                        if kind == 'audioPacket':
                            if command != 'synthesize' or payload.get('enableAudioPackets') is not True:
                                raise ProtocolError('Unexpected audio packet')
                            for key in ('sessionId', 'generationId', 'chunkId', 'synthesisIdentity', 'bindingFingerprint', 'bindingRevision'):
                                if message.get(key) != payload.get(key):
                                    raise ProtocolError(f'Mismatched audio packet {key}')
                            if (type(message.get('packetIndex')) is not int or type(message.get('frameStart')) is not int
                                    or message.get('packetIndex') != packet_count or message.get('frameStart') != frame_count
                                    or type(message.get('frameCount')) is not int or message['frameCount'] <= 0):
                                raise ProtocolError('Invalid audio packet order or frame count')
                            rate = message.get('sampleRate')
                            if (type(rate) is not int or not 0 < rate <= 192000
                                    or message.get('channels') != 1 or message.get('bitsPerSample') != 16
                                    or (packet_rate is not None and rate != packet_rate)):
                                raise ProtocolError('Invalid or changing audio packet format')
                            packet_rate = rate
                            packet_count += 1
                            frame_count += message['frameCount']
                            if packet_count > 2048 or frame_count > rate * 600:
                                raise ProtocolError('Audio packet spool exceeded bound')
                        if on_event:
                            on_event(message)
                        continue
                    if kind is not None or type(message.get('ok')) is not bool:
                        raise ProtocolError('Unknown MLX response envelope')
                    if not message['ok']:
                        raise ProtocolError(f"MLX {command} failed: {message.get('error', 'unspecified failure')}")
                    if command == 'synthesize':
                        for key in ('sessionId', 'generationId', 'chunkId', 'synthesisIdentity', 'bindingFingerprint', 'bindingRevision'):
                            if key in payload and message.get(key) != payload[key]:
                                raise ProtocolError(f'Mismatched final {key}')
                        if payload.get('enableAudioPackets') and (type(message.get('streamedPacketCount')) is not int
                                or type(message.get('streamedFrameCount')) is not int
                                or message.get('streamedPacketCount') != packet_count
                                or message.get('streamedFrameCount') != frame_count):
                            raise ProtocolError('Audio packet/final accounting differs')
                        if type(message.get('generatedPieces')) is not int or message['generatedPieces'] <= 0:
                            raise ProtocolError('Missing complete generation count')
                    if cancel is not None and cancel.is_set():
                        raise RequestCancelled('MLX request cancelled; child retired')
                    return message
                if len(self.buffer) > self.MAX_LINE:
                    raise ProtocolError('Response exceeded line bound')
                ready = self.selector.select(min(.05, max(0, deadline - time.monotonic())))
                for key, _ in ready:
                    if key.data == 'stdin':
                        offset += os.write(key.fileobj.fileno(), data[offset:])
                        if offset == len(data):
                            self.selector.unregister(key.fileobj)
                        continue
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        self.selector.unregister(key.fileobj)
                        if key.data == 'stdout':
                            raise ProtocolError(f'MLX child exited before final response ({self.child.poll()}): '
                                                + self.stderr.decode(errors='replace'))
                        continue
                    if key.data == 'stderr':
                        self.stderr.extend(chunk)
                        del self.stderr[:-self.STDERR_TAIL]
                    else:
                        output_bytes += len(chunk)
                        if output_bytes > self.MAX_OUTPUT:
                            raise ProtocolError('MLX response exceeded byte bound')
                        self.buffer.extend(chunk)
        except BaseException:
            self.retire()
            raise
        finally:
            self.active = False

    def metadata(self):
        result = self.request('metadata', timeout=30)
        if result.get('schemaVersion') != 1 or not isinstance(result.get('models'), dict):
            self.retire()
            raise ProtocolError('Unsupported production metadata')
        return result

    def close(self):
        if self.closed:
            return
        try:
            result = self.request('shutdown', timeout=self.shutdown_timeout)
            if result.get('shutdown') is not True:
                raise ProtocolError('MLX child did not acknowledge shutdown')
            # Drain telemetry/stderr while waiting, including children with noisy exit.
            deadline = time.monotonic() + self.shutdown_timeout
            while self.child.poll() is None or self.selector.get_map():
                if time.monotonic() >= deadline:
                    raise TimeoutError('MLX child did not exit after shutdown')
                for key, _ in self.selector.select(.05):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        self.selector.unregister(key.fileobj)
                    elif key.data == 'stdout':
                        self.buffer.extend(chunk)
                        if len(self.buffer) > self.MAX_LINE:
                            raise ProtocolError('Unexpected output after shutdown')
                    else:
                        self.stderr.extend(chunk)
                        del self.stderr[:-self.STDERR_TAIL]
            # The worker's process-scoped memory sampler stops in its main
            # finally block. Its final telemetry can race the shutdown ack.
            for line in self.buffer.splitlines():
                try:
                    message = json.loads(line)
                except (ValueError, UnicodeError) as error:
                    raise ProtocolError('Unexpected output after shutdown') from error
                if (not isinstance(message, dict) or message.get('id') != ''
                        or message.get('type') != 'memory' or 'ok' in message):
                    raise ProtocolError('Unexpected output after shutdown')
            if self.child.wait(timeout=1) != 0:
                raise ProtocolError('MLX child failed during shutdown')
        finally:
            self.retire()
