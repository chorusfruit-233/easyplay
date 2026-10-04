#!/usr/bin/env python3
"""Build the pinned Pikafish in one cooperative Worker without shared memory.

GPL-3.0-or-later. Upstream sources remain authoritative for AI search; these
patches replace native scheduling/stdio only, yielding with Asyncify for stop.
"""
import argparse
import concurrent.futures
from pathlib import Path
import hashlib
import tarfile
import tempfile
import urllib.request
import subprocess


def patch(source):
    # Numa jobs also use NativeThread: execute them inline in a single Worker.
    native = source / 'thread_native.h'
    original = native.read_text()
    original = original[:original.index('#ifndef THREAD_NATIVE_H_INCLUDED')]
    native.write_text(original + '''#pragma once
#include <functional>
#include <utility>
namespace Stockfish {
struct NativeThreadOptions { NativeThreadOptions& setLargeStack(bool) { return *this; } };
struct NativeThread { bool joinable() const { return true; } void join() {} };
template<class F, class... A> NativeThread create_native_thread(NativeThreadOptions, F&& f, A&&... a) {
    std::invoke(std::forward<F>(f), std::forward<A>(a)...); return {};
}
}
''')
    thread = source / 'thread.cpp'
    text = thread.read_text()
    start = text.index('Thread::Thread(')
    end = text.index('Search::SearchManager* ThreadPool::main_manager()', start)
    text = text[:start] + '''Thread::Thread(Search::SharedState& sharedState,
 std::unique_ptr<Search::ISearchManager> sm, usize n, usize numaN,
 usize totalNumaCount, OptionalThreadToNumaNodeBinder binder)
 : idx(n), idxInNuma(numaN), totalNuma(totalNumaCount), nthreads(1) {
    searching = false;
    numaAccessToken = binder();
    worker = make_unique_large_page<Search::Worker>(sharedState, std::move(sm), n, idxInNuma, totalNuma, numaAccessToken);
}
Thread::~Thread() = default;
void Thread::start_searching() { run_custom_job([this] { worker->start_searching(); }); }
void Thread::clear_worker() { run_custom_job([this] { worker->clear(); }); }
void Thread::wait_for_search_finished() {}
void Thread::run_custom_job(std::function<void()> f) { searching = true; f(); searching = false; }
void Thread::idle_loop() {}
void Thread::ensure_network_replicated() { worker->ensure_network_replicated(); }

''' + text[end:]
    thread.write_text(text)
    uci = source / 'uci.cpp'
    text = uci.read_text()
    text = '#include <emscripten.h>\n' + text
    index = text.index('namespace Stockfish {')
    text = text[:index] + '''EM_JS(int, easyplay_command, (char* buffer, int capacity), {
  var next = Module.easyplayCommands.shift();
  if (next === undefined) return 0;
  if (next.startsWith('go ')) Module.easyplayStop = false;
  stringToUTF8(next, buffer, capacity); return 1;
});
''' + text[index:]
    start = text.index('        if (cli.argc == 1\n')
    end = text.index('\n        currentCmd = cmd;', start)
    text = text[:start] + '''        if (cli.argc == 1) {
            static char input[131072];
            while (!easyplay_command(input, sizeof(input))) emscripten_sleep(10);
            cmd = input;
        }
''' + text[end:]
    # Forbid resizing beyond this single cooperative worker.
    text = text.replace('            setoption(is);', '''        {
            if (cmd.find("name Threads value") == std::string::npos) setoption(is);
        }''')
    uci.write_text(text)
    search = source / 'search.cpp'
    text = '#include <emscripten.h>\nEM_JS(int, easyplay_stopped, (), { return Module.easyplayStop ? 1 : 0; });\n' + search.read_text()
    text = text.replace('void SearchManager::check_time(Search::Worker& worker) {', '''void SearchManager::check_time(Search::Worker& worker) {
    static double lastYield = 0;
    if (emscripten_get_now() - lastYield >= 8) {
        emscripten_sleep(0); lastYield = emscripten_get_now();
        if (easyplay_stopped()) worker.threads.stop = true;
    }
''')
    text = text.replace('while (!threads.stop && (main_manager()->ponder || limits.infinite))\n    {}', '''while (!threads.stop && (main_manager()->ponder || limits.infinite)) {
        emscripten_sleep(10);
        if (easyplay_stopped()) threads.stop = true;
    }''')
    search.write_text(text)


