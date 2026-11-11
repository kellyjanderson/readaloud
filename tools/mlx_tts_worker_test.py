"""Run with the installed MLX runtime Python. No model weights are needed."""
import importlib.util
import hashlib
from pathlib import Path
import tempfile
import contextlib
import io
import json
import wave
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
    def test_owned_stream_joins_real_bounded_mlx_graph_without_model_weights(self):
        worker._unload()
        stream = mx.new_stream(mx.gpu)
        with mx.stream(stream):
            parameters = {'weight': mx.ones((2, 2)) + 2}
        with patch.object(worker, '_model_load_stream', stream), \
                patch.object(worker, '_model_pending_parameters', parameters):
            mx.async_eval(parameters)
            worker._join_model_weights()
            self.assertIsNone(worker._model_pending_parameters)
            self.assertEqual(parameters['weight'].sum().item(), 12)

    def test_drama_load_joins_async_weights_after_existing_qualification(self):
        worker._unload()
        events = []
        parameters = {'weight': mx.ones((2, 2))}
        model = SimpleNamespace(parameters=lambda: parameters)
        stream = object()
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / 'config.json').write_text('{}')
            def verify(*args):
                self.assertIsNone(worker._model_id)
                self.assertIs(worker._model_pending_parameters, parameters)
                events.append('verify')
                return True
            with patch('subprocess.check_output', return_value=b'137438953472'), \
                    patch('mlx_audio.tts.load', side_effect=lambda *a, **k: (events.append(('load', k)), model)[1]), \
                    patch.object(mx, 'new_stream', return_value=stream), \
                    patch.object(mx, 'stream', return_value=contextlib.nullcontext()), \
                    patch.object(mx, 'async_eval', side_effect=lambda tree: events.append('async')), \
                    patch.object(mx, 'eval', side_effect=lambda tree: events.append('join')), \
                    patch.object(mx, 'synchronize', side_effect=lambda owned: events.append(('sync', owned))), \
                    patch.object(worker, '_verify_scene_model', side_effect=verify), \
                    patch.object(worker, '_timing'):
                result = worker._load('fish_drama3', root, root)
            self.assertEqual(events, [('load', {'lazy': True}), 'async', 'verify', 'join', ('sync', stream)])
            self.assertTrue(result['loaded'])
            self.assertTrue(result['nativeScenesQualified'])
            self.assertIsNone(worker._model_pending_parameters)
            self.assertEqual(worker._model_id, 'fish_drama3')
        worker._unload()

    def test_failed_qualification_still_joins_and_cannot_report_loaded(self):
        worker._unload()
        parameters = {}
        model = SimpleNamespace(parameters=lambda: parameters)
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / 'config.json').write_text('{}')
            with patch('subprocess.check_output', return_value=b'137438953472'), \
                    patch('mlx_audio.tts.load', return_value=model), \
                    patch.object(mx, 'async_eval'), patch.object(mx, 'eval') as join, \
                    patch.object(mx, 'synchronize') as synchronize, \
                    patch.object(worker, '_verify_scene_model', side_effect=RuntimeError('qualification failed')), \
                    patch.object(worker, '_timing'):
                with self.assertRaisesRegex(RuntimeError, 'qualification failed'):
                    worker._load('fish_drama3', root, root)
                join.assert_called_once_with(parameters)
                synchronize.assert_called_once_with(worker._model_load_stream)
            self.assertIsNone(worker._model_id)
            self.assertIsNone(worker._model_pending_parameters)
        worker._unload()

    def test_unload_joins_owned_pending_work_before_releasing_model(self):
        worker._unload()
        parameters, model, stream = {}, object(), object()
        with patch.object(worker, '_model', model), \
                patch.object(worker, '_model_pending_parameters', parameters), \
                patch.object(worker, '_model_load_stream', stream), \
                patch.object(mx, 'eval') as join, patch.object(mx, 'synchronize') as synchronize:
            worker._unload()
            join.assert_called_once_with(parameters)
            synchronize.assert_called_once_with(stream)
            self.assertIsNone(worker._model)
            self.assertIsNone(worker._model_load_stream)
            self.assertIsNone(worker._model_pending_parameters)

    def test_drama_reference_timing_restores_instance_on_failure_and_close(self):
        timings = []
        class Model:
            def _voice(self, ref):
                return ref
            def generate(self, **kwargs):
                self._voice('reference')
                yield 'first'
                raise RuntimeError('late error')
        model = Model()
        for close in (False, True):
            with self.subTest(close=close), patch.object(worker, '_timing', side_effect=lambda stage, start: timings.append(stage)):
                results = worker._drama_results(model)
                self.assertEqual(next(results), 'first')
                self.assertIn('_voice', vars(model))
                if close:
                    results.close()
                else:
                    with self.assertRaisesRegex(RuntimeError, 'late error'):
                        next(results)
                self.assertNotIn('_voice', vars(model))
        self.assertEqual(timings, ['referencePrepared'] * 2)

    def test_failed_unload_retains_stream_and_tree_until_join_or_retirement(self):
        worker._unload()
        parameters, model, stream = {}, object(), object()
        with patch.object(worker, '_model', model), \
                patch.object(worker, '_model_pending_parameters', parameters), \
                patch.object(worker, '_model_load_stream', stream), \
                patch.object(mx, 'eval', side_effect=RuntimeError('join failed')):
            with self.assertRaisesRegex(RuntimeError, 'join failed'):
                worker._unload()
            self.assertIs(worker._model, model)
            self.assertIs(worker._model_load_stream, stream)
            self.assertIs(worker._model_pending_parameters, parameters)

    def test_stage_timing_is_request_scoped_diagnostic_without_fake_work(self):
        with patch.object(worker, '_active_request_id', 'load-request'), \
                patch.object(worker, '_reply') as reply, \
                patch.object(worker.time, 'monotonic', return_value=1.25), \
                contextlib.redirect_stderr(io.StringIO()):
            worker._timing('modelBuildAndCodec', 1)
        args, event = reply.call_args
        self.assertEqual(args, ('load-request',))
        self.assertEqual(event['stage'], 'modelBuildAndCodec')
        self.assertEqual(event['elapsedMilliseconds'], 250)
        self.assertIsNone(event['completed'])
        self.assertIsNone(event['total'])

    def test_opt_in_packets_are_closed_exact_pcm_before_final_publication(self):
        events = []
        class Model:
            def generate(self, **kwargs):
                self.kwargs = kwargs
                yield SimpleNamespace(sample_rate=24000, audio=mx.array([.2, -.2, .1]))
                # The first immutable packet exists before requesting more PCM.
                self.assert_packet()
                yield SimpleNamespace(sample_rate=24000, audio=mx.array([.3, -.3]))
        model = Model()
        with tempfile.TemporaryDirectory() as root, patch.object(worker, '_model', model), patch.object(worker, '_model_id', 'qwen3_tts_1_7b'):
            destination = Path(root) / 'scene.wav'
            def packet_published():
                self.assertFalse(destination.exists())
                self.assertEqual(len(events), 1)
                with wave.open(events[0]['audioPath']) as packet:
                    self.assertEqual(packet.getnframes(), 3)
            model.assert_packet = packet_published
            identity = dict(sessionId='s', generationId='g', chunkId='c', synthesisIdentity='synth', bindingFingerprint='b', bindingRevision=3)
            with patch.object(worker, '_reply', side_effect=lambda request_id, **event: events.append(event)), patch.object(worker, '_progress'):
                result = worker._synthesize(dict(modelId='qwen3_tts_1_7b', voice='Ryan', text='Hello', outputPath=str(destination), enableAudioPackets=True, **identity))
            self.assertEqual([(e['packetIndex'], e['frameStart'], e['frameCount']) for e in events], [(0, 0, 3), (1, 3, 2)])
            self.assertEqual(result['streamedPacketCount'], 2)
            self.assertEqual(result['streamedFrameCount'], 5)
            for event in events:
                self.assertEqual({key: event[key] for key in identity}, identity)
                self.assertEqual((event['channels'], event['bitsPerSample']), (1, 16))
            with wave.open(str(destination)) as full:
                actual = full.readframes(full.getnframes())
            expected = b''
            for event in events:
                with wave.open(event['audioPath']) as packet:
                    expected += packet.readframes(packet.getnframes())
            self.assertEqual(actual, expected)

    def test_packet_opt_in_requires_full_identity_and_no_packets_by_default(self):
        class Model:
            def generate(self, **kwargs):
                yield SimpleNamespace(sample_rate=24000, audio=mx.array([.2, -.2]))
        with tempfile.TemporaryDirectory() as root, patch.object(worker, '_model', Model()), patch.object(worker, '_model_id', 'qwen3_tts_1_7b'), patch.object(worker, '_reply') as reply, patch.object(worker, '_progress'):
            request = dict(modelId='qwen3_tts_1_7b', voice='Ryan', text='Hello', outputPath=str(Path(root) / 'scene.wav'))
            with self.assertRaisesRegex(ValueError, 'packet identity'):
                worker._synthesize(dict(request, enableAudioPackets=True))
            result = worker._synthesize(request)
            reply.assert_not_called()
            self.assertEqual(result['streamedPacketCount'], 0)
            self.assertEqual(list(Path(root).glob('packet-*.wav')), [])

    def test_streamed_late_failure_retains_packets_without_publishing_scene(self):
        class Model:
            def generate(self, **kwargs):
                yield SimpleNamespace(sample_rate=24000, audio=mx.array([.2, -.2]))
                raise RuntimeError('late producer failure')
        with tempfile.TemporaryDirectory() as root, patch.object(worker, '_model', Model()), patch.object(worker, '_model_id', 'qwen3_tts_1_7b'), patch.object(worker, '_reply') as reply, patch.object(worker, '_progress'):
            destination = Path(root) / 'scene.wav'
            with self.assertRaisesRegex(RuntimeError, 'late producer failure'):
                worker._synthesize(dict(modelId='qwen3_tts_1_7b', voice='Ryan', text='Hello', outputPath=str(destination), enableAudioPackets=True, sessionId='s', generationId='g', chunkId='c', synthesisIdentity='synth', bindingFingerprint='b', bindingRevision=1))
            reply.assert_called_once()
            self.assertFalse(destination.exists())
            with wave.open(str(Path(root) / 'packet-0000.wav')) as packet:
                self.assertEqual(packet.getnframes(), 2)

    def test_packet_limit_retains_prefix_without_complete_publication(self):
        class Model:
            def generate(self, **kwargs):
                for _ in range(2049):
                    yield SimpleNamespace(sample_rate=24000, audio=mx.array([.2]))
        with tempfile.TemporaryDirectory() as root, patch.object(worker, '_model', Model()), patch.object(worker, '_model_id', 'qwen3_tts_1_7b'), patch.object(worker, '_reply'), patch.object(worker, '_progress'):
            destination = Path(root) / 'scene.wav'
            with self.assertRaisesRegex(RuntimeError, 'spool exceeded'):
                worker._synthesize(dict(modelId='qwen3_tts_1_7b', voice='Ryan', text='Hello', outputPath=str(destination), enableAudioPackets=True, sessionId='s', generationId='g', chunkId='c', synthesisIdentity='synth', bindingFingerprint='b', bindingRevision=1))
            self.assertFalse(destination.exists())
            self.assertEqual(len(list(Path(root).glob('packet-*.wav'))), 2048)

    def test_model_qualification_is_content_based_and_cached_by_exact_file_state(self):
        with tempfile.TemporaryDirectory() as root:
            directory=Path(root)/'model'; directory.mkdir()
            receipt=Path(root)/'receipts'
            path=directory/'model.safetensors'; path.write_bytes(b'known pinned bytes')
            manifest=dict(revision='pinned',files={'model.safetensors':dict(size=path.stat().st_size,
                algorithm='sha256',digest=hashlib.sha256(path.read_bytes()).hexdigest())})
            with patch.object(worker, '_progress'):
                self.assertTrue(worker._verify_scene_model(directory,manifest,receipt))
                with patch('huggingface_hub.utils._verification.compute_file_hash',side_effect=AssertionError('must reuse exact verification')):
                    self.assertTrue(worker._verify_scene_model(directory,manifest,receipt))
                path.write_bytes(b'wrong pinned bytes')
                self.assertFalse(worker._verify_scene_model(directory,manifest,receipt))
                path.unlink()
                self.assertFalse(worker._verify_scene_model(directory,manifest,receipt))

    def test_unqualified_model_cannot_accept_scene_turns(self):
        with tempfile.TemporaryDirectory() as root, patch.object(worker,'_model_native_scenes',False):
            path=Path(root)/'voice.wav'; path.write_bytes(b'reference')
            req=dict(voice='library_a',references=[dict(voice='library_a',referenceAudioPath=str(path),referenceText='Reference.')],
                     sceneTurns=[dict(voice='library_a',text='Hello.',startWord=0,endWord=1)])
            with self.assertRaisesRegex(ValueError,'verified pinned'):
                worker._drama_reference_inputs(req,'Hello.')

    def test_native_scene_is_one_ordered_call_with_delivery_and_source_validation(self):
        calls = []
        class Model:
            def generate(self, **kwargs):
                calls.append(kwargs)
                yield SimpleNamespace(sample_rate=44100, audio=mx.array([.2, -.2]))
        with tempfile.TemporaryDirectory() as root, patch.object(worker, '_model', Model()), patch.object(worker, '_model_id', 'fish_drama3'), patch.object(worker, '_model_native_scenes', True):
            ref = Path(root) / 'ref.wav'
            ref.write_bytes(b'input routing only')
            refs = [dict(voice=v, referenceAudioPath=str(ref), referenceText='Reference.') for v in ['library_mira', 'library_mara']]
            turns = [dict(voice='library_mira', text='[whispers] Be quiet.', startWord=0, endWord=2),
                     dict(voice='library_mara', text='[shouting] I hear footsteps!', startWord=2, endWord=5),
                     dict(voice='library_mira', text='Wait here.', startWord=5, endWord=7)]
            req = dict(modelId='fish_drama3', voice='library_mira', references=refs, sceneTurns=turns,
                       text='Be quiet. I hear footsteps! Wait here.', outputPath=str(Path(root) / 'scene.wav'))
            worker._synthesize(req)
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0]['text'], '<|speaker:0|> [whispers] Be quiet.\n<|speaker:1|> [shouting] I hear footsteps!\n<|speaker:0|> Wait here.')
            for changed in [dict(turns[1], startWord=3), dict(turns[1], voice='missing'), dict(turns[1], text='<|speaker:0|> injected')]:
                with self.assertRaises(ValueError):
                    worker._drama_reference_inputs(dict(req, sceneTurns=[turns[0], changed, turns[2]]), req['text'])

    def test_drama_turns_share_reference_set_and_use_selected_native_slot(self):
        with tempfile.TemporaryDirectory() as root:
            paths = [Path(root) / name for name in ('a.wav', 'b.wav')]
            for path in paths:
                path.write_bytes(b'validated by model loader, not this input test')
            refs = [dict(voice=f'library_{name}', referenceAudioPath=str(path),
                         referenceText=f'Reference {name}.')
                    for name, path in zip(('alice', 'beth'), paths)]
            results = [worker._drama_reference_inputs(
                dict(voice=f'library_{name}', references=refs), 'Hello.')
                for name in ('alice', 'beth', 'alice')]
            self.assertEqual([r[0] for r in results], [
                '<|speaker:0|> Hello.', '<|speaker:1|> Hello.', '<|speaker:0|> Hello.'])
            self.assertEqual(results[0][1:], results[1][1:])
            self.assertEqual(results[0][2], [
                '<|speaker:0|> Reference alice.', '<|speaker:1|> Reference beth.'])
            for invalid in ([], refs * 9, [refs[0], refs[0]]):
                with self.assertRaises(ValueError):
                    worker._drama_reference_inputs(dict(voice='library_alice', references=invalid), 'Hello.')
            with self.assertRaises(ValueError):
                worker._drama_reference_inputs(dict(voice='library_missing', references=refs), 'Hello.')

    def test_drama_native_generator_receives_cast_and_preserves_delivery_cues(self):
        calls = []
        class Model:
            def generate(self, **kwargs):
                calls.append(kwargs)
                yield SimpleNamespace(sample_rate=44100, audio=mx.array([.2, -.2]))
        with tempfile.TemporaryDirectory() as root, \
                patch.object(worker, '_model', Model()), \
                patch.object(worker, '_model_id', 'fish_drama3'):
            ref = Path(root) / 'reference.wav'
            ref.write_bytes(b'input only, native encoder replaced by test model')
            references = [dict(voice=f'library_{name}', referenceAudioPath=str(ref),
                               referenceText=f'Reference {name}.') for name in ('alice', 'beth')]
            worker._synthesize(dict(modelId='fish_drama3', voice='library_beth',
                                    references=references, text='[whispering] Stay here.',
                                    outputPath=str(Path(root) / 'speech.wav')))
            self.assertEqual(calls[0]['text'], '<|speaker:1|> [whispering] Stay here.')
            self.assertEqual(calls[0]['ref_audio'], [str(ref), str(ref)])
            self.assertEqual(calls[0]['ref_text'], [
                '<|speaker:0|> Reference alice.', '<|speaker:1|> Reference beth.'])
            self.assertTrue(calls[0]['stream'])
            self.assertEqual(calls[0]['streaming_interval'], 0.32)
            self.assertEqual(calls[0]['first_chunk_frames'], 4)

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
    @contextlib.contextmanager
    def fixture(self, model_id='fish_drama3'):
        # Tiny pinned fixtures exercise real HF offline resolution and hashing.
        # Only the network transfer boundary is substituted in repair tests.
        with tempfile.TemporaryDirectory() as root:
            cache = Path(root) / 'hub'
            spec = dict(worker.DRAMA_MODELS[model_id], requiredFiles=['config.json', 'model.safetensors', 'codec.safetensors'])
            snapshot = cache / ('models--' + spec['repo'].replace('/', '--')) / 'snapshots' / spec['revision']
            snapshot.mkdir(parents=True)
            content = {'config.json': b'{}', 'model.safetensors': b'pinned weights', 'codec.safetensors': b'pinned codec'}
            entries = {}
            for name, data in content.items():
                (snapshot / name).write_bytes(data)
                entries[name] = dict(size=len(data), algorithm='sha256', digest=hashlib.sha256(data).hexdigest())
            manifest = dict(repo=spec['repo'], revision=spec['revision'], files=entries)
            with patch.dict(worker.DRAMA_MODELS, {model_id: spec}), \
                    patch.object(worker, '_model_manifest', return_value=manifest), \
                    patch.dict(os.environ, {'HF_HUB_CACHE': str(cache)}), \
                    patch('socket.socket.connect', side_effect=AssertionError('fixture attempted network')), \
                    patch.object(worker, '_configure_hf_cache'), patch.object(worker, '_progress'):
                yield cache, snapshot, manifest, content

    def test_completed_pinned_snapshot_reuses_files_without_network(self):
        import huggingface_hub
        with self.fixture() as (cache, snapshot, manifest, _):
            real_download = huggingface_hub.snapshot_download
            def offline_only(**kwargs):
                self.assertTrue(kwargs.get('local_files_only'), 'Warm startup attempted network/download')
                return real_download(**kwargs)
            with patch('huggingface_hub.snapshot_download', side_effect=offline_only) as download:
                for _ in range(3):
                    self.assertEqual(worker._download_model('fish_drama3', str(cache)).resolve(), snapshot.resolve())
                self.assertEqual(download.call_count, 3)
            receipts = list((cache.parent / 'model-qualification').glob('*.json'))
            self.assertEqual(len(receipts), 1)
            self.assertEqual(json.loads(receipts[0].read_text())['revision'], manifest['revision'])

    def test_same_size_corruption_repairs_only_bad_owned_file_and_preserves_variant(self):
        import huggingface_hub
        with self.fixture() as (cache, snapshot, manifest, content):
            bad = snapshot / 'model.safetensors'
            blobs = snapshot.parent.parent / 'blobs'; blobs.mkdir()
            blob = blobs / manifest['files'][bad.name]['digest']
            bad.replace(blob); bad.symlink_to(blob)
            worker._download_model('fish_drama3', str(cache))  # establish real stat receipt
            bad.write_bytes(b'x' * len(content[bad.name]))
            good = {name: (snapshot / name).stat() for name in content if name != bad.name}
            other = cache / 'other-variant' / 'weights'; other.parent.mkdir(); other.write_bytes(b'unrelated')
            partial = cache / 'resume.incomplete'; partial.write_bytes(b'partial')
            real_download = huggingface_hub.snapshot_download
            def snapshot_download(**kwargs):
                self.assertEqual((kwargs['repo_id'], kwargs['revision']), (manifest['repo'], manifest['revision']))
                if kwargs.get('local_files_only'):
                    return real_download(**kwargs)
                if kwargs.get('dry_run'):
                    return [SimpleNamespace(file_size=len(data), will_download=False) for data in content.values()]
                self.assertFalse(kwargs.get('force_download', False))
                return str(snapshot)
            def repair(**kwargs):
                self.assertIn('tqdm_class', kwargs)
                self.assertEqual({key: value for key, value in kwargs.items() if key != 'tqdm_class'}, dict(repo_id=manifest['repo'], filename=bad.name,
                    revision=manifest['revision'], cache_dir=str(cache), force_download=True))
                bad.write_bytes(content[bad.name])
                return str(bad)
            with patch('huggingface_hub.snapshot_download', side_effect=snapshot_download), \
                    patch('huggingface_hub.hf_hub_download', side_effect=repair) as transfer:
                self.assertEqual(worker._download_model('fish_drama3', str(cache)), snapshot)
                transfer.assert_called_once()
            self.assertEqual(other.read_bytes(), b'unrelated')
            self.assertEqual(partial.read_bytes(), b'partial')
            for name, before in good.items():
                self.assertEqual((snapshot / name).stat(), before)

    def test_download_returning_different_pin_or_corrupt_bytes_is_not_completed(self):
        for defect in ['revision', 'bytes']:
            with self.subTest(defect=defect), self.fixture() as (cache, snapshot, manifest, content):
                missing = snapshot / 'model.safetensors'; missing.unlink()
                returned = snapshot
                if defect == 'revision':
                    returned = snapshot.with_name('0' * 40)
                    returned.mkdir()
                def download(**kwargs):
                    self.assertEqual(kwargs['revision'], manifest['revision'])
                    if kwargs.get('local_files_only'):
                        raise FileNotFoundError('snapshot not complete')
                    if kwargs.get('dry_run'):
                        return [SimpleNamespace(file_size=len(data), will_download=True) for data in content.values()]
                    for name, data in content.items():
                        (returned / name).write_bytes(data if defect == 'revision' else b'x' * len(data))
                    return str(returned)
                with patch('huggingface_hub.snapshot_download', side_effect=download):
                    with self.assertRaisesRegex(ValueError, 'failed pinned integrity'):
                        worker._download_model('fish_drama3', str(cache))
                self.assertFalse((cache.parent / 'model-qualification').exists())

    def test_interruption_retains_partial_and_good_files_then_retries_same_cache(self):
        import huggingface_hub
        with self.fixture('fish_drama3_4bit') as (cache, snapshot, manifest, content):
            missing = snapshot / 'model.safetensors'; missing.unlink()
            partial = cache / 'model.incomplete'; partial.write_bytes(b'pinned ')
            good = (snapshot / 'codec.safetensors').stat()
            real_download = huggingface_hub.snapshot_download
            attempts = 0
            def transfer(**kwargs):
                nonlocal attempts
                self.assertEqual(kwargs['cache_dir'], str(cache))
                self.assertEqual(kwargs['repo_id'], manifest['repo'])
                if kwargs.get('local_files_only'):
                    return real_download(**kwargs)
                if kwargs.get('dry_run'):
                    return [SimpleNamespace(file_size=len(data), will_download=(name == missing.name))
                            for name, data in content.items()]
                self.assertFalse(kwargs.get('force_download', False))
                self.assertEqual(partial.read_bytes(), b'pinned ')
                attempts += 1
                if attempts == 1:
                    raise ConnectionError('interrupted transfer')
                missing.write_bytes(partial.read_bytes() + b'weights')
                partial.unlink()
                return str(snapshot)
            with patch('huggingface_hub.snapshot_download', side_effect=transfer), \
                    patch('huggingface_hub.hf_hub_download', side_effect=AssertionError('missing file must resume')):
                with self.assertRaisesRegex(ConnectionError, 'interrupted'):
                    worker._download_model('fish_drama3_4bit', str(cache))
                self.assertFalse((cache.parent / 'model-qualification').exists())
                self.assertEqual(worker._download_model('fish_drama3_4bit', str(cache)), snapshot)
            self.assertEqual(attempts, 2)
            self.assertEqual((snapshot / 'codec.safetensors').stat(), good)

    def test_corrupt_external_symlink_is_refused_without_mutation(self):
        with self.fixture() as (cache, snapshot, _, content):
            external = cache.parent / 'user-weights'; external.write_bytes(b'x' * len(content['model.safetensors']))
            weight = snapshot / 'model.safetensors'; weight.unlink(); weight.symlink_to(external)
            with patch('huggingface_hub.hf_hub_download') as transfer:
                with self.assertRaisesRegex(ValueError, 'outside the managed'):
                    worker._download_model('fish_drama3', str(cache))
                transfer.assert_not_called()
            self.assertEqual(external.read_bytes(), b'x' * len(content['model.safetensors']))

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


