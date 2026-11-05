"""Bounded, offline ModernBookNLP evaluation worker; no playback or voice writer.

One JSON request on stdin, one JSON reply, then exit. The Dart owner can terminate
and reap it out of band. Production default promotion remains a separate gate.
"""
from __future__ import annotations
import contextlib
import csv
import hashlib
import json
import os
from pathlib import Path
import resource
import sys
import tempfile
import time

UPSTREAM = '84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b'
ADAPTER_VERSION = 'readaloud-cpu-1'
MAX_UTF16 = 16384
MAX_TOKENS = 4096
MAX_OUTPUT = 1024 * 1024


def utf16_offset(text, position):
    if not 0 <= position <= len(text):
        raise ValueError('Provider offset outside source')
    return len(text[:position].encode('utf-16-le')) // 2


def validate_request(request):
    if request.get('schema') != 1:
        raise ValueError('Unsupported provider request')
    for key in ('requestId', 'ownerId', 'workId', 'sourceRevision'):
        if not isinstance(request.get(key), str) or not request[key] or len(request[key]) > 512:
            raise ValueError('Missing/bounded identity: ' + key)
    for key in ('analysisRevision', 'sequence'):
        if type(request.get(key)) is not int or request[key] < 0:
            raise ValueError('Invalid revision: ' + key)
    text = request.get('text')
    if not isinstance(text, str) or not text or utf16_offset(text, len(text)) > MAX_UTF16:
        raise ValueError('Source window must contain 1..16384 UTF-16 units')
    return text


def read_rows(path):
    with path.open(encoding='utf-8', newline='') as file:
        return list(csv.DictReader(file, delimiter='\t', quoting=csv.QUOTE_NONE))


def decode_outputs(directory, text):
    tokens = read_rows(directory / 'window.tokens')
    if len(tokens) > MAX_TOKENS:
        raise ValueError('Provider exceeded admitted token bound')
    spans = {}
    for token in tokens:
        start, end = int(token['byte_onset']), int(token['byte_offset'])
        # Upstream calls these bytes but spaCy actually supplies codepoint indices.
        if text[start:end] != token['word']:
            raise ValueError('Provider token does not match original source')
        spans[int(token['token_ID_within_document'])] = (
            utf16_offset(text, start), utf16_offset(text, end))
    def span(start, end):
        a, b = spans[int(start)][0], spans[int(end)][1]
        if b <= a:
            raise ValueError('Invalid provider token range')
        return {'startUtf16': a, 'endUtf16': b}
    entities = {}
    for row in read_rows(directory / 'window.entities'):
        if row['cat'] != 'PER':
            continue
        entity = entities.setdefault(row['COREF'], {'entityId': row['COREF'], 'mentions': []})
        entity['mentions'].append({**span(row['start_token'], row['end_token']),
                                   'text': row['text'], 'proper': row['prop'] == 'PROP'})
    quotes = []
    for row in read_rows(directory / 'window.quotes'):
        entity_id = row['char_id'] if row['char_id'] in entities else None
        quotes.append({**span(row['quote_start'], row['quote_end']),
                       'entityId': entity_id, 'confidence': None})
    return {'entities': list(entities.values()), 'quotes': quotes, 'tokenCount': len(tokens)}


