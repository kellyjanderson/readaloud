"""Persistent JSON-lines worker for local MLX TTS inference.

The Flutter/Dart runtime owns requests, cache identity, playback and export.
This child owns one loaded model and one in-flight inference at a time.
"""

from __future__ import annotations

import contextlib
import gc
import json
import os
import sys
import time
import traceback
from pathlib import Path
from typing import Any


MODEL_IDS = {"qwen3_tts_1_7b", "qwen3_tts_base_1_7b", "voxtral_4b", "moss_tts_8b"}
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
_protocol_stdout = sys.stdout
_active_request_id = ""


def _reply(request_id: str, **payload: Any) -> None:
    _protocol_stdout.write(json.dumps({"id": request_id, **payload}, separators=(",", ":")) + "\n")
    _protocol_stdout.flush()


def _unload() -> None:
    global _model, _model_id, _model_path
    _model = None
    _model_id = None
    _model_path = None
    gc.collect()
    try:
        import mlx.core as mx

        mx.clear_cache()
    except Exception:
        pass


def _progress(message: str, *, stage: str, completed: int | None = None,
              total: int | None = None, unit: str = "bytes") -> None:
    if not _active_request_id:
        return
    _protocol_stdout.write(json.dumps({
        "id": _active_request_id,
        "type": "progress",
        "stage": stage,
        "message": message,
        "completed": completed,
        "total": total,
        "unit": unit,
    }, separators=(",", ":")) + "\n")
    _protocol_stdout.flush()


def _download_progress_class():
    from tqdm import tqdm

    class ProgressTqdm(tqdm):
        _active: dict[int, tuple[int, int | None]] = {}
        _finished_bytes = 0
        _finished_total = 0
        _last_report = 0.0

        def _emit_progress(self):
            if not hasattr(self, 'desc') or not hasattr(self, 'n'):
                return
            if self.desc and "download" not in self.desc.lower():
                return
            key = id(self)
            self.__class__._active[key] = (
                int(self.n), int(self.total) if self.total is not None else None
            )
            now = time.monotonic()
            if now - self._last_report >= 0.4 or (self.total and self.n >= self.total):
                self._last_report = now
                completed = self.__class__._finished_bytes + sum(
                    item[0] for item in self.__class__._active.values()
                )
                known_totals = [item[1] for item in self.__class__._active.values()]
                total = self.__class__._finished_total + sum(
                    item for item in known_totals if item is not None
                )
                if any(item is None for item in known_totals):
                    total = None
                _progress(
                    "Downloading speech model files…",
                    stage="modelDownload",
                    completed=completed,
                    total=total,
                )

        def update(self, n=1):
            result = super().update(n)
            self._emit_progress()
            return result

        def refresh(self, *args, **kwargs):
            result = super().refresh(*args, **kwargs)
            self._emit_progress()
            return result

        def close(self):
            key = id(self)
            current = self.__class__._active.pop(key, None)
            if current is not None:
                self.__class__._finished_bytes += current[0]
                if current[1] is not None:
                    self.__class__._finished_total += current[1]
            super().close()

    return ProgressTqdm


def _download_model(model_id: str, private_cache_path: str) -> Path:
    from huggingface_hub import snapshot_download
    from huggingface_hub import constants as hf_constants

    repo_id = MODEL_REPOSITORIES[model_id]
    # Prefer the normal Hugging Face cache. In a sandboxed release this may not
    # be readable; then keep a reusable copy in this app's support directory.
    configured_cache = (
        os.environ.get("HF_HUB_CACHE")
        or os.environ.get("HUGGINGFACE_HUB_CACHE")
        or str(hf_constants.HF_HUB_CACHE)
    )
    private_cache = Path(private_cache_path).expanduser()
    candidates = [Path(configured_cache).expanduser()]
    if private_cache not in candidates:
        candidates.append(private_cache)

    try:
        cached = snapshot_download(
            repo_id=repo_id,
            cache_dir=str(candidates[0]),
            local_files_only=True,
        )
        if (Path(cached) / "config.json").is_file():
            _configure_hf_cache(candidates[0], hf_constants)
            return Path(cached)
    except Exception:
        pass

    last_error = None
    for index, cache_dir in enumerate(candidates):
        try:
            cache_dir.mkdir(parents=True, exist_ok=True)
            _progress(
                f"Downloading {model_id.replace('_', ' ')} model files…",
                stage="modelDownload",
            )
            snapshot = snapshot_download(
                repo_id=repo_id,
                cache_dir=str(cache_dir),
                tqdm_class=_download_progress_class(),
            )
            resolved = Path(snapshot)
            if not (resolved / "config.json").is_file():
                raise FileNotFoundError(f"Downloaded model has no config.json: {resolved}")
            _configure_hf_cache(cache_dir, hf_constants)
            return resolved
        except Exception as error:
            last_error = error
            # Fall back only if the global cache was rejected (for example by
            # App Sandbox file access); download/network errors are retried in
            # the private cache as a straightforward recovery path.
            if index == 0 and len(candidates) > 1:
                continue
            break
    raise RuntimeError(
        f"Could not download {repo_id} to the shared Hugging Face cache or "
        f"the app cache ({private_cache}): {last_error}"
    )


