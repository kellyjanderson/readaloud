"""Measured byte callbacks without network; optional real pinned-cache check."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'assets'))
import modernbooknlp_assets as assets


class AcquisitionTests(unittest.TestCase):
    def test_disabled_terminal_bar_still_reports_completed_download_bytes(self):
        from huggingface_hub import file_download
        original = file_download._get_progress_bar_context
        payload = b'abcd'
        checksum = hashlib.sha256(payload).hexdigest()
        name = 'ModernBERT_T2000.safetensors'
        repositories = [dict(repo=role, role=role, revision='fixed', files={name: checksum})
                        for role in ('qa', 'encoder', 'entityEncoder', 'corefEncoder')]
        catalog = dict(repositories=repositories, booknlp=[], upstream='fixed', runtimePatchSha256={})
        events = []
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            helper = root / 'modernbooknlp_assets.py'
            helper.with_name('modernbooknlp_models.json').write_text(json.dumps(catalog))
            def snapshot(**kwargs):
                if kwargs.get('local_files_only'):
                    raise FileNotFoundError('Cache miss')
                path = root / kwargs['repo_id']
                path.mkdir()
                # log_level=0 disables tqdm; a two-byte resume prefix is real work.
                with file_download._get_progress_bar_context(
                    desc=name, log_level=0, total=4, initial=2,
                ) as bar:
                    self.assertTrue(bar.disable)
                    bar.update(1)
                    bar.update(1)
                (path / name).write_bytes(payload)
                return str(path)
            with patch.object(assets, '__file__', str(helper)), patch(
                'huggingface_hub.snapshot_download', side_effect=snapshot,
            ):
                assets.prepare(root, progress=lambda **event: events.append(event))
        downloaded = [event for event in events if event['stage'] == 'download']
        self.assertEqual([event['completed'] for event in downloaded], [3, 4] * 4)
        self.assertTrue(all(event['total'] == 4 for event in downloaded))
        self.assertIs(file_download._get_progress_bar_context, original)

    def test_offline_reuse_never_falls_back_to_network(self):
        from huggingface_hub import snapshot_download
        root = Path.home() / 'Library/Application Support/ReadAloudProviderQA/modernbooknlp'
        if not (root / 'runtime.json').exists():
            self.skipTest('Optional pinned local model cache')
        events = []
        def local(**kwargs):
            self.assertTrue(kwargs.get('local_files_only'))
            return snapshot_download(**kwargs)
        with patch('huggingface_hub.snapshot_download', side_effect=local):
            assets.prepare(root, offline=True, progress=lambda **event: events.append(event))
        self.assertEqual(events[-1]['completed'], events[-1]['total'])
        self.assertTrue(all(event['completed'] <= event['total'] for event in events))


if __name__ == '__main__':
    unittest.main()
