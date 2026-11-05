"""Run with the installed MLX runtime Python. No model weights are needed."""
import importlib.util
from pathlib import Path
import tempfile
import io
import os
import subprocess
import sys
from types import SimpleNamespace
from types import MethodType
import unittest
from unittest.mock import patch

import mlx.core as mx

spec = importlib.util.spec_from_file_location(
    "mlx_tts_worker", Path(__file__).parents[1] / "assets/mlx_tts_worker.py"
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class GeneratorAdapterTest(unittest.TestCase):
    def test_installed_drama_generator_exact_boundary_writes_complete_wav(self):
        """Use the installed producer's real framing, with bounded codec input.

        The waveform proves sample preservation, not speech/listening quality.
        No model weights are needed to exercise the upstream boundary bug.
        """
        import numpy as np
        from mlx_audio.tts.models.fish_drama3.drama3 import Model
        from mlx_audio.audio_io import read

        samples = (np.sin(np.arange(8192) * .08) * .2).astype(np.float32)
        model = SimpleNamespace(
            sample_rate=44100,
            codec=SimpleNamespace(
                frame_length=2048,
                reset_streaming_state=lambda: None,
                streaming_step=lambda frames: mx.array(samples)[None, None, :],
            ),
            _voice=lambda *args: SimpleNamespace(references=[]),
            build_frames=lambda *args: (None, None),
            _frames=lambda *args: iter([mx.zeros((10,), dtype=mx.int32)] * 4),
        )
        model._result = MethodType(Model._result, model)
        model.generate = MethodType(Model.generate, model)
        produced = list(model.generate('Complete this passage.', stream=True,
                                       first_chunk_frames=4))
        self.assertEqual([r.audio.size for r in produced], [8192, 0])
        self.assertTrue(produced[-1].is_streaming_chunk)
        self.assertTrue(produced[-1].is_final_chunk)
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(worker, '_model', model), \
                patch.object(worker, '_model_id', 'fish_drama3'):
            reference = Path(tmp) / 'reference.wav'
            reference.write_bytes(b'voice encoder is stubbed, framing is real')
            result = worker._synthesize({
                'modelId': 'fish_drama3', 'text': 'Complete this passage.',
                'voice': 'library_ava', 'referenceAudioPath': str(reference),
                'referenceText': 'A reference.',
                'outputPath': str(Path(tmp) / 'speech.wav'),
            })
            actual, rate = read(result['audioPath'])
            self.assertEqual((rate, result['generatedPieces']), (44100, 1))
            self.assertEqual(actual.shape, samples.shape)
            expected = (samples * 32767).astype(np.int16).astype(np.float64) / 32768
            np.testing.assert_array_equal(actual, expected)
            self.assertEqual(list(Path(tmp).glob('*.partial.wav')), [])

    def test_late_malformed_audio_preserves_prefix_and_prior_render_on_retry(self):
        import numpy as np
        from mlx_audio.audio_io import read
        samples = (np.sin(np.arange(8820) * .08) * .2).astype(np.float32)
        class Model:
            def generate(self, **kwargs):
                yield SimpleNamespace(sample_rate=44100, audio=mx.array(samples[:3500]))
                yield SimpleNamespace(sample_rate=44100, audio=mx.array(samples[3500:]))
                yield SimpleNamespace(sample_rate=44100, audio=mx.array([float('nan'), .1]))
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(worker, '_model', Model()), \
                patch.object(worker, '_model_id', 'qwen3_tts_1_7b'):
            destination = Path(tmp) / 'prior.wav'
            original = b'pre-existing render must not be modified on failure'
            destination.write_bytes(original)
            for _ in range(2):
                with self.assertRaisesRegex(RuntimeError, 'Rendered audio retained at'):
                    worker._synthesize({
                        'modelId': 'qwen3_tts_1_7b', 'voice': 'Ryan',
                        'text': 'Retain the valid beginning.', 'outputPath': str(destination),
                    })
            self.assertEqual(destination.read_bytes(), original)
            preserved = list(Path(tmp).glob('*.partial.wav'))
            self.assertEqual(len(preserved), 2)
            expected = (samples * 32767).astype(np.int16).astype(np.float64) / 32768
            for path in preserved:
                actual, rate = read(str(path))
                self.assertEqual(rate, 44100)
                np.testing.assert_array_equal(actual, expected)

    def test_empty_terminal_packet_preserves_every_preceding_sample(self):
        import numpy as np
        samples = np.sin(np.arange(8820) * .08).astype(np.float32) * .2
        closed = []
        def generate():
            try:
                for chunk in (samples[:3500], samples[3500:]):
                    yield SimpleNamespace(sample_rate=44100, audio=mx.array(chunk))
                yield SimpleNamespace(sample_rate=44100, audio=mx.zeros((0,)),
                                      is_streaming_chunk=True, is_final_chunk=True)
            finally:
                closed.append(True)
        actual, rate, count = worker._complete_audio(generate())
        self.assertEqual((rate, count), (44100, 2))
        np.testing.assert_array_equal(actual, samples)
        self.assertEqual(closed, [True])

    def test_invalid_empty_and_nonfinite_packets_still_fail_and_close(self):
        def packet(audio, **flags):
            return SimpleNamespace(sample_rate=44100, audio=mx.array(audio), **flags)
        valid = packet([.1, -.1])
        terminal = packet([], is_streaming_chunk=True, is_final_chunk=True)
        invalid_sequences = [
            [terminal],
            [valid, packet([])],
            [valid, packet([], is_final_chunk=True)],
            [valid, packet([], is_streaming_chunk=True)],
            [valid, packet([float('nan')])],
            [valid, packet([float('inf')])],
            [valid, packet([[.1, .2], [.3, .4]])],
            [valid, terminal, valid],
            [valid, terminal, terminal],
            [valid, SimpleNamespace(sample_rate=24000, audio=mx.zeros((0,)),
                                    is_streaming_chunk=True, is_final_chunk=True)],
        ]
        for sequence in invalid_sequences:
            closed = []
            def generate():
                try:
                    yield from sequence
                finally:
                    closed.append(True)
            with self.subTest(sequence=sequence), self.assertRaises(ValueError):
                worker._complete_audio(generate())
            self.assertEqual(closed, [True])

    def test_exception_after_terminal_packet_is_not_partial_success(self):
        def generate():
            yield SimpleNamespace(sample_rate=44100, audio=mx.array([.1, -.1]))
            yield SimpleNamespace(sample_rate=44100, audio=mx.zeros((0,)),
                                  is_streaming_chunk=True, is_final_chunk=True)
            raise RuntimeError('late producer failure')
        with self.assertRaisesRegex(RuntimeError, 'late producer failure'):
            worker._complete_audio(generate())

    def test_single_sample_mono_tail_is_retained(self):
        import numpy as np
        actual, rate, count = worker._complete_audio(iter([
            SimpleNamespace(sample_rate=44100, audio=mx.array([.1, -.1])),
            SimpleNamespace(sample_rate=44100, audio=mx.array([.2])),
        ]))
        self.assertEqual((rate, count), (44100, 2))
        np.testing.assert_array_equal(actual, np.array([.1, -.1, .2], dtype=np.float32))

    def test_child_termination_keeps_a_readable_rendered_prefix(self):
        from mlx_audio.audio_io import read
        script = '''
import importlib.util, sys, time
from pathlib import Path
from types import SimpleNamespace
import numpy as np
spec = importlib.util.spec_from_file_location('worker', sys.argv[1])
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
class Model:
    def generate(self, **kwargs):
        yield SimpleNamespace(sample_rate=44100, audio=np.sin(np.arange(8820) * .08) * .2)
        print('prefix-persisted', flush=True)
        time.sleep(60)
worker._model = Model()
worker._model_id = 'qwen3_tts_1_7b'
worker._synthesize({'modelId': 'qwen3_tts_1_7b', 'voice': 'Ryan',
                    'text': 'Retain speech across cancellation.', 'outputPath': sys.argv[2]})
'''
        with tempfile.TemporaryDirectory() as tmp:
            child = subprocess.Popen(
                [sys.executable, '-c', script, str(Path(worker.__file__)),
                 str(Path(tmp) / 'speech.wav')], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    child.communicate(timeout=2)
            finally:
                child.kill()
                stdout, stderr = child.communicate(timeout=5)
            self.assertIn(b'prefix-persisted', stdout, stderr.decode())
            self.assertFalse((Path(tmp) / 'speech.wav').exists())
            partial = list(Path(tmp).glob('*.partial.wav'))
            self.assertEqual(len(partial), 1)
            samples, rate = read(str(partial[0]))
            self.assertEqual((samples.size, rate), (8820, 44100))

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
