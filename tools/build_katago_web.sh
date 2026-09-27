#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/.build/katago-web"
EMSDK="${EASYPLAY_EMSDK_DIR:-$CACHE/emsdk}"
KATAGO="${EASYPLAY_KATAGO_SOURCE:-$CACHE/KataGo}"
EIGEN="${EASYPLAY_EIGEN_SOURCE:-$CACHE/eigen}"
BUILD="$CACHE/build"
# Kept in step with build_katago_android.sh: the Web build must run the same
# engine as the Android one, or the two platforms disagree about which model
# versions they can load.
KATAGO_COMMIT="fd0723fdbc0e9d82cf269c9630af8c27c57c07c4"
KATAGO_TAG="v1.18.2"
EIGEN_COMMIT="3147391d946bb4b6c68edd901f2add6ac1f31f8c"
EIGEN_TAG="3.4.0"
EMSDK_VERSION="6.0.3"

mkdir -p "$CACHE"
if [[ ! -d "$EMSDK/.git" ]]; then
  git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$EMSDK"
fi
if [[ ! -d "$KATAGO/.git" ]]; then
  git clone --depth 1 --branch "$KATAGO_TAG" https://github.com/lightvector/KataGo.git "$KATAGO"
elif [[ "$(git -C "$KATAGO" rev-parse HEAD)" != "$KATAGO_COMMIT" ]]; then
  # An older check-out is present; fetch just the pinned tag and move to it.
  git -C "$KATAGO" fetch --depth 1 origin "refs/tags/$KATAGO_TAG:refs/tags/$KATAGO_TAG"
  git -C "$KATAGO" checkout --detach "$KATAGO_COMMIT"
fi
if [[ ! -d "$EIGEN/.git" ]]; then
  git clone --depth 1 --branch "$EIGEN_TAG" https://gitlab.com/libeigen/eigen.git "$EIGEN"
fi
for spec in "$KATAGO:$KATAGO_COMMIT" "$EIGEN:$EIGEN_COMMIT"; do
  dir="${spec%%:*}"
  expected="${spec##*:}"
  if [[ "$(git -C "$dir" rev-parse HEAD)" != "$expected" ]]; then
    echo "Unexpected source revision in $dir" >&2
    exit 1
  fi
  if [[ -n "$(git -C "$dir" status --short)" ]]; then
    echo "Refusing to build modified source tree: $dir" >&2
    exit 1
  fi
done

export EMSDK_QUIET=1
"$EMSDK/emsdk" install "$EMSDK_VERSION"
"$EMSDK/emsdk" activate "$EMSDK_VERSION"
# shellcheck disable=SC1091
source "$EMSDK/emsdk_env.sh" >/dev/null
embuilder build zlib

SHIMS="$CACHE/shims"
mkdir -p "$SHIMS"
emar rcs "$SHIMS/libatomic.a"
emcmake cmake -S "$KATAGO/cpp" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DEMSCRIPTEN_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_CXX_FLAGS="-sUSE_ZLIB=1 -pthread -fexceptions -msimd128 -DBYTE_ORDER=1234 -DLITTLE_ENDIAN=1234 -DBIG_ENDIAN=4321" \
  -DCMAKE_EXE_LINKER_FLAGS="-sUSE_ZLIB=1 -pthread -fexceptions -msimd128 -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createKataGo -sINVOKE_RUN=0 -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS,callMain,getExceptionMessage -sENVIRONMENT=web,worker -sPTHREAD_POOL_SIZE=4 -sPTHREAD_POOL_SIZE_STRICT=0 -sSTACK_SIZE=8388608 -sDEFAULT_PTHREAD_STACK_SIZE=8388608 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=268435456 -sEXIT_RUNTIME=1 -L$SHIMS" \
  -DUSE_BACKEND=EIGEN \
  -DNO_GIT_REVISION=1 \
  -DEIGEN3_INCLUDE_DIRS="$EIGEN" \
  -DBUILD_DISTRIBUTED=OFF
emmake cmake --build "$BUILD" --target katago --parallel "${JOBS:-$(getconf _NPROCESSORS_ONLN)}"

OUT="$ROOT/web/katago"
mkdir -p "$OUT"
cp "$BUILD/katago.js" "$BUILD/katago.wasm" "$OUT/"
if [[ -f "$BUILD/katago.worker.js" ]]; then
  cp "$BUILD/katago.worker.js" "$OUT/"
fi
printf 'Built threaded KataGo WASM: '
ls -lh "$OUT/katago.js" "$OUT/katago.wasm"
