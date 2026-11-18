"""Adapt one bounded local audition to the existing MLX protocol client."""
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mlx_probe_support import audio_evidence, descriptor, resolve_voice
from mlx_protocol_client import MlxClient


MODEL_ID = 'fish_drama3'
RUNTIME_PACKAGES = {'mlx': '0.32.4', 'mlx-audio': '0.6.3'}


def emit(**message):
    print(json.dumps(message, allow_nan=False), flush=True)


def render(request, cancelled):
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise RuntimeError('Fish requires the arm64 macOS MLX runtime. Use the installed arm64 interpreter.')
    pressure = subprocess.run(['/usr/sbin/sysctl', '-n', 'kern.memorystatus_vm_pressure_level'],
                              capture_output=True, text=True, timeout=2)
    if pressure.returncode or pressure.stdout.strip() != '1':
        raise RuntimeError('Fish needs normal macOS memory pressure. Close other memory-intensive applications and retry.')
    checkpoint = Path(request['checkpoint']).resolve(strict=True)
    output = Path(request['output']).resolve()
    turns = request['turns']
    with MlxClient() as client:
        metadata = client.request('metadata', timeout=15, cancel=cancelled)
        if any(metadata['runtime']['packages'].get(name) != version
               for name, version in RUNTIME_PACKAGES.items()):
            raise RuntimeError('Fish requires mlx 0.32.4 and mlx-audio 0.6.3. Run tools/install_mlx_tts_runtime.sh.')
        model = descriptor(metadata, MODEL_ID)
        refs = {
            voice: resolve_voice(model, voice, request['referenceCache'])
            for voice in dict.fromkeys(turn['voice'] for turn in turns)
        }
        references = [item[0] for item in refs.values()]
        reference_receipts = [{
            **payload, 'slot': slot, 'label': receipt['label'],
            'sha256': receipt['verifiedReferenceSha256'],
        } for slot, (payload, receipt) in enumerate(refs.values())]

        def progress(message):
            if message.get('type') == 'progress':
                emit(type='progress', **{key: message[key] for key in
                     ('stage', 'message', 'completed', 'total', 'unit') if key in message})

        loaded = client.request('load', timeout=300, cancel=cancelled, on_event=progress,
                                modelId=MODEL_ID, modelPath=str(checkpoint),
                                privateCachePath=request['privateCache'], quantizationBits=0,
                                requireVerifiedModelAssets=True,
                                runtimeMemoryLimitBytes=request['runtimeMemoryLimitBytes'])
        if (loaded.get('modelId') != MODEL_ID or loaded.get('loaded') is not True
                or loaded.get('nativeScenesQualified') is not True
                or loaded.get('modelAssetsVerified') is not True
                or loaded.get('verifiedModelIdentity') != model['repo'] + '@' + model['revision']
                or not loaded.get('modelIdentity')):
            raise RuntimeError('The local checkpoint did not verify for native scenes. Select the pinned Drama 3 bf16 snapshot.')
        slot_for = {voice: index for index, voice in enumerate(refs)}
        model_text = '\n'.join(f"<|speaker:{slot_for[turn['voice']]}|> {turn['text']}" for turn in turns)
        synthesis_request = {
            'modelId': MODEL_ID,
            'text': '\n'.join(turn['text'] for turn in turns),
            'voice': turns[0]['voice'],
            'references': references,
            'sceneTurns': turns,
            'outputPath': str(output),
            'enableAudioPackets': True,
            'sessionId': request['id'], 'generationId': request['id'],
            'chunkId': request['id'], 'synthesisIdentity': request['id'],
            'bindingFingerprint': request['id'], 'bindingRevision': 1,
        }
        packet_pcm = hashlib.sha256()
        last_reported = 0.0

        def capture(message):
            nonlocal last_reported
            if message.get('type') != 'audioPacket':
                progress(message)
                return
            packet = Path(message['audioPath']).resolve()
            if packet.parent != output.parent or not packet.is_file():
                raise RuntimeError('Worker audio escaped the private staging directory.')
            evidence = audio_evidence(packet, concatenated_pcm=packet_pcm)
            if evidence['frames'] != message['frameCount'] or evidence['sampleRate'] != message['sampleRate']:
                raise RuntimeError('Worker audio packet differs from its reported frame count or sample rate.')
            packet.unlink()
            now = time.monotonic()
            if now - last_reported >= 0.25:
                last_reported = now
                emit(type='progress', stage='synthesis', message='Rendering the ordered scene',
                     completed=message['frameStart'] + message['frameCount'], total=None, unit='frames')

        final = client.request('synthesize', timeout=180, cancel=cancelled, on_event=capture,
                               **synthesis_request)
        if final['audioPath'] != str(output):
            raise RuntimeError('Worker published audio outside the owned staging file.')
        evidence = audio_evidence(output)
        if (evidence['frames'] != final['streamedFrameCount']
                or evidence['sampleRate'] != final['nativeSampleRate']
                or evidence['pcmSha256'] != packet_pcm.hexdigest()
                or evidence['peak'] == 0):
            raise RuntimeError('The completed WAV must match the worker packets and contain non-silent PCM.')
        # The transport stage is disposable. The Node request publishes the WAV
        # after the complete result and verified worker shutdown have arrived.
        del evidence['audioPath']
        return {
            **evidence,
            'modelId': MODEL_ID,
            'modelIdentity': loaded['modelIdentity'],
            'verifiedModelIdentity': loaded['verifiedModelIdentity'],
            'modelAssetsVerified': loaded['modelAssetsVerified'],
            'nativeScenesQualified': loaded['nativeScenesQualified'],
            'generatedPieces': final['generatedPieces'],
            'streamedPacketCount': final['streamedPacketCount'],
            'runtime': metadata['runtime'],
            'workerSha256': metadata['workerSha256'],
            'workerProcessId': client.child.pid,
            'request': {**synthesis_request, 'modelText': model_text},
            'referenceReceipts': reference_receipts,
        }


def main():
    cancelled = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: cancelled.set())
    try:
        raw = sys.stdin.buffer.readline(64 * 1024 + 1)
        if len(raw) > 64 * 1024:
            raise ValueError('Fish request exceeded its transport budget.')
        result = render(json.loads(raw), cancelled)
        if cancelled.is_set():
            raise RuntimeError('Fish audition was cancelled.')
        emit(ok=True, result=result)
    except Exception as error:
        emit(ok=False, error=str(error))


if __name__ == '__main__':
    main()
