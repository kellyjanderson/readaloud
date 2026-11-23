"""Build fictional, reproducible reference voices; run with the managed MLX Python.

The generated WAVs and manifest are application assets, not private recordings.
VoiceDesign creates each reference; Base/MOSS reproduce its speaker identity.
"""
import argparse
import hashlib
import json
from pathlib import Path

DESIGN_MODEL = 'mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16'
DESIGN_REVISION = '7d3824abff87e49756bb0f83fb5411de75d160c4'
REFERENCE_TEXT = ('The garden gate stood open in the morning light. '
                  'I put the blue notebook on the table, then turned to greet '
                  'my friend. There was still time to tell the whole story.')
VOICES = [
    ('ava', 'Ava', 'female', 'en-US', 'A woman in her thirties with a clear medium-high voice, bright resonance and a general American accent.'),
    ('ben', 'Ben', 'male', 'en-US', 'A man in his forties with a low rounded baritone, warm resonance and a general American accent.'),
    ('clara', 'Clara', 'female', 'en-GB', 'A British woman in her fifties with a rich low contralto, precise consonants and a southern English accent.'),
    ('david', 'David', 'male', 'en-GB', 'A British man in his thirties with a light midrange tenor, crisp articulation and a modern London accent.'),
    ('elin', 'Elin', 'female', 'en-GB', 'A Welsh woman in her thirties with a lilting musical midrange voice and a light Welsh English accent.'),
    ('finn', 'Finn', 'male', 'en-IE', 'An Irish man in his twenties with a bright youthful tenor and a natural Dublin accent.'),
    ('grace', 'Grace', 'female', 'en-US', 'An American woman in her sixties with a gentle husky low voice, slightly grainy timbre and a New England accent.'),
    ('hugo', 'Hugo', 'male', 'en-GB', 'An older English man in his sixties with a resonant deep bass, dry textured timbre and careful Oxford articulation.'),
    ('iris', 'Iris', 'female', 'en-AU', 'An Australian woman in her twenties with a bright forward high voice and a light Sydney accent.'),
    ('jack', 'Jack', 'male', 'en-AU', 'An Australian man in his fifties with a gravelly low baritone, relaxed vowels and a broad Australian accent.'),
    ('keira', 'Keira', 'female', 'en-IE', 'An Irish woman in her forties with a soft rich alto, clear rounded vowels and a Cork English accent.'),
    ('leon', 'Leon', 'male', 'en-US', 'An American man in his twenties with a light high tenor, smooth clean timbre and a west coast accent.'),
    ('maya', 'Maya', 'female', 'en-IN', 'An Indian woman in her thirties with a smooth medium voice, clear articulation and an educated Indian English accent.'),
    ('noah', 'Noah', 'male', 'en-US', 'An American man in his seventies with a low breathy weathered voice and an unhurried midwestern accent.'),
    ('olive', 'Olive', 'female', 'en-GB', 'A Scottish woman in her fifties with a rounded low alto, rich chest resonance and a mild Edinburgh accent.'),
    ('peter', 'Peter', 'male', 'en-GB', 'A Scottish man in his forties with a firm medium baritone, lightly rough timbre and a natural Glasgow English accent.'),
    ('quinn', 'Quinn', 'female', 'en-US', 'An American woman in her twenties with a low androgynous voice, dry close timbre and a neutral American accent.'),
    ('rajan', 'Rajan', 'male', 'en-IN', 'An Indian man in his fifties with a deep sonorous baritone and a clear educated Indian English accent.'),
    ('sarah', 'Sarah', 'female', 'en-US', 'An American woman in her forties with a clear high soprano, light airy timbre and a gentle southern US accent.'),
    ('theo', 'Theo', 'male', 'en-GB', 'An English man in his twenties with a reedy high tenor, light nasal resonance and a northern English accent.'),
    ('una', 'Una', 'female', 'en-NZ', 'A New Zealand woman in her forties with a clear middle alto and a natural New Zealand English accent.'),
    ('victor', 'Victor', 'male', 'en-US', 'An American man in his forties with a dark resonant bass, a slight rasp and a measured east coast accent.'),
    ('willow', 'Willow', 'female', 'en-US', 'An American woman in her thirties with a soft breathy middle voice, delicate sibilants and a Pacific Northwest accent.'),
    ('xavier', 'Xavier', 'male', 'en-ZA', 'A South African man in his thirties with a rounded midrange baritone and a natural South African English accent.'),
    ('yasmin', 'Yasmin', 'female', 'en-ZA', 'A South African woman in her fifties with a firm clear low voice and a mild South African English accent.'),
    ('zach', 'Zach', 'male', 'en-CA', 'A Canadian man in his twenties with a bright forward tenor, slightly nasal timbre and a natural Canadian English accent.'),
    ('audrey', 'Audrey', 'female', 'en-CA', 'A Canadian woman in her sixties with a polished middle alto, smooth full resonance and clear Canadian English vowels.'),
    ('bruno', 'Bruno', 'male', 'en-US', 'An American man in his fifties with a rough gravelly medium voice, compact chest resonance and a rural midwestern accent.'),
    ('celia', 'Celia', 'female', 'en-GB', 'An English woman in her twenties with a bright bell-like soprano, quick clear articulation and a modern southeast English accent.'),
    ('duncan', 'Duncan', 'male', 'en-NZ', 'A New Zealand man in his sixties with a soft airy low baritone and a natural New Zealand English accent.'),
]


