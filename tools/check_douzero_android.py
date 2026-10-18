#!/usr/bin/env python3
"""Reject an APK whose DEX classes cannot satisfy ONNX Runtime's JNI lookups.

Inspect class definitions, not just strings (a removed class can still be named
by a signature). The required names come from the JNI library in the same APK.
This check must run on a minified release build; debug/JVM tests miss R8 damage.
"""

import argparse
from pathlib import Path
import re
import struct
import zipfile


def dex_classes(data: bytes) -> set[str]:
    if not data.startswith(b"dex\n") or struct.unpack_from("<I", data, 40)[0] != 0x12345678:
        raise ValueError("Expected a standard little-endian DEX file")
    string_ids = struct.unpack_from("<I", data, 60)[0]
    type_ids = struct.unpack_from("<I", data, 68)[0]
    count, class_defs = struct.unpack_from("<II", data, 96)
    classes = set()
    for index in range(count):
        type_id = struct.unpack_from("<I", data, class_defs + index * 32)[0]
        string_id = struct.unpack_from("<I", data, type_ids + type_id * 4)[0]
        offset = struct.unpack_from("<I", data, string_ids + string_id * 4)[0]
        # Skip the ULEB128 UTF-16 length. Class descriptors of interest are ASCII.
        while data[offset] & 0x80:
            offset += 1
        offset += 1
        end = data.index(b"\0", offset)
        classes.add(data[offset:end].decode("utf-8", errors="replace"))
    return classes


def check_apk(path: Path) -> None:
    with zipfile.ZipFile(path) as apk:
        library = apk.read("lib/arm64-v8a/libonnxruntime4j_jni.so")
        required = {
            "L" + name.decode("ascii") + ";"
            for name in re.findall(rb"ai/onnxruntime/[A-Za-z0-9_$]+", library)
        }
        if not required:
            raise ValueError("ONNX JNI class names not found in native library")
        defined = set()
        for name in apk.namelist():
            if re.fullmatch(r"classes\d*\.dex", name):
                defined.update(dex_classes(apk.read(name)))
    missing = sorted(required - defined)
    if missing:
        raise ValueError(
            "ONNX JNI classes missing or renamed by R8: " + ", ".join(missing)
            + ". Check android/app/proguard-rules.pro."
        )
    print(f"DouZero Android JNI contract PASS: {len(required)} native class lookups in {path.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    args = parser.parse_args()
    try:
        check_apk(args.apk)
    except (ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