def load_pipeline(root):
    manifest = json.loads((root / 'runtime.json').read_text())
    catalog = json.loads(Path(__file__).with_name('modernbooknlp_models.json').read_text())
    if (manifest.get('upstream') != UPSTREAM or manifest.get('schema') != 1
            or manifest.get('runtimePatchSha256') != catalog['runtimePatchSha256']):
        raise ValueError('Unsupported provider runtime')
    # Validate every component before importing constructors which otherwise fetch.
    # The application-owned installer records the hashes from its pinned artifacts.
    for relative, digest in manifest['sha256'].items():
        path = (root / relative).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError('Missing provider artifact: ' + relative)
        with path.open('rb') as file:
            if hashlib.file_digest(file, 'sha256').hexdigest() != digest:
                raise ValueError('Provider artifact changed: ' + relative)
    os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
                      TOKENIZERS_PARALLELISM='false', READALOUD_BOOKNLP_HOME=str(root),
                      READALOUD_MODERNBERT=str(root / manifest['encoder']),
                      READALOUD_ENTITY_ENCODER=str(root / manifest['entityEncoder']),
                      READALOUD_COREF_ENCODER=str(root / manifest['corefEncoder']))
    import importlib.util
    package = importlib.util.find_spec('booknlp')
    if package is None or package.origin is None:
        raise ValueError('Install the pinned provider runtime first')
    package_root = Path(package.origin).parent
    for relative, expected in catalog['patchedModules'].items():
        if hashlib.sha256((package_root / relative).read_bytes()).hexdigest() != expected:
            raise ValueError('Provider CPU adapter differs from pinned runtime')
    import torch
    torch.set_num_threads(4)
    from booknlp.english.english_booknlp import EnglishBookNLP
    pipeline = EnglishBookNLP({'pipeline': 'entity,quote,coref', 'model': 'big',
                              'modern_qa': True, 'direct_qa': False,
                              'model_path': str(root / 'booknlp_models'),
                              'spacy_model': 'en_core_web_sm'})
    if pipeline.quote_attrib.device != 'cpu':
        raise ValueError('Only CPU is qualified by this evaluation runner')
    return pipeline, manifest


def analyze(pipeline, request):
    text = validate_request(request)
    # Tokenization is part of admission, before quadratic graph/model work.
    if len(pipeline.tagger.tag(text)) > MAX_TOKENS:
        raise ValueError('Source exceeds 4096 upstream tokens')
    with tempfile.TemporaryDirectory(prefix='readaloud-nlp-') as temporary:
        directory = Path(temporary)
        source = directory / 'source.txt'
        source.write_text(text, encoding='utf-8')
        # Upstream writes debug pickles relative to cwd. Confine them to this
        # request's disposable directory rather than modifying the library.
        (directory / 'examples').mkdir()
        previous = Path.cwd()
        try:
            os.chdir(directory)
            pipeline.process(str(source), str(directory / 'output'), 'window')
        finally:
            os.chdir(previous)
        return decode_outputs(directory / 'output', text)


def main():
    protocol = sys.stdout
    request = {}
    try:
        raw = sys.stdin.buffer.readline(128 * 1024 + 1)
        if len(raw) > 128 * 1024:
            raise ValueError('Request too large')
        request = json.loads(raw)
        validate_request(request)
        started = time.monotonic()
        with contextlib.redirect_stdout(sys.stderr):
            pipeline, manifest = load_pipeline(Path(sys.argv[1]).resolve())
            loaded = time.monotonic()
            result = analyze(pipeline, request)
        reply = {key: request[key] for key in ('requestId', 'ownerId', 'workId', 'sourceRevision', 'analysisRevision', 'sequence')}
        reply.update(schema=1, ok=True, providerId='modernbooknlp-joint', providerVersion=UPSTREAM,
                     modelIdentity=manifest['modelIdentity'], adapterVersion=ADAPTER_VERSION, **result,
                     loadSeconds=loaded-started, inferenceSeconds=time.monotonic()-loaded,
                     peakRssBytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * (1 if sys.platform == 'darwin' else 1024))
    except Exception as error:
        reply = {'schema': 1, 'requestId': request.get('requestId'), 'ok': False,
                 'error': f'{type(error).__name__}: {error}'}
        import traceback
        traceback.print_exc(file=sys.stderr)
    encoded = json.dumps(reply)
    if len(encoded.encode()) > MAX_OUTPUT:
        encoded = json.dumps({'ok': False, 'requestId': request.get('requestId'), 'error': 'Provider output exceeded bound'})
    protocol.write(encoded + '\n')
    protocol.flush()


if __name__ == '__main__':
    main()