def complete_voice_design(results):
    """Collect the complete authoring generator before publishing any reference.

    Keep this offline authoring policy separate from production packet spooling.
    Late generator failures and changing formats must never publish a prefix.
    """
    import numpy as np
    pieces, sample_rate, frames = [], None, 0
    ended = False
    try:
        for result in results:
            if ended:
                raise ValueError('VoiceDesign output after final marker')
            rate = int(result.sample_rate)
            audio = np.asarray(result.audio, dtype=np.float32).squeeze()
            if audio.ndim == 0:
                audio = audio.reshape(1)
            if audio.ndim != 1 or rate <= 0:
                raise ValueError('VoiceDesign requires mono audio and a valid sample rate')
            if sample_rate is not None and rate != sample_rate:
                raise ValueError('VoiceDesign sample rate changed')
            if not audio.size:
                if (getattr(result, 'is_streaming_chunk', False) is True
                        and getattr(result, 'is_final_chunk', False) is True):
                    ended = True
                    continue
                raise ValueError('Empty VoiceDesign audio')
            if not np.isfinite(audio).all():
                raise ValueError('Non-finite VoiceDesign audio')
            sample_rate = rate
            frames += audio.size
            if frames > rate * 30:
                raise ValueError('VoiceDesign reference exceeded thirty seconds')
            pieces.append(audio.copy())
    finally:
        close = getattr(results, 'close', None)
        if close:
            close()
    if not pieces:
        raise ValueError('VoiceDesign generated no audio')
    return np.concatenate(pieces), sample_rate


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='assets/voice_library')
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    from huggingface_hub import snapshot_download
    import mlx.core as mx
    from mlx_audio.tts import load
    from mlx_audio.audio_io import write
    import soundfile as sf
    checkpoint = snapshot_download(DESIGN_MODEL, revision=DESIGN_REVISION)
    model = load(checkpoint)
    entries = []
    for index, (key, label, gender, locale, description) in enumerate(VOICES):
        target = output / f'{key}.wav'
        seed = 73000 + index
        if not target.exists():
            mx.random.seed(seed)
            instruct = (description + ' Speak naturally in English, in a neutral '
                        'storytelling manner. One speaker, clean close microphone, no music.')
            audio, sample_rate = complete_voice_design(model.generate_voice_design(
                text=REFERENCE_TEXT, language='English', instruct=instruct,
                max_tokens=512, stream=False, verbose=False,
            ))
            audio = mx.array(audio)
            mx.eval(audio)
            temporary = output / f'{key}.partial.wav'
            write(str(temporary), audio, sample_rate)
            temporary.replace(target)
        audio, rate = sf.read(target)
        duration = len(audio) / rate
        if not 3 <= duration <= 30 or abs(audio).max() < 0.01:
            raise ValueError(f'Unusable reference {key}: duration={duration}')
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        entries.append(dict(id=f'library_{key}', label=label, gender=gender,
                            locale=locale, description=description,
                            asset=f'assets/voice_library/{key}.wav',
                            sha256=digest, referenceText=REFERENCE_TEXT,
                            durationSeconds=duration, seed=seed))
        print(f'{index + 1}/{len(VOICES)} {label}: {duration:.2f}s {digest[:12]}', flush=True)
        mx.clear_cache()
    if len({e['sha256'] for e in entries}) != len(VOICES):
        raise ValueError('Voice references must have distinct audio content')
    manifest = dict(schema=1, version='synthetic-reference-v1',
                    sourceModel=DESIGN_MODEL, sourceRevision=DESIGN_REVISION,
                    provenance='Fictional voices generated from descriptions; no personal recordings.',
                    voices=entries)
    (output / 'library.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
