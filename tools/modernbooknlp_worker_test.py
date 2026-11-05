import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys

spec=importlib.util.spec_from_file_location('provider',Path(__file__).resolve().parents[1]/'assets/modernbooknlp_worker.py')
provider=importlib.util.module_from_spec(spec);spec.loader.exec_module(provider)

class ProtocolTests(unittest.TestCase):
    def test_request_bounds_and_identity(self):
        value=dict(schema=1,requestId='r',ownerId='o',workId='w',sourceRevision='s',analysisRevision=1,sequence=1,text='hello')
        self.assertEqual(provider.validate_request(value),'hello')
        for key,bad in [('text','😀'*8193),('sequence',True),('ownerId','')]:
            with self.assertRaises(ValueError): provider.validate_request({**value,key:bad})
    def test_utf16_mapping_and_unknown(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/'window.tokens').write_text('token_ID_within_document\tword\tbyte_onset\tbyte_offset\n0\t😀\t0\t1\n1\tAda\t2\t5\n2\tHi\t6\t8\n')
            (root/'window.entities').write_text('COREF\tstart_token\tend_token\tprop\tcat\ttext\n8\t1\t1\tPROP\tPER\tAda\n')
            (root/'window.quotes').write_text('quote_start\tquote_end\tchar_id\n2\t2\tNone\n')
            (root/'window.book').write_text('{"characters": []}')
            result=provider.decode_outputs(root,'😀 Ada Hi')
            self.assertEqual(result['linguisticArtifacts']['pipeline'], 'entity,quote,coref')
            self.assertEqual(set(result['linguisticArtifacts']['files']), {'tokens','entities','quotes','book'})
            self.assertEqual(result['entities'][0]['mentions'][0]['startUtf16'],3)
            self.assertIsNone(result['quotes'][0]['entityId'])
            self.assertIsNone(result['quotes'][0]['confidence'])
            self.assertEqual(result['quotes'][0]['endUtf16'],9)
            with self.assertRaises(ValueError):provider.decode_outputs(root,'😀 Eve Hi')
    def test_missing_assets_fail_before_model_import(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(FileNotFoundError):provider.load_pipeline(Path(temporary))
        self.assertNotIn('torch',sys.modules)

if __name__=='__main__':unittest.main()
