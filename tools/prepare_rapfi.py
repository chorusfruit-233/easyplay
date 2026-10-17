#!/usr/bin/env python3
"""Verify bundled Rapfi code and fetch the pinned CC0 Renju networks."""
import argparse
import hashlib
from pathlib import Path
import os
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SOURCE_COMMIT = '1be1551ced57e38d53ed58f6d74bf6f8b4bdc230'
NETWORK_COMMIT = '918b757a129258e9e765f77fe17d507c2bb1a60b'
RESOURCES = {
    'config.toml': (None, 'f2f913c36dcff38fcb65ea5db61b1a990680a086129db951640c4ba8b351e72a'),
    'model210901.bin': ('classical/model210901.bin', '2fa08cb15cf240d9533548c3e011b03d46809f6858362e97ee873d0632aa2015'),
    'mix9svqrenju_bs15_black.bin.lz4': ('mix9svq/mix9svqrenju_bs15_black.bin.lz4', '7ab8c974c30da07717ce6a504616a62ac8c981500503f0ced0fadefd3f46c5ec'),
    'mix9svqrenju_bs15_white.bin.lz4': ('mix9svq/mix9svqrenju_bs15_white.bin.lz4', 'a31f318518d3b5630489054d9eb013fd5353c553999640c2bcfd8d95e6fe4e4e'),
}
CODE_SHA = {
    'android/app/src/main/jniLibs/arm64-v8a/librapfi.so': '056b57a4c7d3f9adf2eec7ed385e8746ff66eaa51c3eb0149aba71327079554a',
    'web/rapfi/rapfi-single-simd128.js': '97d953994fc8c12e8a135bdb4295fb43c5e3305c3e569a545de6bbf9570b8667',
    'web/rapfi/rapfi-single-simd128.wasm': 'b59b574131dd6f520bb281dd771529cfc1896a3cb68fc364426f895a3e7759d0',
    'web/rapfi/rapfi.js': '66ef60b5aa2e57ef8a81286eed29f932c5f5d3c6dd12bac06a01a84fbf801836',
}
DATA_SHA = 'a2dd6d845e8c190d73ef3f34af4392864d53a8c42d240e5c7bb725aa05760afa'


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--android-only', action='store_true')
    group.add_argument('--web-only', action='store_true')
    args = parser.parse_args()
    for name, expected in CODE_SHA.items():
        if args.android_only and name.startswith('web/'):
            continue
        if args.web_only and name.startswith('android/'):
            continue
        path = ROOT / name
        if not path.is_file() or digest(path) != expected:
            raise RuntimeError(f'Rapfi code checksum mismatch: {name}; see tools/build_rapfi.py')
    for name, (source, expected) in RESOURCES.items():
        target = ROOT / 'assets/rapfi' / name
        if target.is_file() and digest(target) == expected:
            continue
        if source is None:
            raise RuntimeError('Rapfi config checksum mismatch')
        print(f'Downloading pinned Rapfi network: {name}', flush=True)
        temporary = target.with_suffix(target.suffix + '.download')
        try:
            url = f'https://raw.githubusercontent.com/dhbloo/rapfi-networks/{NETWORK_COMMIT}/{source}'
            with urllib.request.urlopen(url, timeout=120) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            if digest(temporary) != expected:
                raise RuntimeError(f'Rapfi network checksum mismatch: {name}')
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
    if not args.android_only:
        target = ROOT / 'web/rapfi/rapfi-single-simd128.data'
        if not target.is_file() or digest(target) != DATA_SHA:
            temporary = target.with_suffix('.download')
            try:
                # Emscripten file_packager sorts the virtual paths. Exactly the
                # same bytes/offsets as the pinned JS metadata, no build tools.
                with temporary.open('wb') as output:
                    for name in sorted(RESOURCES):
                        with (ROOT / 'assets/rapfi' / name).open('rb') as source:
                            shutil.copyfileobj(source, output)
                if digest(temporary) != DATA_SHA:
                    raise RuntimeError('Rapfi Web data checksum mismatch')
                os.replace(temporary, target)
            finally:
                temporary.unlink(missing_ok=True)
    if not args.web_only:
        (ROOT / 'android/app/src/main/jniLibs/arm64-v8a/librapfi.so').chmod(0o755)
    print('Rapfi 250615: code and CC0 Renju networks verified', flush=True)


if __name__ == '__main__':
    main()
