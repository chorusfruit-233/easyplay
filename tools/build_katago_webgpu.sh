#!/usr/bin/env bash
# Build the fork's browser Search ABI as a separate, experimental artifact.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/.build/katago-webgpu"
SOURCE="${EASYPLAY_KATAGO_WEBGPU_SOURCE:-$CACHE/KataGo-WebGPU}"
EMSDK="${EASYPLAY_EMSDK_DIR:-$ROOT/.build/katago-web/emsdk}"
EIGEN="${EASYPLAY_EIGEN_SOURCE:-$ROOT/.build/katago-web/eigen}"
KATAGO_WEBGPU_REPO="https://github.com/saigo-online/katago-webgpu.git"
KATAGO_WEBGPU_COMMIT="d5ad1c0423dba989c60a2f06b1848e7eec2b5941"
EIGEN_COMMIT="3147391d946bb4b6c68edd901f2add6ac1f31f8c"
EMSDK_VERSION="6.0.3"
EMDAWN_VERSION="v20260423.175430"
MODE="${1:-mt}"
if [[ "$MODE" != mt && "$MODE" != single ]]; then
  echo "Usage: $0 [mt|single]" >&2
  exit 2
fi

mkdir -p "$CACHE"
if [[ ! -d "$EMSDK/.git" ]]; then
  git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$EMSDK"
fi
if [[ ! -d "$EIGEN/.git" ]]; then
  git clone --depth 1 --branch 3.4.0 https://gitlab.com/libeigen/eigen.git "$EIGEN"
fi
if [[ ! -d "$SOURCE/.git" ]]; then
  mkdir -p "$(dirname "$SOURCE")"
  git clone "$KATAGO_WEBGPU_REPO" "$SOURCE"
  git -C "$SOURCE" checkout --detach "$KATAGO_WEBGPU_COMMIT"
fi
for spec in "$SOURCE:$KATAGO_WEBGPU_COMMIT" "$EIGEN:$EIGEN_COMMIT"; do
  dir="${spec%%:*}"
  expected="${spec##*:}"
  if [[ "$(git -C "$dir" rev-parse HEAD)" != "$expected" ]] ||
     [[ -n "$(git -C "$dir" status --short)" ]]; then
    echo "Source must be clean and pinned at $expected: $dir" >&2
    exit 1
  fi
done

export EMSDK_QUIET=1
"$EMSDK/emsdk" install "$EMSDK_VERSION"
"$EMSDK/emsdk" activate "$EMSDK_VERSION"
# shellcheck disable=SC1091
source "$EMSDK/emsdk_env.sh" >/dev/null
if ! grep -Fq "_VERSION = '$EMDAWN_VERSION'" \
    "$EMSDK/upstream/emscripten/tools/ports/emdawnwebgpu.py"; then
  echo "Unexpected emdawnwebgpu port version for emsdk $EMSDK_VERSION" >&2
  exit 1
fi

BUILD="$CACHE/build-$MODE"
OUT="$ROOT/web/katago-webgpu"
mkdir -p "$BUILD/obj" "$OUT"
cd "$SOURCE/cpp"
MANIFESTS=(kataeval/sources.txt)
THREAD_FLAGS=()
LINK_THREADS=()
INITIAL_MEMORY=64MB
NAME=kataeval
EXPORTS=_kgeLoad,_kgeEval,_kgeEvalSeq,_kgeEvalBatch,_kgeSearch,_kgeSetGumbel,_kgeSetPolicyOptimism,_kgeError,_kgeBoardSize,_kgeModelVersion,_kgeBackendIsGpu,_kgeSetForceCpu,_kgeSetFp16,_malloc,_free
if [[ "$MODE" == mt ]]; then
  MANIFESTS+=(kataeval/sources-search.txt)
  THREAD_FLAGS=(-pthread -DKGE_THREADS)
  LINK_THREADS=(-pthread -sPTHREAD_POOL_SIZE=5)
  INITIAL_MEMORY=512MB
  NAME=kataeval-mt
  EXPORTS="${EXPORTS},_kgeSearchKata,_kgeEvalSeqKata,_kgeSearchBegin,_kgePollAll,_kgePonderBegin,_kgeStopSearch,_kgeSetStrength"
fi
mapfile -t SOURCES < <(cat "${MANIFESTS[@]}" | sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d')
OBJECTS=()
for file in "${SOURCES[@]}"; do
  object="$BUILD/obj/$(printf '%s' "$file" | tr '/.' '__').o"
  if [[ -s "$object" && "${EASYPLAY_WEBGPU_REBUILD:-0}" != 1 ]]; then
    OBJECTS+=("$object")
    continue
  fi
  standard=c++17
  optimization=-O2
  extra=()
  if [[ "$file" == kataeval/backend_gpu.cpp ]]; then
    standard=c++20
    # LLVM 23 in emsdk 6.0.3 crashes optimizing this large translation unit.
    optimization=-O0
  elif [[ "$file" == kataeval/backend_cpu.cpp ]]; then
    extra=(-DUSE_EIGEN_BACKEND -isystem "$EIGEN")
  fi
  emcc -c "$file" -o "$object" -std="$standard" "$optimization" -fexceptions -msimd128 \
    "${THREAD_FLAGS[@]}" -DNO_GIT_REVISION -DHALF_ENABLE_CPP11_CFENV=0 \
    -I external -isystem external/filesystem-1.5.8/include \
    --use-port=emdawnwebgpu -sUSE_ZLIB=1 "${extra[@]}"
  OBJECTS+=("$object")
done

emcc "${OBJECTS[@]}" -o "$OUT/$NAME.js" --use-port=emdawnwebgpu \
  -sUSE_ZLIB=1 -fexceptions -msimd128 "${LINK_THREADS[@]}" -sASYNCIFY \
  -sALLOW_MEMORY_GROWTH=1 -sFORCE_FILESYSTEM=1 -sSTACK_SIZE=16MB \
  -sINITIAL_MEMORY="$INITIAL_MEMORY" \
  -sMODULARIZE=1 -sEXPORT_NAME=createKata \
  -sEXPORTED_FUNCTIONS="$EXPORTS" \
  -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,FS,HEAPF32,HEAP32,UTF8ToString \
  -O2

if [[ "$MODE" == mt ]]; then
  # In emsdk 6.0.3 _scriptName otherwise points to kata-worker.js when the
  # module is loaded with importScripts, recursively spawning that wrapper.
  old='else if(ENVIRONMENT_IS_WORKER){_scriptName=self.location.href}'
  new='else if(ENVIRONMENT_IS_WORKER){_scriptName=self.__easyPlayPthreadScriptUrl||self.location.href}'
  if ! grep -Fq "$old" "$OUT/$NAME.js"; then
    echo "Emscripten pthread loader changed; update the worker bootstrap" >&2
    exit 1
  fi
  python3 - "$OUT/$NAME.js" "$old" "$new" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
path.write_text(source.replace(sys.argv[2], sys.argv[3], 1))
PY
fi

cat > "$OUT/build-info.txt" <<EOF
WebGPU fork: $KATAGO_WEBGPU_REPO@$KATAGO_WEBGPU_COMMIT
Eigen: $EIGEN_COMMIT
Emscripten: $EMSDK_VERSION
Emdawnwebgpu: $EMDAWN_VERSION
Interfaces: kataeval-mt (threaded Search ABI); kataeval (single-thread NN); neither is GTP
EOF
ls -lh "$OUT/$NAME.js" "$OUT/$NAME.wasm"
