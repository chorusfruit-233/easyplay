#!/usr/bin/env python3
"""Independently verify fixed Asian repetition cases with the pinned C++ rules."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request
from build_pikafish_web import SOURCE_COMMIT, SOURCE_ARCHIVE_SHA

ROOT = Path(__file__).resolve().parent.parent
CASES = [
    ('long check', '4k4/3R5/9/9/9/4P4/9/9/9/4K4 w - - 0 1', 'd8e8 e9d9 e8d8 d9e9', -32000),
    ('long chase', '4k4/9/9/9/9/3nP4/1R7/9/9/4K4 w - - 0 1', 'b3d3 d4b5 d3b3 b5d4', -32000),
    ('mixed check', '4k4/3R5/9/9/9/4P4/9/9/9/4K4 w - - 0 1', 'd8e8 e9d9 e8e7 d9d8 e7d7 d8e8 d7d8 e8e9', 0),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='Unmodified pinned src directory')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='easyplay-pikafish-oracle-') as temporary:
        folder = Path(temporary)
        source = args.source
        if source is None:
            archive = folder / 'source.tar.gz'
            url = f'https://codeload.github.com/official-pikafish/Pikafish/tar.gz/{SOURCE_COMMIT}'
            with urllib.request.urlopen(url, timeout=120) as response:
                archive.write_bytes(response.read())
            if hashlib.sha256(archive.read_bytes()).hexdigest() != SOURCE_ARCHIVE_SHA:
                raise RuntimeError('Pikafish source checksum mismatch')
            with tarfile.open(archive) as tar:
                tar.extractall(folder, filter='data')
            source = folder / f'Pikafish-{SOURCE_COMMIT}' / 'src'
        executable = folder / 'judge'
        files = ['position', 'attacks', 'bitboard', 'misc', 'memory', 'tt', 'movegen', 'nnue/features/half_ka_v2_hm']
        subprocess.run(['g++', '-O2', '-std=c++17', '-DIS_64BIT', '-DUSE_POPCNT',
            '-DNNUE_EMBEDDING_OFF', '-ffunction-sections', '-fdata-sections', '-pthread',
            '-Wl,--gc-sections', '-I', str(source), str(ROOT / 'tools/pikafish_rule_oracle.cpp'),
            *[str(source / (name + '.cpp')) for name in files], '-o', str(executable)], check=True)
        for name, fen, cycle, expected in CASES:
            result = subprocess.run([str(executable)], input=f'{fen}\n{cycle} {cycle}\n',
                capture_output=True, text=True, check=True).stdout.split()
            if result[:3] != ['valid', '1', str(expected)]:
                raise RuntimeError(f'{name}: unexpected native verdict {result}')
            print(f'PASS pinned Asian rule oracle: {name}')


if __name__ == '__main__':
    main()
