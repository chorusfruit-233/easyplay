#!/usr/bin/env python3
"""Build Rapfi's bundled Android/Web code from checksum-pinned complete source.

Requirements: CMake, Ninja; Android NDK r28c for --android, Emsdk 3.1.64
activated on PATH for --web. prepare_rapfi.py supplies the pinned CC0 networks.
See docs/RAPFI.md for flags, licenses, and the small single-thread source patch.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

from prepare_rapfi import ROOT, SOURCE_COMMIT, RESOURCES

SOURCE_SHA = '22e7ab8f4ce850ff1efd95e6a0a287d977dd66e5b2068e05fd38fb3a51d38efd'


def run(command):
    subprocess.run([str(arg) for arg in command], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--android', action='store_true')
    parser.add_argument('--web', action='store_true')
    parser.add_argument('--ndk', type=Path, help='Android NDK r28c directory')
    parser.add_argument('--work', type=Path, default=ROOT / 'build/rapfi-source')
    args = parser.parse_args()
    if not args.android and not args.web:
        parser.error('Select --android and/or --web')
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    archive = work / 'source.tar.gz'
    if not archive.exists():
        urllib.request.urlretrieve(f'https://codeload.github.com/dhbloo/rapfi/tar.gz/{SOURCE_COMMIT}', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SOURCE_SHA:
        raise RuntimeError('Rapfi source checksum mismatch')
    source = work / f'rapfi-{SOURCE_COMMIT}'
    if source.exists():
        shutil.rmtree(source)
    with tarfile.open(archive) as package:
        package.extractall(work, filter='data')
    cpp = source / 'Rapfi/search/searchthread.cpp'
    old = '''    // Iterate all other threads and wait for them to finish
    for (auto &th : *this)
        if (th->thread.get_id() != std::this_thread::get_id())
            th->waitForIdle();'''
    new = '''#ifdef MULTI_THREADING
    // The single-thread build has no thread member and is already idle here.
    for (auto &th : *this)
        if (th->thread.get_id() != std::this_thread::get_id())
            th->waitForIdle();
#endif'''
    text = cpp.read_text()
    if text.count(old) != 1:
        raise RuntimeError('Rapfi single-thread patch no longer applies')
    cpp.write_text(text.replace(old, new))
    networks = source / 'Networks'
    networks.mkdir(exist_ok=True)
    for name in RESOURCES:
        shutil.copyfile(ROOT / 'assets/rapfi' / name, networks / name)
    (networks / 'wasm_preloads.txt').write_text(''.join(f'{name}@/{name}\n' for name in RESOURCES))
    common = ['-G', 'Ninja', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
              '-DCMAKE_BUILD_TYPE=Release', '-DNO_COMMAND_MODULES=ON',
              '-DNO_MULTI_THREADING=ON', '-DUSE_SSE=OFF', '-DUSE_AVX2=OFF',
              '-DUSE_AVX512=OFF', '-DUSE_BMI2=OFF', '-DUSE_VNNI=OFF',
              '-DUSE_NEON_DOTPROD=OFF', '-DUSE_WASM_SIMD_RELAXED=OFF']
    if args.android:
        ndk = args.ndk or Path(os.environ.get('ANDROID_NDK_HOME', ''))
        if not (ndk / 'build/cmake/android.toolchain.cmake').is_file():
            parser.error('--ndk must identify Android NDK r28c')
        build = work / 'android'
        run(['cmake', '-S', source / 'Rapfi', '-B', build, *common,
             f'-DCMAKE_TOOLCHAIN_FILE={ndk}/build/cmake/android.toolchain.cmake',
             '-DANDROID_ABI=arm64-v8a', '-DANDROID_PLATFORM=android-21',
             '-DANDROID_STL=c++_static', '-DUSE_NEON=ON',
             '-DCMAKE_EXE_LINKER_FLAGS=-Wl,-z,max-page-size=16384'])
        run(['cmake', '--build', build, '-j', '3'])
        binary = ROOT / 'android/app/src/main/jniLibs/arm64-v8a/librapfi.so'
        shutil.copyfile(build / 'pbrain-rapfi', binary)
        strip = next((ndk / 'toolchains/llvm/prebuilt').glob('*/bin/llvm-strip*'))
        run([strip, binary])
        binary.chmod(0o755)
    if args.web:
        build = work / 'web'
        run(['emcmake', 'cmake', '-S', source / 'Rapfi', '-B', build, *common,
             '-DUSE_WASM_SIMD=ON', '-DUSE_NEON=OFF'])
        run(['cmake', '--build', build, '-j', '3'])
        for suffix in ['js', 'wasm', 'data']:
            name = f'rapfi-single-simd128.{suffix}'
            shutil.copyfile(build / name, ROOT / 'web/rapfi' / name)
    print('Built pinned Rapfi source. Review output hashes before updating CODE_SHA.')


if __name__ == '__main__':
    main()
