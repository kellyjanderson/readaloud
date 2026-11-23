"""Probe evidence policy and offline voice resolution, separate from transport."""
from __future__ import annotations

from array import array
import hashlib
from pathlib import Path
import re
import sys
import wave

from mlx_protocol_client import ROOT


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(65536), b''):
            digest.update(block)
    return digest.hexdigest()


def descriptor(metadata, engine):
    try:
        return metadata['models'][engine]
    except KeyError as error:
        raise ValueError(f'Unknown installed production engine: {engine}') from error


def resolve_voice(model, voice_id, reference_cache=None):
    """Never download or silently substitute a reference during a probe."""
    voice = next((value for value in model['voices'] if value['id'] == voice_id), None)
    if voice is None:
        raise ValueError(f'Voice {voice_id} is unavailable for {model["modelId"]}')
    if model['voiceKind'] == 'preset':
        return {'voice': voice_id}, dict(voice)
    digest = voice['sha256']
    candidates = []
    if 'asset' in voice:
        candidates.append(ROOT / voice['asset'])
    if reference_cache:
        extension = 'mp3' if voice.get('url') else 'wav'
        candidates.append(Path(reference_cache) / 'voice-library' / f'{digest}.{extension}')
    reference = next((path.resolve() for path in candidates if path.is_file() and sha256(path) == digest), None)
    if reference is None:
        raise ValueError(f'No verified offline reference for {voice_id}; prepare it in the app first and pass --reference-cache MLX_ROOT')
    return {'voice': voice_id, 'referenceAudioPath': str(reference), 'referenceText': voice['referenceText']}, {
        **voice, 'referenceAudioPath': str(reference), 'verifiedReferenceSha256': digest,
    }


def load_model(client, model, checkpoint, cache, bits):
    checkpoint = Path(checkpoint).expanduser().resolve()
    if not (checkpoint / 'config.json').is_file():
        raise ValueError(f'Explicit local checkpoint config missing: {checkpoint}')
    if model['descriptor'] is not None and bits:
        raise ValueError('Fish variants encode precision in their catalog identity; do not request live quantization')
    result = client.request('load', modelId=model['modelId'], modelPath=str(checkpoint),
                            privateCachePath=str(cache), quantizationBits=bits,
                            requireVerifiedModelAssets=model['descriptor'] is not None)
    if result.get('loaded') is not True or result.get('modelId') != model['modelId'] or not result.get('modelIdentity'):
        raise ValueError('Production load did not return its exact model identity')
    if model['revision'] is not None and result.get('verifiedModelIdentity') != f'{model["repo"]}@{model["revision"]}':
        raise ValueError('Loaded model differs from catalog revision')
    return {**result, 'checkpointPath': str(checkpoint),
            'checkpointConfigSha256': sha256(checkpoint / 'config.json'),
            'checkpointSnapshotRevision': checkpoint.name if checkpoint.parent.name == 'snapshots'
            and re.fullmatch(r'[a-f0-9]{40}', checkpoint.name) else None}


def audio_evidence(path, *, concatenated_pcm=None):
    """Decoded PCM16 accounting is objective evidence, never a listening claim."""
    frames = 0
    peak = 0
    pcm_digest = hashlib.sha256()
    with wave.open(str(path), 'rb') as audio:
        rate, channels, width = audio.getframerate(), audio.getnchannels(), audio.getsampwidth()
        if width != 2 or channels != 1 or rate <= 0:
            raise ValueError('Expected production mono PCM16 output')
        expected = audio.getnframes()
        while block := audio.readframes(32768):
            pcm_digest.update(block)
            if concatenated_pcm is not None:
                concatenated_pcm.update(block)
            samples = array('h', block)
            if sys.byteorder != 'little':
                samples.byteswap()
            peak = max(peak, max((abs(value) for value in samples), default=0))
            frames += len(samples)
    if frames != expected or not frames:
        raise ValueError('Truncated or empty rendered audio')
    return {'audioPath': str(Path(path).resolve()), 'outputSha256': sha256(path), 'pcmSha256': pcm_digest.hexdigest(), 'sampleRate': rate,
            'frames': frames, 'channels': channels, 'durationSeconds': frames / rate, 'peak': peak / 32768}


def synthesize(client, model, voice, text, directory, identity):
    directory.mkdir(exist_ok=False)
    destination = directory / 'complete.wav'
    packet_pcm = hashlib.sha256()
    with (directory / 'events.jsonl').open('x') as events:
        import json
        def preserve(message):
            if message['type'] == 'audioPacket':
                packet = Path(message['audioPath'])
                if packet.parent.resolve() != directory.resolve() or not packet.is_file():
                    raise ValueError('Packet output escaped owned probe directory or is missing')
                evidence = audio_evidence(packet, concatenated_pcm=packet_pcm)
                if evidence['frames'] != message['frameCount'] or evidence['sampleRate'] != message['sampleRate']:
                    raise ValueError('Packet file differs from protocol accounting')
            events.write(json.dumps(message) + '\n')
        result = client.request('synthesize', on_event=preserve, modelId=model['modelId'],
                                text=text, outputPath=str(destination.resolve()), **voice,
                                enableAudioPackets=True, sessionId=identity, generationId=identity,
                                chunkId=identity, synthesisIdentity=identity,
                                bindingFingerprint=identity, bindingRevision=1)
    if result.get('audioPath') != str(destination.resolve()):
        raise ValueError('Final output escaped owned probe directory')
    evidence = audio_evidence(destination)
    if evidence['frames'] != result.get('streamedFrameCount') or evidence['sampleRate'] != result.get('nativeSampleRate'):
        raise ValueError('Final output differs from packet accounting')
    if evidence['pcmSha256'] != packet_pcm.hexdigest():
        raise ValueError('Final PCM differs from concatenated packet samples')
    return {**evidence, 'protocolFinal': result}


def provenance(metadata, model, loaded, bits):
    return {'engine': model['modelId'], 'descriptor': model, 'load': loaded, 'bits': bits,
            'workerSha256': metadata['workerSha256'], 'runtime': metadata['runtime'],
            'voiceLibraries': metadata['voiceLibraries'],
            'seed': None, 'seedPolicy': 'production protocol has no seed override; RNG is uncontrolled',
            'evidenceLimit': 'Offline worker emitted PCM accounting only; no human listening, voice identity, app timing or native process-tree admission qualification. Legacy modelIdentity fingerprints config and file metadata, not complete weight content.'}
