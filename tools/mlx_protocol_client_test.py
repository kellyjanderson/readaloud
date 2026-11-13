"""No weights/inference: real pipe/process lifecycle and production metadata tests."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import mlx_tts_benchmark
import qualify_voice_library

from build_voice_library import complete_voice_design
from mlx_probe_support import ROOT, descriptor, resolve_voice, sha256, audio_evidence, synthesize
from mlx_protocol_client import MlxClient, ProtocolError, RequestCancelled
from stage_mlx_qa_cache import MLX_SUFFIX, cache_paths, stage_cache


FAKE = r'''
import json, sys, time, os, signal
mode = sys.argv[1]
if mode == 'ignore_term': signal.signal(signal.SIGTERM, signal.SIG_IGN)
for line in sys.stdin:
    request = json.loads(line)
    rid = request['id']
    def emit(**value): print(json.dumps(dict(id=rid, **value)), flush=True)
    if request['command'] == 'environment':
        emit(ok=True, hf=os.environ.get('HF_HUB_OFFLINE'), transformers=os.environ.get('TRANSFORMERS_OFFLINE'))
        continue
    if request['command'] == 'shutdown':
        if mode == 'shutdown_hang': time.sleep(30)
        emit(ok=True, shutdown=True)
        if mode.endswith('shutdown_nonzero'): sys.exit(7)
        break
    if mode in ('hang', 'ignore_term'): time.sleep(30)
    if mode == 'malformed': print('{broken', flush=True); continue
    if mode == 'wrong': print(json.dumps(dict(id='unowned', ok=True)), flush=True); continue
    if mode == 'long': print('x' * 2048, flush=True); continue
    if mode == 'eof': print('{"id":', end='', flush=True); sys.exit()
    if mode == 'failure': emit(ok=False, error='fixture failure'); continue
    if mode == 'stderr': sys.stderr.write('e' * 200000); sys.stderr.flush()
    print(json.dumps(dict(id='', type='memory', footprintBytes=42)), flush=True)
    emit(type='progress', completed=1, total=2, stage='fixture')
    if request['command'] == 'synthesize':
        identity = {key: request[key] for key in ('sessionId', 'generationId', 'chunkId', 'synthesisIdentity', 'bindingFingerprint', 'bindingRevision')}
        pcm = []
        for index in range(2):
            fields = {}
            frames = 10
            if mode in ('render', 'render_wrong_final', 'render_shutdown_nonzero'):
                import wave
                from pathlib import Path
                frames = 24000
                block = bytes([index + 1, 32]) * frames
                pcm.append(block)
                path = Path(request['outputPath']).parent / ('packet-%04d.wav' % index)
                with wave.open(str(path), 'wb') as audio:
                    audio.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
                    audio.writeframes(block)
                fields['audioPath'] = str(path)
            emit(type='audioPacket', packetIndex=index, frameStart=index * frames, frameCount=frames,
                 sampleRate=24000, channels=1, bitsPerSample=16, **identity, **fields)
        if mode == 'late_failure': emit(ok=False, error='after packets'); continue
        if mode == 'cancel_after_packet': time.sleep(30)
        fields = {}
        if pcm:
            with wave.open(request['outputPath'], 'wb') as audio:
                audio.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
                audio.writeframes(b'\0' * len(b''.join(pcm)) if mode == 'render_wrong_final' else b''.join(pcm))
            fields = dict(audioPath=request['outputPath'], nativeSampleRate=24000)
        emit(ok=True, generatedPieces=2, streamedPacketCount=1 if mode == 'bad_count' else 2,
             streamedFrameCount=48000 if pcm else 20, **identity, **fields)
    else: emit(ok=True, loaded=True)
    if mode == 'duplicate': emit(ok=True)
'''


def fake(mode='normal', **kwargs):
    return MlxClient([sys.executable, '-u', '-c', FAKE, mode], **kwargs)


def packet_request(client, **kwargs):
    return client.request('synthesize', enableAudioPackets=True, sessionId='s', generationId='g',
                          chunkId='c', synthesisIdentity='i', bindingFingerprint='f', bindingRevision=1,
                          **kwargs)


class ProcessClientTest(unittest.TestCase):
    def assert_retired(self, client):
        self.assertTrue(client.closed)
        self.assertIsNotNone(client.child.poll())
        self.assertTrue(client.child.stdout.closed)
        self.assertTrue(client.child.stderr.closed)
        self.assertTrue(client.child.stdin.closed)

    def test_load_progress_two_pieces_final_shutdown(self):
        events = []
        with fake() as client:
            self.assertTrue(client.request('load')['loaded'])
            result = packet_request(client, on_event=events.append)
            self.assertEqual(result['generatedPieces'], 2)
        self.assertEqual([event['type'] for event in events], ['progress', 'audioPacket', 'audioPacket'])
        self.assert_retired(client)
        self.assertEqual(client.child.returncode, 0)

    def test_stderr_is_drained_and_tail_is_bounded(self):
        with fake('stderr') as client:
            self.assertTrue(client.request('load', timeout=3)['loaded'])
            self.assertLessEqual(len(client.stderr), client.STDERR_TAIL)
        self.assert_retired(client)

    def test_offline_settings_are_scoped_to_owned_child(self):
        import os
        with patch.dict(os.environ, {'HF_HUB_OFFLINE': '0', 'TRANSFORMERS_OFFLINE': '0'}):
            with fake() as client:
                response = client.request('environment')
                self.assertEqual((response['hf'], response['transformers']), ('1', '1'))
            self.assertEqual(os.environ['HF_HUB_OFFLINE'], '0')
            self.assertEqual(os.environ['TRANSFORMERS_OFFLINE'], '0')

    def test_protocol_failure_retires_owned_process(self):
        for mode in ('malformed', 'wrong', 'eof', 'failure', 'bad_count', 'late_failure'):
            with self.subTest(mode=mode):
                client = fake(mode)
                with self.assertRaises(ProtocolError):
                    packet_request(client, timeout=2)
                self.assert_retired(client)

    def test_line_and_event_and_total_byte_bounds(self):
        client = fake('long')
        client.MAX_LINE = 1024
        with self.assertRaisesRegex(ProtocolError, 'line bound'):
            client.request('load')
        self.assert_retired(client)
        client = fake()
        client.MAX_EVENTS = 1
        with self.assertRaisesRegex(ProtocolError, 'event bound'):
            client.request('load')
        self.assert_retired(client)
        client = fake()
        client.MAX_OUTPUT = 10
        with self.assertRaisesRegex(ProtocolError, 'byte bound'):
            client.request('load')
        self.assert_retired(client)

    def test_timeout_terminates_and_reaps(self):
        client = fake('hang')
        with self.assertRaises(TimeoutError):
            client.request('load', timeout=.1)
        self.assert_retired(client)

    def test_cancel_before_request_and_after_packets_retires(self):
        for early, mode in ((True, 'cancel_after_packet'), (False, 'cancel_after_packet'), (False, 'normal')):
            event = threading.Event()
            if early:
                event.set()
            client = fake(mode)
            def progress(message):
                if message['type'] == 'audioPacket':
                    event.set()
            with self.assertRaises(RequestCancelled):
                packet_request(client, cancel=event, on_event=progress, timeout=3)
            self.assert_retired(client)

    def test_uncooperative_child_is_killed_after_cancel(self):
        client = fake('ignore_term')
        # Child acknowledges progress only in other modes; timeout allows its
        # signal handler to install before the deterministic retirement test.
        with self.assertRaises(TimeoutError):
            client.request('load', timeout=.2)
        self.assert_retired(client)
        self.assertEqual(client.child.returncode, -9)

    def test_callback_failure_retires(self):
        client = fake()
        def fail(message):
            raise ValueError('consumer failed')
        with self.assertRaisesRegex(ValueError, 'consumer failed'):
            client.request('load', on_event=fail)
        self.assert_retired(client)

    def test_duplicate_response_cannot_satisfy_adjacent_request(self):
        client = fake('duplicate')
        client.request('load')
        with self.assertRaisesRegex(ProtocolError, 'mismatched'):
            client.request('load')
        self.assert_retired(client)

    def test_shutdown_requires_ack_exit_and_zero_status(self):
        for mode in ('shutdown_hang', 'shutdown_nonzero'):
            client = fake(mode, shutdown_timeout=.1)
            with self.subTest(mode=mode), self.assertRaises((ProtocolError, TimeoutError)):
                client.close()
            self.assert_retired(client)

    def test_context_exception_retires_without_queued_shutdown(self):
        client = fake('hang')
        with self.assertRaisesRegex(ValueError, 'caller'):
            with client:
                raise ValueError('caller')
        self.assert_retired(client)

    def test_probe_consumes_complete_packet_pcm_and_refuses_wrong_final(self):
        with tempfile.TemporaryDirectory() as root:
            with fake('render') as client:
                evidence = synthesize(client, {'modelId': 'fixture'}, {'voice': 'fixture'},
                                      'Test all emitted samples.', Path(root) / 'render', 'fixture')
            self.assertEqual(evidence['frames'], 48000)
            self.assertEqual(evidence['protocolFinal']['generatedPieces'], 2)
            with fake('render_wrong_final') as client:
                with self.assertRaisesRegex(ValueError, 'Final PCM differs'):
                    synthesize(client, {'modelId': 'fixture'}, {'voice': 'fixture'},
                               'Refuse a mismatched final.', Path(root) / 'wrong', 'fixture')


class CatalogAndStagingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with MlxClient() as client:
            cls.metadata = client.metadata()

    def test_real_production_metadata_matches_pinned_assets_and_presets(self):
        fish = json.loads((ROOT / 'assets/fish_drama_models.json').read_text())
        local = json.loads((ROOT / 'assets/voice_library/library.json').read_text())
        remote = json.loads((ROOT / 'assets/fish_voice_library.json').read_text())
        expected = {voice['id']: voice for voice in local['voices'] + remote['voices']}
        for key, value in fish.items():
            model = descriptor(self.metadata, key)
            self.assertEqual(model['descriptor'], value)
            self.assertEqual(model['revision'], value['revision'])
            self.assertEqual({voice['id'] for voice in model['voices']}, set(expected))
        self.assertEqual(len(expected), len(local['voices']) + len(remote['voices']))
        self.assertEqual(descriptor(self.metadata, 'qwen3_tts_1_7b')['voiceKind'], 'preset')
        self.assertIn('Ryan', [voice['id'] for voice in descriptor(self.metadata, 'qwen3_tts_1_7b')['voices']])
        self.assertIn('casual_male', [voice['id'] for voice in descriptor(self.metadata, 'voxtral_4b')['voices']])
        for engine in ('qwen3_tts_base_1_7b', 'moss_tts_8b'):
            model = descriptor(self.metadata, engine)
            self.assertIsNone(model['revision'])
            self.assertEqual({voice['id'] for voice in model['voices']}, set(expected))
        self.assertEqual(self.metadata['workerSha256'], sha256(ROOT / 'assets/mlx_tts_worker.py'))

    def test_voice_resolution_verifies_content_and_refuses_missing_or_unknown(self):
        model = descriptor(self.metadata, 'fish_drama3')
        voice, receipt = resolve_voice(model, 'library_ava')
        self.assertEqual(receipt['verifiedReferenceSha256'], sha256(voice['referenceAudioPath']))
        remote = next(value for value in model['voices'] if 'url' in value)
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError, 'No verified offline'):
                resolve_voice(model, remote['id'], root)
            target = Path(root) / 'voice-library' / f'{remote["sha256"]}.mp3'
            target.parent.mkdir()
            target.write_bytes(b'wrong reference')
            with self.assertRaisesRegex(ValueError, 'No verified offline'):
                resolve_voice(model, remote['id'], root)
        with self.assertRaisesRegex(ValueError, 'unavailable'):
            resolve_voice(model, 'invented')

    def test_staging_includes_all_current_variants_and_refuses_existing_data(self):
        with tempfile.TemporaryDirectory() as root:
            source, target = Path(root) / 'user', Path(root) / 'qa'
            source.mkdir()
            for name in self.metadata['models']:
                cache = source / MLX_SUFFIX / name
                cache.mkdir(parents=True)
                (cache / 'config.json').write_text(name)
            (source / 'private-document.txt').write_text('never stage user documents')
            copied = stage_cache(source, target, self.metadata, clone=shutil.copytree)
            for name in self.metadata['models']:
                self.assertIn(str(MLX_SUFFIX / name), copied)
                self.assertEqual((target / MLX_SUFFIX / name / 'config.json').read_text(), name)
            self.assertFalse((target / 'private-document.txt').exists())
            with self.assertRaises(FileExistsError):
                stage_cache(source, target, self.metadata, clone=shutil.copytree)
            self.assertEqual((source / 'private-document.txt').read_text(), 'never stage user documents')

    def test_staging_refuses_paths_or_symlinks_that_alias_user_data(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / 'user'
            source.mkdir()
            cache = source / MLX_SUFFIX / 'fish_drama3'
            cache.mkdir(parents=True)
            private = source / 'private'
            private.write_text('user data')
            (cache / 'escape').symlink_to(private)
            with self.assertRaisesRegex(ValueError, 'symlink escapes'):
                stage_cache(source, Path(root) / 'qa', self.metadata, clone=shutil.copytree)
            self.assertFalse((Path(root) / 'qa').exists())
            with self.assertRaisesRegex(ValueError, 'independent'):
                stage_cache(source, source / 'nested-qa', self.metadata)
            alias = Path(root) / 'alias'
            alias.symlink_to(source, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'independent'):
                stage_cache(source, alias / 'nested-qa', self.metadata)
        with self.assertRaises(ValueError):
            cache_paths({'models': {'bad': {'cacheDirectory': '../outside'}}})

    def test_platform_clone_keeps_writes_independent(self):
        with tempfile.TemporaryDirectory() as root:
            source, target = Path(root) / 'source', Path(root) / 'qa'
            cache = source / MLX_SUFFIX / 'fish_drama3_4bit'
            cache.mkdir(parents=True)
            (cache / 'config.json').write_text('source fixture')
            stage_cache(source, target, self.metadata)
            cloned = target / MLX_SUFFIX / 'fish_drama3_4bit' / 'config.json'
            cloned.write_text('QA write')
            self.assertEqual((cache / 'config.json').read_text(), 'source fixture')

    def test_staging_refuses_absolute_internal_symlinks_before_copy(self):
        for clone in (None, lambda source, target: shutil.copytree(source, target, symlinks=True)):
            with self.subTest(platform_clone=clone is None), tempfile.TemporaryDirectory() as root:
                source, target = Path(root) / 'source', Path(root) / 'qa'
                cache = source / MLX_SUFFIX / 'fish_drama3_4bit'
                cache.mkdir(parents=True)
                blob = cache / 'blob'
                blob.write_text('source fixture')
                (cache / 'config.json').symlink_to(blob)
                with self.assertRaisesRegex(ValueError, 'absolute'):
                    stage_cache(source, target, self.metadata, clone=clone)
                self.assertFalse(target.exists())
                self.assertEqual(blob.read_text(), 'source fixture')

    def test_relative_internal_symlinks_preserve_independent_qa_writes(self):
        for clone in (None, lambda source, target: shutil.copytree(source, target, symlinks=True)):
            with self.subTest(platform_clone=clone is None), tempfile.TemporaryDirectory() as root:
                source, target = Path(root) / 'source', Path(root) / 'qa'
                cache = source / MLX_SUFFIX / 'hub'
                (cache / 'blobs').mkdir(parents=True)
                (cache / 'snapshots').mkdir()
                blob = cache / 'blobs' / 'fixture'
                blob.write_text('source fixture')
                (cache / 'snapshots' / 'reference').symlink_to('../blobs/fixture')
                stage_cache(source, target, self.metadata, clone=clone)
                staged = target / MLX_SUFFIX / 'hub' / 'snapshots' / 'reference'
                self.assertTrue(staged.is_symlink())
                self.assertEqual(staged.readlink(), Path('../blobs/fixture'))
                self.assertTrue(staged.resolve().is_relative_to(target.resolve()))
                staged.write_text('QA write through preserved relative link')
                self.assertEqual(blob.read_text(), 'source fixture')

    def test_staging_refuses_relative_symlink_escape(self):
        import os
        for clone in (None, lambda source, target: shutil.copytree(source, target, symlinks=True)):
            with self.subTest(platform_clone=clone is None), tempfile.TemporaryDirectory() as root:
                source, target = Path(root) / 'source', Path(root) / 'qa'
                cache = source / MLX_SUFFIX / 'fish_drama3_4bit'
                cache.mkdir(parents=True)
                private = source / 'private'
                private.write_text('source fixture')
                (cache / 'escape').symlink_to(os.path.relpath(private, cache))
                with self.assertRaisesRegex(ValueError, 'symlink escapes'):
                    stage_cache(source, target, self.metadata, clone=clone)
                self.assertFalse(target.exists())
                self.assertEqual(private.read_text(), 'source fixture')

    def test_staging_rechecks_preserved_links_before_publication(self):
        with tempfile.TemporaryDirectory() as root:
            source, target = Path(root) / 'source', Path(root) / 'qa'
            cache = source / MLX_SUFFIX / 'fish_drama3_4bit'
            cache.mkdir(parents=True)
            blob = cache / 'blob'
            blob.write_text('source fixture')
            (cache / 'reference').symlink_to('blob')
            def changed_copy(origin, staged):
                shutil.copytree(origin, staged, symlinks=True)
                (staged / 'reference').unlink()
                (staged / 'reference').symlink_to(blob)
            with self.assertRaisesRegex(ValueError, 'absolute'):
                stage_cache(source, target, self.metadata, clone=changed_copy)
            self.assertFalse(target.exists())
            self.assertEqual(blob.read_text(), 'source fixture')


class ToolReceiptTest(unittest.TestCase):
    def test_qa_script_accepts_fresh_identity_and_refuses_unsafe_ids_before_staging(self):
        import subprocess
        prefix = 'com.kellyjanderson.readAloud.mlxPlaybackTest'
        with tempfile.TemporaryDirectory() as root:
            for identity in ('com.kellyjanderson.readAloud', prefix + '.bad/../path',
                             prefix + '..bad', prefix + '.', prefix + '.run-20261113-02'):
                with self.subTest(identity=identity):
                    result = subprocess.run(['sh', str(ROOT / 'tools/prepare_mlx_playback_test_app.sh'),
                                             str(Path(root) / 'missing.app'), str(Path(root) / 'qa.app'), identity],
                                            capture_output=True, text=True, check=False)
                    self.assertEqual(result.returncode, 2)
                    if identity.endswith('.run-20261113-02'):
                        self.assertIn('Source app must contain', result.stderr)
                    else:
                        self.assertIn('QA bundle ID', result.stderr)
                    self.assertFalse((Path(root) / 'qa.app').exists())

    def test_tools_only_complete_receipts_after_verified_shutdown(self):
        metadata = {'models': {'fixture': {'modelId': 'fixture', 'voiceKind': 'preset',
                    'voices': [{'id': 'voice'}], 'repo': 'fixture', 'revision': None}},
                    'workerSha256': 'fixture-only-no-weight-hash', 'voiceLibraries': [], 'runtime': {}}
        for tool in (mlx_tts_benchmark, qualify_voice_library):
            for succeeds in (True, False):
                with self.subTest(tool=tool.__name__, succeeds=succeeds), tempfile.TemporaryDirectory() as root:
                    corpus = Path(root) / 'corpus.txt'
                    corpus.write_text(' '.join(['word'] * 180))
                    output = Path(root) / 'output'
                    arguments = [tool.__name__, 'fixture', root]
                    if tool is mlx_tts_benchmark:
                        arguments.extend([str(corpus), str(output), '--voice', 'voice'])
                    else:
                        arguments.append(str(output))
                    client = fake('render' if succeeds else 'render_shutdown_nonzero')
                    client.metadata = lambda: metadata
                    with patch.object(tool, 'MlxClient', return_value=client), \
                            patch.object(tool, 'load_model', return_value={'modelIdentity': 'fixture'}), \
                            patch.object(sys, 'argv', arguments), patch('builtins.print'):
                        if succeeds:
                            tool.main()
                        else:
                            with self.assertRaises(ProtocolError):
                                tool.main()
                    receipt = json.loads((output / 'receipt.json').read_text())
                    self.assertIs(receipt['complete'], succeeds)
                    if succeeds:
                        self.assertEqual(receipt['workerExitCode'], 0)
                    self.assertTrue(client.closed)
                    self.assertIsNotNone(client.child.poll())


class VoiceDesignTest(unittest.TestCase):
    def test_consumes_all_outputs_and_closes_before_publication(self):
        import numpy as np
        state = []
        def generate():
            try:
                yield SimpleNamespace(audio=np.array([.1, .2]), sample_rate=24000)
                state.append('second')
                yield SimpleNamespace(audio=np.array([.3]), sample_rate=24000)
            finally:
                state.append('closed')
        audio, rate = complete_voice_design(generate())
        np.testing.assert_allclose(audio, [.1, .2, .3])
        self.assertEqual(rate, 24000)
        self.assertEqual(state, ['second', 'closed'])

    def test_late_failure_format_change_empty_and_nonfinite_refuse_prefix(self):
        import numpy as np
        def fail():
            yield SimpleNamespace(audio=[.1], sample_rate=24000)
            raise RuntimeError('late authoring failure')
        with self.assertRaisesRegex(RuntimeError, 'late authoring'):
            complete_voice_design(fail())
        for results in ([], [SimpleNamespace(audio=[], sample_rate=24000)],
                        [SimpleNamespace(audio=[np.nan], sample_rate=24000)],
                        [SimpleNamespace(audio=[.1], sample_rate=24000), SimpleNamespace(audio=[.2], sample_rate=48000)]):
            with self.subTest(results=results), self.assertRaises(ValueError):
                complete_voice_design(iter(results))


if __name__ == '__main__':
    unittest.main()
