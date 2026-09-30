#!/usr/bin/env python3
"""Fetch and verify pinned Stockfish 19 Android and Web release assets.

No floating branches: tag, source commit, archive and executable SHA-256 are
recorded here. The APK packs a native executable as libstockfish.so so Android
extracts it into its executable nativeLibraryDir, not app-writable storage.
"""
import argparse
import hashlib
import os
from pathlib import Path
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
NATIVE_COMMIT = 'edb0d9db6731067ec50ce619ff372b463bc4dd5d'
WEB_COMMIT = '9cb3e5066d48f1a35d792afeda36eff37ae60570'
ANDROID_URL = 'https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-arm64-universal.tar.gz'
ARCHIVE_SHA = 'ebb24051aa4a222b4daaf049b882ecf1163d370c128fe02316602643f4d5e426'
BINARY_SHA = 'ffd8fc2004d3d19f9fdab95d84c92709aea92e8d3af405eda0b281b23cf1daf8'
WEB_SHA = {
    'stockfish-19-lite-single.js': 'd3344124ab067fb0b90ee77873bb8e9fbf5fc01bc525fe714b0f942581e889e6',
    'stockfish-19-lite-single.wasm': '57ac2d72312aba346760e3f173f687a8c211208e97a87268436f7f0e10bb5387',
}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def prepare_android():
    target = ROOT / 'android/app/src/main/jniLibs/arm64-v8a/libstockfish.so'
    if target.exists() and digest(target) == BINARY_SHA:
        target.chmod(0o755)
        return
    with tempfile.TemporaryDirectory(prefix='easyplay-stockfish-') as folder:
        archive = Path(folder) / 'stockfish.tar.gz'
        print('Downloading pinned Stockfish 19 ARM64 release', flush=True)
        with urllib.request.urlopen(ANDROID_URL, timeout=120) as response, archive.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        if digest(archive) != ARCHIVE_SHA:
            raise RuntimeError('Stockfish release archive checksum mismatch')
        with tarfile.open(archive) as tar:
            source = tar.extractfile('stockfish/stockfish-android-arm64-universal')
            if source is None:
                raise RuntimeError('Stockfish executable absent from archive')
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix('.download')
            with temporary.open('wb') as output:
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)
            if digest(temporary) != BINARY_SHA:
                temporary.unlink()
                raise RuntimeError('Stockfish executable checksum mismatch')
            temporary.chmod(0o755)
            os.replace(temporary, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web-only', action='store_true')
    args = parser.parse_args()
    for name, expected in WEB_SHA.items():
        path = ROOT / 'web/stockfish' / name
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            url = f'https://github.com/nmrugg/stockfish.js/releases/download/v19.0.0/{name}'
            with urllib.request.urlopen(url, timeout=120) as response:
                path.write_bytes(response.read())
        if digest(path) != expected:
            raise RuntimeError(f'Bundled Web engine checksum mismatch: {name}')
    if not args.web_only:
        prepare_android()
    print('Stockfish 19 assets verified')


if __name__ == '__main__':
    main()
