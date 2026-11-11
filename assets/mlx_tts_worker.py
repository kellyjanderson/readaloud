"""Persistent JSON-lines worker for local MLX TTS inference.

The Flutter/Dart runtime owns requests, cache identity, playback and export.
This child owns one loaded model and one in-flight inference at a time.
"""

from __future__ import annotations

import contextlib
import ctypes
import gc
import hashlib
import json
import os
import sys
import tempfile
import threading
import time
import traceback
import wave
from pathlib import Path
from typing import Any


DRAMA_MODELS = json.loads(Path(__file__).with_name("fish_drama_models.json").read_text())
MODEL_IDS = set(DRAMA_MODELS) | {"qwen3_tts_1_7b", "qwen3_tts_base_1_7b", "voxtral_4b", "moss_tts_8b"}
MODEL_REPOSITORIES = {
    "qwen3_tts_1_7b": "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16",
    "qwen3_tts_base_1_7b": "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
    "voxtral_4b": "mlx-community/Voxtral-4B-TTS-2603-mlx-bf16",
    "moss_tts_8b": "OpenMOSS-Team/MOSS-TTS-v1.5",
}
QWEN_VOICES = {"Ryan", "Aiden", "Vivian", "Serena", "Dylan", "Eric", "Uncle_Fu", "Ono_Anna", "Sohee"}
VOXTRAL_VOICES = {
    "casual_male",
    "casual_female",
    "neutral_male",
    "neutral_female",
    "cheerful_female",
    "pt_male", "pt_female", "nl_male", "nl_female", "it_male", "it_female",
    "fr_male", "fr_female", "es_male", "es_female", "de_male", "de_female",
    "ar_male", "hi_male", "hi_female",
}

_model: Any = None
_model_id: str | None = None
_model_path: str | None = None
_model_bits = 0
_model_native_scenes = False
_model_load_stream: Any = None
_model_pending_parameters: Any = None
_protocol_stdout = sys.stdout
_active_request_id = ""
_output_lock = threading.Lock()


def _reply(request_id: str, **payload: Any) -> None:
    # Download progress and the memory sampler can publish from other threads.
    with _output_lock:
        _protocol_stdout.write(json.dumps({"id": request_id, **payload}, separators=(",", ":")) + "\n")
        _protocol_stdout.flush()


def _physical_footprint() -> int:
    # The sandbox permits self-inspection but forbids the GUI from inspecting
    # its child. Match Darwin's rusage_info_v2 ABI, including its UUID prefix.
    class RusageInfoV2(ctypes.Structure):
        _fields_ = [("uuid", ctypes.c_uint8 * 16),
                    ("counters", ctypes.c_uint64 * 18)]

    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    libproc.proc_pid_rusage.restype = ctypes.c_int
    info = RusageInfoV2()
    if libproc.proc_pid_rusage(os.getpid(), 2, ctypes.byref(info)) != 0:
        raise OSError(ctypes.get_errno(), "Could not sample inference memory")
    return int(info.counters[7])  # ri_phys_footprint


def _report_memory(stop: threading.Event) -> None:
    # One daemon per child, no job queue. Process retirement owns cancellation.
    while not stop.is_set():
        try:
            _reply("", type="memory", footprintBytes=_physical_footprint())
        except Exception as error:
            _reply("", type="memory", error=str(error))
            return
        stop.wait(2)


def _unload() -> None:
    global _model, _model_id, _model_path, _model_native_scenes, _model_load_stream
    # If a join fails, retain its model/tree/stream ownership until retry or
    # process retirement. Never drop a stream that may still own queued work.
    _join_model_weights()
    _model = None
    _model_id = None
    _model_path = None
    _model_native_scenes = False
    _model_load_stream = None
    gc.collect()
    try:
        import mlx.core as mx

        mx.clear_cache()
    except Exception:
        pass


def _join_model_weights() -> None:
    global _model_pending_parameters
    if _model_pending_parameters is not None:
        import mlx.core as mx

        # The protocol thread owns the stream and the one pending tree. No
        # loaded response, model replacement or clean shutdown may outrun it.
        # Hard cancellation remains retirement of this worker process.
        mx.eval(_model_pending_parameters)
        mx.synchronize(_model_load_stream)
        _model_pending_parameters = None


