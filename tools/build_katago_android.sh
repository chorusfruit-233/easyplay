#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/.build/katago-android"
KATAGO="$CACHE/KataGo"
EIGEN="$CACHE/eigen"
BUILD="$CACHE/build"
BACKEND="${1:-all}"
case "$BACKEND" in cpu|opencl|all) ;; *) echo "Usage: $0 [cpu|opencl|all]" >&2; exit 2;; esac
OPENCL_HEADERS="$CACHE/OpenCL-Headers"
OPENCL_HEADERS_COMMIT="8a97ebc88daa3495d6f57ec10bb515224400186f"
KATAGO_COMMIT="ba938676d7f42d70950b3a535af2466fb642008c"
EIGEN_COMMIT="3147391d946bb4b6c68edd901f2add6ac1f31f8c"
KATAGO_TAG="v1.16.5"
EIGEN_TAG="3.4.0"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}/ndk/28.2.13676358}}"
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"

if [[ ! -f "$TOOLCHAIN" ]]; then
  echo "Android NDK not found at $NDK (set ANDROID_NDK_HOME to override)." >&2
  exit 1
fi

mkdir -p "$CACHE"
if [[ ! -d "$KATAGO/.git" ]]; then
  git clone --depth 1 --branch "$KATAGO_TAG" https://github.com/lightvector/KataGo.git "$KATAGO"
fi
if [[ "$BACKEND" != "opencl" && ! -d "$EIGEN/.git" ]]; then
  git clone --depth 1 --branch "$EIGEN_TAG" https://gitlab.com/libeigen/eigen.git "$EIGEN"
fi
SOURCES=("$KATAGO:$KATAGO_COMMIT")
if [[ "$BACKEND" != "opencl" ]]; then SOURCES+=("$EIGEN:$EIGEN_COMMIT"); fi
if [[ "$BACKEND" != "cpu" ]]; then
  if [[ ! -d "$OPENCL_HEADERS/.git" ]]; then
    git clone --depth 1 --branch v2025.07.22 https://github.com/KhronosGroup/OpenCL-Headers.git "$OPENCL_HEADERS"
  fi
  SOURCES+=("$OPENCL_HEADERS:$OPENCL_HEADERS_COMMIT")
fi
for spec in "${SOURCES[@]}"; do
  dir="${spec%%:*}"
  expected="${spec##*:}"
  actual="$(git -C "$dir" rev-parse HEAD)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected source revision in $dir: $actual (expected $expected)" >&2
    exit 1
  fi
  if [[ -n "$(git -C "$dir" status --short)" ]]; then
    echo "Refusing to build modified source tree: $dir" >&2
    exit 1
  fi
done

if [[ "$BACKEND" != "opencl" ]]; then
cmake -S "$KATAGO/cpp" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DUSE_BACKEND=EIGEN \
  -DNO_GIT_REVISION=1 \
  -DBUILD_DISTRIBUTED=OFF \
  -DEIGEN3_INCLUDE_DIRS="$EIGEN" \
  -DCMAKE_CXX_FLAGS="-O3 -fexceptions -DBYTE_ORDER=1234 -DLITTLE_ENDIAN=1234 -DBIG_ENDIAN=4321" \
  -DCMAKE_EXE_LINKER_FLAGS="-fexceptions"

cmake --build "$BUILD" --target katago --parallel "${JOBS:-$(getconf _NPROCESSORS_ONLN)}"

STRIP="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
OUT="$ROOT/android/app/src/main/jniLibs/arm64-v8a/libkatago.so"
mkdir -p "$(dirname "$OUT")"
cp "$BUILD/katago" "$OUT"
"$STRIP" --strip-debug "$OUT"
chmod 755 "$OUT"

printf 'Built Android KataGo %s (%s) for arm64-v8a: ' "$KATAGO_TAG" "$KATAGO_COMMIT"
ls -lh "$OUT"
fi

if [[ "$BACKEND" != "cpu" ]]; then
  LLVM="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
  OPENCL_BUILD="$CACHE/build-opencl"
  mkdir -p "$OPENCL_BUILD"
  python3 "$ROOT/tools/generate_opencl_loader.py" "$KATAGO" "$OPENCL_HEADERS" "$OPENCL_BUILD/loader.cpp"
  "$LLVM/aarch64-linux-android24-clang++" -std=c++17 -O2 -fPIC -I"$OPENCL_HEADERS" -c "$OPENCL_BUILD/loader.cpp" -o "$OPENCL_BUILD/loader.o"
  "$LLVM/llvm-ar" rcs "$OPENCL_BUILD/libeasyplay-opencl.a" "$OPENCL_BUILD/loader.o"
  cmake -S "$KATAGO/cpp" -B "$OPENCL_BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
    -DUSE_BACKEND=OPENCL -DNO_GIT_REVISION=1 -DBUILD_DISTRIBUTED=OFF \
    -DOpenCL_INCLUDE_DIR="$OPENCL_HEADERS" -DOpenCL_LIBRARY="$OPENCL_BUILD/libeasyplay-opencl.a" \
    -DCMAKE_CXX_FLAGS="-O3 -fexceptions -DBYTE_ORDER=1234 -DLITTLE_ENDIAN=1234 -DBIG_ENDIAN=4321" \
    -DCMAKE_EXE_LINKER_FLAGS="-fexceptions -ldl"
  cmake --build "$OPENCL_BUILD" --target katago --parallel "${JOBS:-$(getconf _NPROCESSORS_ONLN)}"
  OUT_DIR="$ROOT/android/app/src/main/jniLibs/arm64-v8a"
  mkdir -p "$OUT_DIR"
  cp "$OPENCL_BUILD/katago" "$OUT_DIR/libkatago-opencl.so"
  "$LLVM/aarch64-linux-android24-clang++" -std=c++17 -O2 -static-libstdc++ -I"$OPENCL_HEADERS" \
    "$ROOT/tools/native/opencl_probe.cpp" "$OPENCL_BUILD/libeasyplay-opencl.a" -ldl -o "$OUT_DIR/libkatago-opencl-probe.so"
  "$LLVM/llvm-strip" --strip-debug "$OUT_DIR/libkatago-opencl.so" "$OUT_DIR/libkatago-opencl-probe.so"
  chmod 755 "$OUT_DIR/libkatago-opencl.so" "$OUT_DIR/libkatago-opencl-probe.so"
  printf 'Built Android KataGo OpenCL %s with a dynamic device driver loader\n' "$KATAGO_TAG"
fi