def _configure_hf_cache(cache_dir: Path, hf_constants: Any) -> None:
    cache = str(cache_dir.expanduser())
    os.environ["HF_HUB_CACHE"] = cache
    os.environ["HUGGINGFACE_HUB_CACHE"] = cache
    hf_constants.HF_HUB_CACHE = cache


def _load(model_id: str, model_path: str, private_cache_path: str, quantization_bits: int = 0) -> dict[str, Any]:
    global _model, _model_id, _model_path, _model_bits
    if quantization_bits not in (0, 4):
        raise ValueError('Supported inference precision: full or 4-bit')
    if model_id not in MODEL_IDS:
        raise ValueError(f"Unknown model ID: {model_id}")
    directory = Path(model_path).expanduser().resolve() if model_path else _download_model(model_id, private_cache_path).resolve()
    if not (directory / "config.json").is_file():
        raise FileNotFoundError(f"Model config is missing: {directory / 'config.json'}")
    if _model is not None and _model_id == model_id and _model_path == str(directory) and _model_bits == quantization_bits:
        return {"modelId": model_id, "loaded": True}

    _unload()
    from mlx_audio.tts import load

    _progress("Loading speech model weights into memory…", stage="modelLoad")
    _model = load(str(directory), lazy=False)
    if quantization_bits:
        _progress('Preparing faster 4-bit inference…', stage='modelQuantization')
        from mlx_audio.lm.convert import quantize_model
        import mlx.core as mx
        predicate = getattr(_model, 'model_quant_predicate', lambda p, m: True)
        _model, _ = quantize_model(_model, {}, 64, quantization_bits, quant_predicate=predicate)
        mx.eval(_model.parameters())
    _model_bits = quantization_bits
    _model_id = model_id
    _model_path = str(directory)
    return {"modelId": model_id, "loaded": True}


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


def _first_result(results: Any) -> Any:
    return next(iter(results))


def _reference_inputs(request: dict[str, Any]) -> tuple[str, str]:
    voice = request.get('voice')
    reference = request.get('referenceAudioPath')
    transcript = request.get('referenceText')
    if (not isinstance(voice, str) or not voice.startswith('library_') or
            not isinstance(reference, str) or not Path(reference).is_file() or
            not isinstance(transcript, str) or not transcript.strip()):
        raise ValueError('A selected reference voice, its audio and transcript are required; no default voice fallback is permitted.')
    return reference, transcript


def _synthesize(request: dict[str, Any]) -> dict[str, Any]:
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
        result = _first_result(
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
        result = _first_result(_model.generate(
            text=text, ref_audio=reference, ref_text=transcript,
            lang_code=_qwen_language(language), stream=False, verbose=False,
        ))
    elif _model_id == "voxtral_4b":
        if voice not in VOXTRAL_VOICES:
            raise ValueError(f'Unknown Voxtral preset: {voice}')
        result = _first_result(
            _model.generate(text=text, voice=voice, stream=False, verbose=False)
        )
    else:
        reference, transcript = _reference_inputs(request)
        result = _first_result(
            _model.generate(text=text, ref_audio=reference, ref_text=transcript,
                            language=language, max_tokens=512, stream=False)
        )

    sample_rate = int(result.sample_rate)
    if sample_rate != 24000:
        raise ValueError(f"Expected 24000 Hz model output; received {sample_rate} Hz.")

    import mlx.core as mx
    from mlx_audio.audio_io import write as write_audio

    audio = mx.array(result.audio).squeeze()
    if audio.ndim != 1 or audio.size == 0:
        raise ValueError(f"Expected non-empty mono audio; received shape {audio.shape}.")
    destination = Path(output_path).expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_audio(str(destination), audio, sample_rate)
    if not destination.is_file() or destination.stat().st_size <= 44:
        raise RuntimeError("MLX Audio did not write a complete WAV file.")
    return {
        "audioPath": str(destination),
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
    raise SystemExit(main())
