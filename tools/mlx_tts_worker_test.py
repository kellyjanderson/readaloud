"""Run with the installed MLX runtime Python. No model weights are needed."""
import importlib.util
from pathlib import Path
import tempfile
import io
import os
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


class ModelDownloadReuseTest(unittest.TestCase):
    def test_completed_pinned_snapshot_reuses_files_without_network(self):
        import huggingface_hub
        spec = worker.DRAMA_MODELS['fish_drama3']
        with tempfile.TemporaryDirectory() as tmp:
            snapshot = Path(tmp) / ('models--' + spec['repo'].replace('/', '--')) / 'snapshots' / spec['revision']
            snapshot.mkdir(parents=True)
            for name in spec['requiredFiles']:
                (snapshot / name).write_bytes(b'cached fixture')
            real_download = huggingface_hub.snapshot_download
            def offline_only(**kwargs):
                self.assertTrue(kwargs.get('local_files_only'), 'Warm startup attempted network/download')
                return real_download(**kwargs)
            with patch('huggingface_hub.snapshot_download', side_effect=offline_only) as download, patch.object(worker, '_configure_hf_cache'), patch.object(worker, '_progress') as progress:
                for _ in range(3):
                    self.assertEqual(worker._download_model('fish_drama3', tmp).resolve(), snapshot.resolve())
                self.assertEqual(download.call_count, 3)
                self.assertTrue(all(c.kwargs['stage'] == 'modelCached' for c in progress.call_args_list))

    def test_checks_secondary_cache_before_any_network(self):
        with tempfile.TemporaryDirectory() as tmp:
            shared = Path(tmp) / 'shared'
            shared.mkdir()
            (shared / 'config.json').write_text('{}')
            (shared / 'model.safetensors').write_bytes(b'weight fixture')
            def cached(**kwargs):
                self.assertTrue(kwargs.get('local_files_only'))
                if kwargs['cache_dir'] == str(shared): return str(shared)
                raise FileNotFoundError()
            with patch.dict(os.environ, {'HF_HUB_CACHE': str(shared)}), patch('huggingface_hub.snapshot_download', side_effect=cached), patch.object(worker, '_configure_hf_cache'):
                self.assertEqual(worker._download_model('voxtral_4b', str(Path(tmp) / 'private')), shared)

    def test_network_failure_never_changes_download_destination(self):
        calls = []
        def download(**kwargs):
            calls.append(kwargs)
            if kwargs.get('local_files_only'): raise FileNotFoundError()
            if kwargs.get('dry_run'):
                return [SimpleNamespace(file_size=100, will_download=True, commit_hash='a' * 40)]
            raise ConnectionError('interrupted')
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HF_HUB_CACHE': tmp + '/shared'}), patch('huggingface_hub.snapshot_download', side_effect=download):
            for _ in range(2):
                with self.assertRaises(ConnectionError):
                    worker._download_model('fish_drama3', tmp + '/private')
            writes = [c for c in calls if not c.get('local_files_only') and not c.get('dry_run')]
            self.assertEqual(len(writes), 2)
            self.assertTrue(all(c['cache_dir'] == tmp + '/private' for c in writes))
            self.assertTrue(all(not c.get('force_download', False) for c in writes))

    def test_resume_progress_includes_cached_and_reconstructed_bytes(self):
        with patch.object(worker, '_progress') as report:
            cls = worker._download_progress_class(100, 30)
            with cls(desc='Reconstructing (incomplete total...)', initial=20, total=70, file=io.StringIO()) as bar:
                bar._last_report = 0
                bar._emit_progress()
            self.assertEqual(report.call_args.kwargs['completed'], 50)
            self.assertEqual(report.call_args.kwargs['total'], 100)


if __name__ == "__main__":
    unittest.main()
