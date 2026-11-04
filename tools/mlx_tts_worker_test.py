"""Run with the installed MLX runtime Python. No model weights are needed."""
import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import mlx.core as mx

spec = importlib.util.spec_from_file_location(
    "mlx_tts_worker", Path(__file__).parents[1] / "assets/mlx_tts_worker.py"
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class GeneratorAdapterTest(unittest.TestCase):
    def test_child_can_measure_its_own_physical_footprint(self):
        self.assertGreater(worker._physical_footprint(), 0)

    def test_precision_change_reloads_instead_of_reusing_wrong_weights(self):
        worker._unload()
        model = SimpleNamespace(parameters=lambda: {})
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'config.json').write_text('{}')
            with patch('mlx_audio.tts.load', return_value=model) as load, patch('mlx_audio.lm.convert.quantize_model', return_value=(model, {})) as quantize:
                for bits in (0, 0, 4, 4, 0):
                    worker._load('voxtral_4b', tmp, tmp, bits)
                self.assertEqual(load.call_count, 3)
                self.assertEqual(quantize.call_count, 1)
        worker._unload()

    def test_all_generator_backends_write_audio(self):
        class Model:
            kwargs = None
            def generate(self, **kwargs):
                self.kwargs = kwargs
                yield SimpleNamespace(
                    sample_rate=24000,
                    audio=0.2 * mx.sin(mx.arange(24000) * 0.1),
                )

        for engine in sorted(worker.MODEL_IDS):
            with self.subTest(engine=engine), tempfile.TemporaryDirectory() as tmp:
                worker._model = Model()
                worker._model_id = engine
                path = str(Path(tmp) / "speech.wav")
                reference = Path(tmp) / 'reference.wav'
                reference.write_bytes(b'only the adapter routing is tested here')
                result = worker._synthesize({
                    "modelId": engine, "text": "A generator must be consumed.",
                    "outputPath": path, "synthesisIdentity": "regression",
                    'voice': {'qwen3_tts_1_7b': 'Ryan', 'voxtral_4b': 'casual_male'}.get(engine, 'library_ava'),
                    'referenceAudioPath': str(reference),
                    'referenceText': 'Reference voice speech.',
                })
                self.assertEqual(result["sampleRate"], 24000)
                self.assertEqual(result["synthesisIdentity"], "regression")
                self.assertGreater(Path(path).stat().st_size, 1000)
                if engine in ('moss_tts_8b', 'qwen3_tts_base_1_7b'):
                    self.assertEqual(worker._model.kwargs['ref_audio'], str(reference))
                    self.assertEqual(worker._model.kwargs['ref_text'], 'Reference voice speech.')
                    self.assertNotIn('voice', worker._model.kwargs)

    def test_all_pieces_keep_native_rate_and_exact_samples(self):
        import numpy as np

        source = np.sin(np.arange(8820) * .08).astype(np.float32) * .2
        pieces = (SimpleNamespace(sample_rate=44100, audio=mx.array(a))
                  for a in (source[:3500], source[3500:]))
        audio, rate, count = worker._complete_audio(pieces)
        self.assertEqual((rate, count, audio.size), (44100, 2, 8820))
        np.testing.assert_array_equal(audio, source)

    def test_malformed_late_piece_never_publishes_partial_success(self):
        pieces = iter([SimpleNamespace(sample_rate=24000, audio=mx.ones(240)),
                       SimpleNamespace(sample_rate=44100, audio=mx.ones(240))])
        with self.assertRaises(ValueError): worker._complete_audio(pieces)
        with self.assertRaises(ValueError): worker._complete_audio(iter([]))

    def test_unknown_presets_and_missing_reference_are_rejected(self):
        for engine in sorted(worker.MODEL_IDS):
            worker._model = SimpleNamespace()
            worker._model_id = engine
            with self.subTest(engine=engine), self.assertRaises(ValueError):
                worker._synthesize({'modelId': engine, 'voice': 'not-a-voice',
                                    'text': 'Do not substitute a default speaker.',
                                    'outputPath': '/tmp/unused-rejection.wav'})


if __name__ == "__main__":
    unittest.main()
