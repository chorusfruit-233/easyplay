#!/usr/bin/env python3
"""Prepare checksum-pinned official Pikafish native/model and bundled Web build."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SOURCE_COMMIT = '4c17cee11f888ae1d48a9494f2e2239f019f0a1f'
RELEASE = 'Pikafish-2026-09-06'
URL = f'https://github.com/official-pikafish/Pikafish/releases/download/{RELEASE}/Pikafish.2026-09-06.7z'
ARCHIVE_SHA = '41952bbfe2520faceb5902c69e6ab4845cc999841d2b49a95cc1be7867a25e5b'
BINARY_SHA = '6c06b8752e10c1ed605fa836d2c9bbf885e9c402b216023040ddf4586f4320b1'
NNUE_SHA = '7d13d73569a9b571ba0eb20cf1596247bc2a42738967e61afef6482b231e900e'
WEB_SHA = {'pikafish-core.wasm': '6e6bcb8702b726cf2c772511ce825c63957d4f12858cc63dfe125eac4eb7377a', 'pikafish-core.js': '969ddd8e9f479a76100bbb7bea799db6080a3df07f046b9d80dc3b7794fff51f', 'pikafish.js': 'ab6899101c2447dd22f7f69751a978eea638be42aea41cbdf92ccbdc6f1a0969'}


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--android-only', action='store_true')
    group.add_argument('--web-only', action='store_true')
    args = parser.parse_args()
    targets = [(ROOT / 'assets/pikafish/pikafish.nnue', 'pikafish.nnue', NNUE_SHA)]
    if not args.android_only:
        targets.append((ROOT / 'web/pikafish/pikafish.nnue', 'pikafish.nnue', NNUE_SHA))
        for name, expected in WEB_SHA.items():
            path = ROOT / 'web/pikafish' / name
            if not path.exists() or digest(path) != expected:
                raise RuntimeError(f'Bundled Pikafish Web build checksum mismatch: {name}')
    if not args.web_only:
        targets.append((ROOT / 'android/app/src/main/jniLibs/arm64-v8a/libpikafish.so', 'Pikafish-Android-arm64-universal', BINARY_SHA))
    missing = [(target, name, sha) for target, name, sha in targets if not target.exists() or digest(target) != sha]
    if missing:
        extractor = shutil.which('7z') or shutil.which('7zz')
        if not extractor:
            raise RuntimeError('Install 7zip (7z or 7zz) to extract the official release')
        with tempfile.TemporaryDirectory(prefix='easyplay-pikafish-') as folder:
            folder = Path(folder)
            archive = folder / 'release.7z'
            print(f'Downloading {RELEASE}', flush=True)
            with urllib.request.urlopen(URL, timeout=120) as response, archive.open('wb') as output:
                shutil.copyfileobj(response, output)
            if digest(archive) != ARCHIVE_SHA:
                raise RuntimeError('Pikafish release archive checksum mismatch')
            subprocess.run([extractor, 'x', str(archive), f'-o{folder / "release"}', '-y'], check=True, stdout=subprocess.DEVNULL)
            for target, name, expected in missing:
                source = folder / 'release' / name
                if digest(source) != expected:
                    raise RuntimeError(f'Pikafish asset checksum mismatch: {name}')
                target.parent.mkdir(parents=True, exist_ok=True)
                temporary = target.with_suffix('.download')
                shutil.copyfile(source, temporary)
                os.replace(temporary, target)
    if not args.web_only:
        (ROOT / 'android/app/src/main/jniLibs/arm64-v8a/libpikafish.so').chmod(0o755)
    print(f'{RELEASE}: native/model/Web resources verified')


if __name__ == '__main__':
    main()