def _timing(stage: str, started: float) -> None:
    # Stage duration is diagnostic, never a fabricated work percentage. Include
    # it in progress so successful app probes can retain it as well as stderr.
    elapsed = round((time.monotonic() - started) * 1000, 3)
    print('[readaloud-timing] ' + json.dumps({
        'requestId': _active_request_id, 'stage': stage,
        'elapsedMilliseconds': elapsed,
    }, separators=(',', ':')), file=sys.stderr, flush=True)
    message = {
        'modelBuildAndCodec': 'Speech model and codec constructed',
        'modelVerification': 'Speech model qualification checked',
        'modelWeights': 'Remaining speech model weights ready',
        'modelWeightsAndVerification': 'Speech model weights and qualification ready',
        'modelLoadTotal': 'Speech model prepared',
        'referencePrepared': 'Reference voice prepared',
        'referencePreparationFailed': 'Reference voice preparation failed',
        'synthesisFirstPacket': 'First native audio packet rendered',
    }[stage]
    _progress(f'{message} ({elapsed:g} ms)', stage=stage,
              elapsed_milliseconds=elapsed)


def _progress(message: str, *, stage: str, completed: int | None = None,
              total: int | None = None, unit: str = "bytes",
              elapsed_milliseconds: float | None = None) -> None:
    if not _active_request_id:
        return
    _reply(_active_request_id, type="progress", stage=stage, message=message,
           completed=completed, total=total, unit=unit,
           **({'elapsedMilliseconds': elapsed_milliseconds}
              if elapsed_milliseconds is not None else {}))


def _download_progress_class(total_bytes: int | None, cached_bytes: int):
    from tqdm import tqdm

    class ProgressTqdm(tqdm):
        _last_report = 0.0

        def _emit_progress(self):
            # HF owns aggregate reconstruction accounting, including resumed
            # bytes. Its separate transfer bar starts at zero on every retry
            # and must not be presented as whole-model completion.
            if not getattr(self, 'desc', '').startswith('Reconstructing'):
                return
            now = time.monotonic()
            if now - self._last_report < 0.4:
                return
            self._last_report = now
            completed = cached_bytes + int(self.n)
            _progress('Downloading remaining speech model files…',
                      stage='modelDownload',
                      completed=min(total_bytes, completed) if total_bytes is not None else completed,
                      total=total_bytes)

        def update(self, n=1):
            result = super().update(n)
            self._emit_progress()
            return result

        def refresh(self, *args, **kwargs):
            result = super().refresh(*args, **kwargs)
            self._emit_progress()
            return result

    return ProgressTqdm


def _complete_snapshot(directory: Path, model_id: str) -> bool:
    required = DRAMA_MODELS.get(model_id, {}).get('requiredFiles')
    if required is None:
        required = ['config.json']
        # A config alone is a partial download, not an installed model.
        weights = list(directory.glob('*.safetensors'))
        if not weights:
            return False
        required += [weight.name for weight in weights]
        for index in directory.glob('*.safetensors.index.json'):
            try:
                required += list(set(json.loads(index.read_text())['weight_map'].values()))
            except (OSError, ValueError, KeyError):
                return False
    try:
        return all((directory / name).is_file() and (directory / name).stat().st_size > 0
                   for name in required)
    except OSError:
        return False


