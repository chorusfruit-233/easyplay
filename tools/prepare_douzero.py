#!/usr/bin/env python3
"""Verify bundled DouZero-WP models and fetch the pinned ONNX Runtime Web files."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
ORT_VERSION = '1.22.0'
ARCHIVE_SHA = 'e293551f9d36d003e293d0f2937fee7b3dfdcef76d71d1449b55e2d4157c7aea'
WEB_FILES = ('ort.wasm.min.js', 'ort-wasm-simd-threaded.mjs', 'ort-wasm-simd-threaded.wasm')


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--android-only', action='store_true')
    mode.add_argument('--web-only', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'assets/douzero/manifest.json').read_text())
    for role, info in manifest['models'].items():
        path = ROOT / 'assets/douzero' / info['file']
        if not path.is_file() or path.stat().st_size != info['bytes'] or digest(path) != info['sha256']:
            raise RuntimeError(f'DouZero model checksum mismatch: {role}; see tools/export_douzero.py')
    if not args.android_only:
        directory = ROOT / 'web/douzero'
        checksums = json.loads((directory / 'runtime-manifest.json').read_text())
        if any(not (directory / name).is_file() or digest(directory / name) != checksums[name] for name in WEB_FILES):
            url = f'https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-{ORT_VERSION}.tgz'
            data = urllib.request.urlopen(url, timeout=120).read()
            if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA:
                raise RuntimeError('ONNX Runtime archive checksum mismatch')
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
                for name in WEB_FILES:
                    contents = archive.extractfile(f'package/dist/{name}').read()
                    if hashlib.sha256(contents).hexdigest() != checksums[name]:
                        raise RuntimeError(f'ONNX Runtime file checksum mismatch: {name}')
                    path = directory / name
                    temporary = path.with_suffix(path.suffix + '.download')
                    temporary.write_bytes(contents)
                    os.replace(temporary, path)
    print('DouZero-WP models and ONNX Runtime 1.22.0 verified', flush=True)


if __name__ == '__main__':
    main()