class ModelAssetVerificationTest(unittest.TestCase):
    fixture = ModelDownloadReuseTest.fixture

    def test_manifest_selects_exact_variant_and_preserves_legacy_identity(self):
        original = worker._model_manifest
        with self.fixture() as (_, _, manifest, _):
            with patch('pathlib.Path.read_text', return_value=json.dumps(manifest)):
                self.assertEqual(original('fish_drama3'), manifest)
                with self.assertRaisesRegex(ValueError, 'manifest'):
                    original('fish_drama3_4bit')
            bundle = dict(schemaVersion=2, variants={'fish_drama3': manifest})
            with patch('pathlib.Path.read_text', return_value=json.dumps(bundle)):
                self.assertEqual(original('fish_drama3'), manifest)
            for invalid in [dict(bundle, schemaVersion=3), dict(schemaVersion=2, variants={}),
                            dict(manifest, revision='0' * 40), dict(manifest, repo='wrong/repo'),
                            dict(manifest, files={}), [], dict(manifest, files=[]),
                            dict(manifest, files=dict(manifest['files'], **{'../escape': manifest['files']['config.json']}))]:
                with self.subTest(invalid=invalid), patch('pathlib.Path.read_text', return_value=json.dumps(invalid)):
                    with self.assertRaisesRegex(ValueError, 'manifest'):
                        original('fish_drama3')
            with patch('pathlib.Path.read_text', side_effect=FileNotFoundError('missing bundle')):
                with self.assertRaisesRegex(ValueError, 'Update the application'):
                    original('fish_drama3')

    def test_legacy_stat_receipt_reuses_without_hashing_and_publication_is_atomic(self):
        with self.fixture() as (cache, snapshot, manifest, _):
            receipt_root = cache.parent / 'model-qualification'
            state = {}
            for name in manifest['files']:
                st = (snapshot / name).stat()
                state[name] = [st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns]
            identity = hashlib.sha256(json.dumps([str(snapshot), manifest, state], sort_keys=True).encode()).hexdigest()
            receipt = receipt_root / (identity + '.json')
            real_replace = Path.replace
            publications = []
            def publish(temporary, destination):
                self.assertFalse(destination.exists())
                payload = json.loads(temporary.read_text())
                self.assertEqual(payload, dict(verifiedIdentity=identity, revision=manifest['revision'], files=state))
                publications.append(payload)
                return real_replace(temporary, destination)
            with patch.object(Path, 'replace', publish):
                self.assertTrue(worker._verify_scene_model(snapshot, manifest, receipt_root))
            self.assertEqual(len(publications), 1)
            self.assertEqual(list(receipt_root.iterdir()), [receipt])
            with patch('huggingface_hub.utils._verification.compute_file_hash', side_effect=AssertionError('legacy receipt rehashed')):
                self.assertTrue(worker._verify_scene_model(snapshot, manifest, receipt_root))

    def test_interrupted_receipt_never_publishes_complete_and_retry_recovers(self):
        with self.fixture() as (cache, snapshot, manifest, _):
            receipts = cache.parent / 'model-qualification'
            with patch.object(Path, 'replace', side_effect=OSError('interrupted receipt')):
                with self.assertRaisesRegex(OSError, 'interrupted receipt'):
                    worker._verify_scene_model(snapshot, manifest, receipts)
            self.assertEqual(list(receipts.iterdir()), [])
            self.assertTrue(worker._verify_scene_model(snapshot, manifest, receipts))

    def test_change_during_hash_or_receipt_publication_cannot_be_accepted(self):
        from huggingface_hub.utils._verification import compute_file_hash
        for phase in ['hash', 'publish']:
            with self.subTest(phase=phase), self.fixture() as (cache, snapshot, manifest, content):
                receipts = cache.parent / 'model-qualification'
                real_replace = Path.replace
                def hash_and_change(path, algorithm):
                    digest = compute_file_hash(path, algorithm)
                    if path.name == 'model.safetensors':
                        path.write_bytes(b'x' * len(content[path.name]))
                    return digest
                def publish_and_change(path, destination):
                    result = real_replace(path, destination)
                    weight = snapshot / 'model.safetensors'
                    weight.write_bytes(b'x' * len(content[weight.name]))
                    return result
                target = ('huggingface_hub.utils._verification.compute_file_hash'
                          if phase == 'hash' else 'pathlib.Path.replace')
                effect = hash_and_change if phase == 'hash' else publish_and_change
                with patch(target, side_effect=effect, autospec=(phase == 'publish')):
                    self.assertFalse(worker._verify_scene_model(snapshot, manifest, receipts))
                self.assertFalse(worker._verify_scene_model(snapshot, manifest, receipts))

    def test_verified_quantized_load_is_direct_and_rechecks_resident_assets(self):
        worker._unload()
        with self.fixture('fish_drama3_8bit') as (cache, snapshot, manifest, content):
            with patch('subprocess.check_output', return_value=b'137438953472'), \
                    patch('mlx_audio.tts.load', return_value=SimpleNamespace()) as load, \
                    patch('mlx_audio.lm.convert.quantize_model', side_effect=AssertionError('prequantized variant must load directly')), \
                    patch.object(worker, '_timing'):
                result = worker._load('fish_drama3_8bit', str(snapshot), str(cache), require_verified_model_assets=True)
                self.assertTrue(result['modelAssetsVerified'])
                self.assertEqual(result['verifiedModelIdentity'], manifest['repo'] + '@' + manifest['revision'])
                self.assertFalse(result['nativeScenesQualified'])
                load.assert_called_once_with(str(snapshot.resolve()), lazy=False)
                self.assertEqual(worker._load('fish_drama3_8bit', str(snapshot), str(cache), require_verified_model_assets=True), result)
                bad = snapshot / 'codec.safetensors'; bad.write_bytes(b'x' * len(content[bad.name]))
                with self.assertRaisesRegex(ValueError, 'failed pinned integrity'):
                    worker._load('fish_drama3_8bit', str(snapshot), str(cache), require_verified_model_assets=True)
                load.assert_called_once()
                self.assertEqual(bad.read_bytes(), b'x' * len(content[bad.name]))
        worker._unload()

    def test_unverified_explicit_path_refused_before_loading_and_never_mutated(self):
        worker._unload()
        with self.fixture() as (cache, snapshot, _, content):
            bad = snapshot / 'model.safetensors'; bad.write_bytes(b'x' * len(content[bad.name]))
            with patch('subprocess.check_output', return_value=b'137438953472'), \
                    patch('mlx_audio.tts.load') as load:
                with self.assertRaisesRegex(ValueError, 'no weights were loaded'):
                    worker._load('fish_drama3', str(snapshot), str(cache), require_verified_model_assets=True)
                load.assert_not_called()
            self.assertEqual(bad.read_bytes(), b'x' * len(content[bad.name]))

    def test_require_verified_request_flag_is_strict_boolean(self):
        replies = []
        requests = [dict(id=str(i), command='load', modelId='fish_drama3', requireVerifiedModelAssets=value)
                    for i, value in enumerate(['false', 1, None, [], {}])]
        with patch.object(sys, 'stdin', io.StringIO(''.join(json.dumps(r) + '\n' for r in requests))), \
                patch.object(worker, '_reply', side_effect=lambda request_id, **payload: replies.append(payload)), \
                patch.object(worker, '_unload'), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(worker.main(), 0)
        self.assertEqual(len(replies), len(requests))
        self.assertTrue(all(not reply['ok'] and 'must be a boolean' in reply['error'] for reply in replies))


if __name__ == "__main__":
    unittest.main()