def _download_model(model_id: str, private_cache_path: str) -> Path:
    from huggingface_hub import snapshot_download
    from huggingface_hub import constants as hf_constants

    spec = DRAMA_MODELS.get(model_id)
    repo_id = spec['repo'] if spec else MODEL_REPOSITORIES[model_id]
    revision = spec['revision'] if spec else None
    private_cache = Path(private_cache_path).expanduser()
    configured_cache = Path(os.environ.get('HF_HUB_CACHE') or
                            os.environ.get('HUGGINGFACE_HUB_CACHE') or
                            str(hf_constants.HF_HUB_CACHE)).expanduser()
    candidates = list(dict.fromkeys([private_cache, configured_cache]))
    # Check every accessible cache before any network request. No build number,
    # executable path or debug/release mode is part of this persistent identity.
    for cache_dir in candidates:
        try:
            cached = Path(snapshot_download(repo_id=repo_id, revision=revision,
                          cache_dir=str(cache_dir), local_files_only=True))
            if _complete_snapshot(cached, model_id):
                _configure_hf_cache(cache_dir, hf_constants)
                _progress('Using downloaded speech model files', stage='modelCached')
                return cached
        except (OSError, ValueError):
            pass

    # One destination per attempt: retries resume the same blobs. A network
    # failure must never start a second copy in a different cache.
    private_cache.mkdir(parents=True, exist_ok=True)
    _progress('Checking saved files and remaining download size…', stage='modelCache')
    plan = snapshot_download(repo_id=repo_id, revision=revision,
                             cache_dir=str(private_cache), dry_run=True,
                             allow_patterns=spec['requiredFiles'] if spec else None)
    total = (sum(item.file_size for item in plan)
             if all(item.file_size is not None for item in plan) else None)
    cached_bytes = sum(item.file_size or 0 for item in plan if not item.will_download)
    _progress('Reusing saved files; downloading only missing model data…',
              stage='modelDownload', completed=cached_bytes, total=total)
    # Freeze the metadata revision even for models whose catalog uses main.
    resolved_revision = revision or (plan[0].commit_hash if plan else None)
    snapshot = snapshot_download(
        repo_id=repo_id, revision=resolved_revision, cache_dir=str(private_cache),
        allow_patterns=spec['requiredFiles'] if spec else None,
        tqdm_class=_download_progress_class(total, cached_bytes),
    )
    resolved = Path(snapshot)
    if not _complete_snapshot(resolved, model_id):
        raise FileNotFoundError(f'Model download is incomplete: {resolved}')
    _configure_hf_cache(private_cache, hf_constants)
    return resolved


def _configure_hf_cache(cache_dir: Path, hf_constants: Any) -> None:
    cache = str(cache_dir.expanduser())
    os.environ["HF_HUB_CACHE"] = cache
    os.environ["HUGGINGFACE_HUB_CACHE"] = cache
    hf_constants.HF_HUB_CACHE = cache


def _verify_scene_model(directory: Path, manifest: dict, receipt_root: Path) -> bool:
    """Offline capability qualification, independent of the selected engine name.

    Hub's verify_repo_checksums requires a network tree query and rehashes every
    file. Reuse its hashing implementation with our bundled immutable tree and
    retain an app-owned stat-bound qualification receipt, not model-history data.
    """
    from huggingface_hub.utils._verification import compute_file_hash
    entries = manifest['files']
    expected_weights = {name for name in entries if name.endswith('.safetensors')}
    if {p.name for p in directory.glob('*.safetensors')} != expected_weights:
        return False
    def snapshot():
        result = {}
        for name, expected in entries.items():
            p = directory / name
            if not p.is_file() or p.stat().st_size != expected['size']:
                return None
            st = p.stat()
            result[name] = [st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns]
        return result
    before = snapshot()
    if before is None:
        return False
    identity = hashlib.sha256(json.dumps([str(directory), manifest, before], sort_keys=True).encode()).hexdigest()
    receipt = receipt_root / f'{identity}.json'
    try:
        if json.loads(receipt.read_text()).get('verifiedIdentity') == identity:
            return True
    except (OSError, ValueError):
        pass
    total = sum(e['size'] for e in entries.values())
    completed = 0
    for name, expected in entries.items():
        _progress('Verifying pinned speech model files…', stage='modelVerification', completed=completed, total=total)
        if compute_file_hash(directory / name, expected['algorithm']) != expected['digest']:
            return False
        completed += expected['size']
    if snapshot() != before:
        return False
    receipt_root.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=receipt_root, delete=False) as stream:
        json.dump({'verifiedIdentity': identity, 'revision': manifest['revision'], 'files': before}, stream)
        temporary = Path(stream.name)
    try:
        temporary.replace(receipt)
    finally:
        temporary.unlink(missing_ok=True)
    _progress('Pinned speech model verified', stage='modelVerification', completed=total, total=total)
    return True