SOURCE_COMMIT = '4c17cee11f888ae1d48a9494f2e2239f019f0a1f'
SOURCE_ARCHIVE_SHA = 'dde6748080072b0fc9152eb8e559bd9f1db6cb22d8242db7f87c2066f2c2e366'
SOURCE_TREE_SHA = '854b0f1e0f2b6a7c446e3d1bcd80902c75f91bfdbb3d8f09ceafbccbf2457510'


def build(source, emxx, output, jobs=4):
    fingerprint = hashlib.sha256()
    for file in sorted(source.rglob('*')):
        if file.is_file():
            fingerprint.update(str(file.relative_to(source)).encode() + b'\0' + file.read_bytes() + b'\0')
    if fingerprint.hexdigest() != SOURCE_TREE_SHA:
        raise RuntimeError('Use a clean, unmodified copy of the pinned Pikafish source')

    output.mkdir(parents=True, exist_ok=True)
    patch(source)
    objects = source.parent / 'easyplay-wasm-objects'
    objects.mkdir(exist_ok=True)
    flags = ['-O3', '-std=c++17', '-DNDEBUG', '-DIS_64BIT', '-DUSE_POPCNT',
             '-DUSE_SLOPPY_ATOMICS', '-DNNUE_EMBEDDING_OFF', '-msimd128', '-fno-exceptions']
    def compile_file(file):
        obj = objects / (str(file.relative_to(source)).replace('/', '_') + '.o')
        subprocess.run([str(emxx), *flags, '-I', str(source), '-c', str(file), '-o', str(obj)], check=True)
        return obj
    sources = sorted(f for f in source.rglob('*.cpp') if 'universal' not in f.parts)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        compiled = list(pool.map(compile_file, sources))
    subprocess.run([str(emxx), '-O3', *map(str,compiled), '-o', str(output / 'pikafish-core.js'),
        '-sASYNCIFY', '-sASYNCIFY_STACK_SIZE=1048576', '-sSTACK_SIZE=8388608',
        '-sINITIAL_MEMORY=134217728', '-sALLOW_MEMORY_GROWTH', '-sMAXIMUM_MEMORY=1073741824',
        '-sENVIRONMENT=worker', '-sEXPORTED_RUNTIME_METHODS=FS,stringToUTF8',
        '-sFILESYSTEM=1', '-sASSERTIONS=1'], check=True)

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,help='Clean pinned src directory; omitted downloads the verified commit')
    parser.add_argument('--emxx',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=Path('web/pikafish'))
    parser.add_argument('--jobs',type=int,default=4)
    args=parser.parse_args()
    if args.source:
        build(args.source.resolve(), args.emxx.resolve(), args.output.resolve(), args.jobs)
    else:
        with tempfile.TemporaryDirectory(prefix='easyplay-pikafish-source-') as temporary:
            folder = Path(temporary)
            url = f'https://codeload.github.com/official-pikafish/Pikafish/tar.gz/{SOURCE_COMMIT}'
            archive = folder / 'source.tar.gz'
            with urllib.request.urlopen(url, timeout=120) as response:
                archive.write_bytes(response.read())
            if hashlib.sha256(archive.read_bytes()).hexdigest() != SOURCE_ARCHIVE_SHA:
                raise RuntimeError('Pikafish source archive checksum mismatch')
            with tarfile.open(archive) as tar:
                tar.extractall(folder, filter='data')
            source = folder / f'Pikafish-{SOURCE_COMMIT}' / 'src'
            build(source, args.emxx.resolve(), args.output.resolve(), args.jobs)