def _load(model_id: str, model_path: str, private_cache_path: str, quantization_bits: int = 0) -> dict[str, Any]:
    global _model, _model_id, _model_path, _model_bits, _model_native_scenes
    global _model_load_stream, _model_pending_parameters
    load_started = time.monotonic()
    if quantization_bits not in (0, 4):
        raise ValueError('Supported inference precision: full or 4-bit')
    if model_id not in MODEL_IDS:
        raise ValueError(f"Unknown model ID: {model_id}")
    if model_id in DRAMA_MODELS:
        import subprocess
        physical = int(subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.memsize']))
        estimated = DRAMA_MODELS[model_id]['estimatedPeakBytes']
        if estimated > min(100_000_000_000, physical * .85):
            raise MemoryError('This Drama variant needs more memory than this Mac can safely provide. Select a smaller variant.')
    directory = Path(model_path).expanduser().resolve() if model_path else _download_model(model_id, private_cache_path).resolve()
    if not (directory / "config.json").is_file():
        raise FileNotFoundError(f"Model config is missing: {directory / 'config.json'}")
    if _model is not None and _model_id == model_id and _model_path == str(directory) and _model_bits == quantization_bits:
        return {"modelId": model_id, "loaded": True, "nativeScenesQualified": _model_native_scenes, "modelIdentity": _model_identity(directory, model_id, quantization_bits)}

    _unload()
    import mlx.core as mx
    # Reserve headroom for Flutter, Python, codec and allocator overhead.
    mx.set_memory_limit(85_000_000_000)
    mx.set_cache_limit(1_000_000_000)
    from mlx_audio.tts import load

    _progress("Loading speech model weights into memory…", stage="modelLoad")
    build_started = time.monotonic()
    # The provider's supported lazy flag preserves its full construction and
    # post-load codec setup. For qualified Drama, overlap the remaining weight
    # evaluation with the existing CPU checksum/receipt work below. There is
    # one stream/tree per model, no executor or additional queued model job.
    overlap_weights = model_id == 'fish_drama3' and quantization_bits == 0
    if overlap_weights:
        _model_load_stream = mx.new_stream(mx.gpu)
        with mx.stream(_model_load_stream):
            _model = load(str(directory), lazy=True)
        _model_pending_parameters = _model.parameters()
        mx.async_eval(_model_pending_parameters)
    else:
        _model = load(str(directory), lazy=False)
    _timing('modelBuildAndCodec', build_started)
    weights_started = time.monotonic()
    if quantization_bits and model_id not in DRAMA_MODELS:
        _progress('Preparing faster 4-bit inference…', stage='modelQuantization')
        from mlx_audio.lm.convert import quantize_model
        import mlx.core as mx
        predicate = getattr(_model, 'model_quant_predicate', lambda p, m: True)
        _model, _ = quantize_model(_model, {}, 64, quantization_bits, quant_predicate=predicate)
        mx.eval(_model.parameters())
    _model_native_scenes = False
    try:
        if overlap_weights:
            verification_started = time.monotonic()
            _progress('Checking speech model qualification…', stage='modelQualification')
            manifest = json.loads(Path(__file__).with_name('fish_drama_model_checksums.json').read_text())
            _model_native_scenes = _verify_scene_model(directory, manifest,
                Path(private_cache_path).parent / 'model-qualification')
            _timing('modelVerification', verification_started)
            if not _model_native_scenes:
                _progress('Unverified model revision: native scenes and delivery cues are disabled', stage='modelContext')
    finally:
        join_started = time.monotonic()
        if overlap_weights:
            _progress('Waiting for remaining speech model weights…', stage='modelWeights')
        _join_model_weights()
        if overlap_weights:
            _timing('modelWeights', join_started)
    _timing('modelWeightsAndVerification', weights_started)
    _model_bits = quantization_bits
    _model_id = model_id
    _model_path = str(directory)
    _timing('modelLoadTotal', load_started)
    return {"modelId": model_id, "loaded": True, "nativeScenesQualified": _model_native_scenes, "modelIdentity": _model_identity(directory, model_id, quantization_bits)}


def _qwen_language(language: str) -> str:
    names = {
        "en": "English",
        "zh": "Chinese",
        "ja": "Japanese",
        "ko": "Korean",
        "fr": "French",
        "es": "Spanish",
        "de": "German",
        "it": "Italian",
        "pt": "Portuguese",
        "ar": "Arabic",
        "ru": "Russian",
    }
    code = language.lower().replace("_", "-").split("-", 1)[0]
    return names.get(code, "English")


def _model_identity(directory: Path, model_id: str, bits: int) -> str:
    # Snapshot revisions are immutable. Explicit folders are fingerprinted from
    # their config and weight file identities, so they cannot share old caches.
    files = [(f.name, f.stat().st_size, f.stat().st_mtime_ns)
             for f in sorted(directory.glob("*.safetensors"))]
    value = [str(directory), DRAMA_MODELS.get(model_id), bits, files,
             hashlib.sha256((directory / "config.json").read_bytes()).hexdigest()]
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def _complete_audio(results: Any, *, on_piece=None):
    import numpy as np
    pieces = []
    sample_rate = None
    frames = 0
    ended = False
    try:
        for result in results:
            if ended:
                raise ValueError("Audio packet received after the final stream marker")
            rate = int(result.sample_rate)
            audio = np.asarray(result.audio, dtype=np.float32)
            if audio.ndim > 1:
                audio = audio.squeeze()
                if audio.ndim == 0:
                    audio = audio.reshape(1)
            if audio.ndim != 1:
                raise ValueError(f"Expected mono audio; received shape {audio.shape}")
            if sample_rate is not None and rate != sample_rate:
                raise ValueError("Sample rate changed within one generation")
            if rate <= 0:
                raise ValueError("Invalid model sample rate")
            if not audio.size:
                # MLX Audio Drama 3 emits an empty final streaming packet when
                # the last codec frame landed exactly on a streaming boundary.
                # It is an end marker, not missing speech. Keep consuming the
                # iterator so late producer failures cannot become success.
                if (getattr(result, 'is_streaming_chunk', False) is True and
                        getattr(result, 'is_final_chunk', False) is True):
                    ended = True
                    continue
                raise ValueError("Empty audio without a final streaming marker")
            if not np.isfinite(audio).all():
                raise ValueError("Model audio contains non-finite samples")
            sample_rate = rate
            frames += audio.size
            if frames > rate * 600:
                raise ValueError("Generated chunk exceeded ten minute bound")
            if on_piece is not None:
                on_piece(audio, rate)
            pieces.append(audio)
    finally:
        close = getattr(results, 'close', None)
        if close: close()
    if not pieces:
        raise ValueError("The model generated no audio")
    audio = np.concatenate(pieces)
    return audio, sample_rate, len(pieces)


def _reference_inputs(request: dict[str, Any]) -> tuple[str, str]:
    voice = request.get('voice')
    reference = request.get('referenceAudioPath')
    transcript = request.get('referenceText')
    if (not isinstance(voice, str) or not voice.startswith('library_') or
            not isinstance(reference, str) or not Path(reference).is_file() or
            not isinstance(transcript, str) or not transcript.strip()):
        raise ValueError('A selected reference voice, its audio and transcript are required; no default voice fallback is permitted.')
    return reference, transcript


def _drama_reference_inputs(request: dict[str, Any], text: str):
    """Lower stable app voice IDs to native scene slots; MLX owns conditioning.

    Use the same ordered reference set across turns so its existing content cache
    can reuse encodings/prefixes. No tensors or history cache cross this boundary.
    """
    references = request.get('references')
    if references is None:
        reference, transcript = _reference_inputs(request)
        return text, reference, transcript
    if not isinstance(references, list) or not 1 <= len(references) <= 16:
        raise ValueError('Drama requires a bounded reference set of 1 to 16 voices.')
    audios, transcripts, voices = [], [], []
    for slot, item in enumerate(references):
        if not isinstance(item, dict) or item.get('voice') in voices:
            raise ValueError('Drama reference voices must be unique objects.')
        audio, transcript = _reference_inputs(item)
        if '<|speaker:' in transcript:
            raise ValueError('Reference transcripts must not supply speaker slots.')
        audios.append(audio)
        transcripts.append(f'<|speaker:{slot}|> {transcript}')
        voices.append(item['voice'])
    if request.get('voice') not in voices:
        raise ValueError('Selected voice is absent from the Drama reference set.')
    turns = request.get('sceneTurns')
    if turns is not None:
        if not _model_native_scenes:
            raise ValueError('Native scenes require a verified pinned model context.')
        if not isinstance(turns, list) or not 1 <= len(turns) <= 16:
            raise ValueError('Drama scene requires 1 to 16 ordered turns.')
        lines, next_word = [], None
        for turn in turns:
            if not isinstance(turn, dict) or turn.get('voice') not in voices:
                raise ValueError('Scene turn has no reference voice.')
            content = turn.get('text')
            start, end = turn.get('startWord'), turn.get('endWord')
            if (not isinstance(content, str) or not content.strip()
                    or '<|speaker:' in content or not isinstance(start, int)
                    or not isinstance(end, int) or end <= start
                    or (next_word is not None and start != next_word)):
                raise ValueError('Scene text/source spans are invalid.')
            next_word = end
            lines.append(f"<|speaker:{voices.index(turn['voice'])}|> {content}")
        return '\n'.join(lines), audios, transcripts
    slot = voices.index(request['voice'])
    return f'<|speaker:{slot}|> {text}', audios, transcripts


def _drama_results(model: Any, **kwargs):
    # The protocol thread owns this temporary per-instance instrumentation.
    # Always restore it on exhaustion, generator close or producer failure.
    voice = getattr(model, '_voice', None)
    missing = object()
    previous = vars(model).get('_voice', missing)
    if callable(voice):
        def timed_voice(*args, **voice_kwargs):
            started = time.monotonic()
            _progress('Preparing reference voice…', stage='referencePreparing')
            try:
                result = voice(*args, **voice_kwargs)
            except Exception:
                _timing('referencePreparationFailed', started)
                raise
            _timing('referencePrepared', started)
            return result
        model._voice = timed_voice
    try:
        yield from model.generate(**kwargs)
    finally:
        if callable(voice):
            if previous is missing:
                delattr(model, '_voice')
            else:
                model._voice = previous


def _synthesize(request: dict[str, Any]) -> dict[str, Any]:
    synthesis_started = time.monotonic()
    if _model is None or _model_id is None:
        raise RuntimeError("No MLX TTS model is loaded.")
    if request.get("modelId") != _model_id:
        raise RuntimeError("The request model does not match the loaded model.")
    text = request.get("text")
    output_path = request.get("outputPath")
    if not isinstance(text, str) or not text.strip() or len(text) > 65536:
        raise ValueError("Text must contain 1 to 65536 characters.")
    if not isinstance(output_path, str) or not output_path:
        raise ValueError("Output WAV path is required.")

    voice = request.get("voice")
    language = request.get("language", "English")
    if not isinstance(language, str):
        language = "English"

    if _model_id == "qwen3_tts_1_7b":
        if voice not in QWEN_VOICES:
            raise ValueError(f'Unknown Qwen CustomVoice speaker: {voice}')
        results = (
            _model.generate(
                text=text,
                voice=voice,
                lang_code=_qwen_language(language),
                stream=False,
                verbose=False,
            )
        )
    elif _model_id == "qwen3_tts_base_1_7b":
        reference, transcript = _reference_inputs(request)
        results = (_model.generate(
            text=text, ref_audio=reference, ref_text=transcript,
            lang_code=_qwen_language(language), stream=False, verbose=False,
        ))
    elif _model_id == "voxtral_4b":
        if voice not in VOXTRAL_VOICES:
            raise ValueError(f'Unknown Voxtral preset: {voice}')
        results = (
            _model.generate(text=text, voice=voice, stream=False, verbose=False)
        )
    elif _model_id in DRAMA_MODELS:
        text, reference, transcript = _drama_reference_inputs(request, text)
        results = _drama_results(_model, text=text, ref_audio=reference, ref_text=transcript,
                                stream=True, streaming_interval=0.32,
                                first_chunk_frames=4)
    else:
        reference, transcript = _reference_inputs(request)
        results = (
            _model.generate(text=text, ref_audio=reference, ref_text=transcript,
                            language=language, max_tokens=512, stream=False)
        )

    destination = Path(output_path).expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = None
    raw = None
    wav = None
    packet_count = 0
    frame_count = 0
    enable_packets = request.get('enableAudioPackets') is True
    if enable_packets:
        for key in ('sessionId', 'generationId', 'chunkId', 'synthesisIdentity',
                    'bindingFingerprint'):
            if not isinstance(request.get(key), str) or not request[key]:
                raise ValueError(f'Missing audio packet identity: {key}')
        if type(request.get('bindingRevision')) is not int:
            raise ValueError('Missing audio packet binding revision')

    def preserve_piece(audio, rate):
        nonlocal partial, raw, wav, packet_count, frame_count
        import numpy as np
        if wav is None:
            raw = tempfile.NamedTemporaryFile(
                mode='xb', prefix='rendered-', suffix='.partial.wav',
                dir=destination.parent, delete=False,
            )
            partial = Path(raw.name)
            wav = wave.open(raw, 'wb')
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(rate)
        # Match mlx_audio.audio_io.write's PCM16 encoding. Each write updates
        # the WAV header; flush it so child failure/cancellation retains a
        # readable prefix, without claiming the passage is complete.
        pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype('<i2')
        pcm_bytes = pcm.tobytes()
        if enable_packets and (packet_count >= 2048 or rate > 192000 or
                               frame_count + len(pcm) > rate * 600 or
                               frame_count * 2 + len(pcm_bytes) > 192000 * 600 * 2):
            raise ValueError('Audio packet spool exceeded scene bounds')
        wav.writeframes(pcm_bytes)
        raw.flush()
        if enable_packets:
            # Exclusive create, close before publication; never mutate a packet
            # after the protocol consumer may have admitted it to playback.
            packet_path = destination.parent / f'packet-{packet_count:04d}.wav'
            with packet_path.open('xb') as packet_file:
                with wave.open(packet_file, 'wb') as packet_wav:
                    packet_wav.setnchannels(1)
                    packet_wav.setsampwidth(2)
                    packet_wav.setframerate(rate)
                    packet_wav.writeframes(pcm_bytes)
            _reply(_active_request_id, **{
                'type': 'audioPacket', 'audioPath': str(packet_path),
                'packetIndex': packet_count, 'frameStart': frame_count,
                'frameCount': len(pcm), 'sampleRate': rate,
                'channels': 1, 'bitsPerSample': 16,
                **{key: request[key] for key in (
                    'sessionId', 'generationId', 'chunkId',
                    'synthesisIdentity', 'bindingFingerprint', 'bindingRevision')},
            })
            packet_count += 1
        frame_count += len(pcm)
        if wav.getnframes() == len(pcm):
            _timing('synthesisFirstPacket', synthesis_started)
            _progress('First native audio packet rendered', stage='firstAudioPacket',
                      completed=len(pcm), unit='frames')

    try:
        try:
            _, sample_rate, piece_count = _complete_audio(
                results, on_piece=preserve_piece)
        finally:
            if wav is not None:
                wav.close()
            if raw is not None:
                raw.close()
        # Atomic, no-clobber publication: an existing render is never replaced.
        os.link(partial, destination)
    except Exception as error:
        if partial is not None and partial.is_file():
            raise RuntimeError(
                f'{error}. Rendered audio retained at {partial} '
                '(incomplete passage; not used as a completed cache entry).'
            ) from error
        raise
    # This removes only a duplicate link after the same bytes were published.
    partial.unlink()
    return {
        "audioPath": str(destination),
        "nativeSampleRate": sample_rate,
        "generatedPieces": piece_count,
        "streamedPacketCount": packet_count,
        "streamedFrameCount": frame_count if enable_packets else 0,
        "sampleRate": sample_rate,
        "synthesisIdentity": request.get("synthesisIdentity"),
        "sessionId": request.get("sessionId"),
        "generationId": request.get("generationId"),
        "chunkId": request.get("chunkId"),
        "bindingFingerprint": request.get("bindingFingerprint"),
        "bindingRevision": request.get("bindingRevision"),
    }


def main() -> int:
    global _active_request_id
    for raw_line in sys.stdin:
        request: Any = {}
        try:
            request = json.loads(raw_line)
            if not isinstance(request, dict):
                raise ValueError("Request must be a JSON object.")
            request_id = str(request.get("id", ""))
            _active_request_id = request_id
            command = request.get("command")
            with contextlib.redirect_stdout(sys.stderr):
                if command == "load":
                    response = _load(
                        str(request.get("modelId", "")),
                        str(request.get("modelPath", "")),
                        str(request.get("privateCachePath", "")),
                        int(request.get('quantizationBits', 0)),
                    )
                elif command == "synthesize":
                    response = _synthesize(request)
                elif command == "shutdown":
                    _unload()
                    _reply(request_id, ok=True, shutdown=True)
                    return 0
                else:
                    raise ValueError(f"Unknown command: {command}")
            _reply(request_id, ok=True, **response)
        except Exception as error:  # Keep the protocol alive after a failed request.
            traceback.print_exc(file=sys.stderr)
            request_id = str(request.get("id", "")) if isinstance(request, dict) else ""
            _reply(request_id, ok=False, error=str(error))
        finally:
            _active_request_id = ""
    _unload()
    return 0


if __name__ == "__main__":
    stop_memory = threading.Event()
    memory_thread = threading.Thread(target=_report_memory, args=(stop_memory,),
                                     name="speech-memory", daemon=True)
    memory_thread.start()
    try:
        raise SystemExit(main())
    finally:
        stop_memory.set()
        memory_thread.join(timeout=1)
