#!/usr/bin/env python3
"""Build the Web client and bundle the same revision into an Android APK.

Flutter asset declarations are temporary: declaring assets/web during the Web
build would recursively embed an older Web bundle in the new one.
"""

import argparse
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
WEB_BUILD = ROOT / "build/web"
BUNDLE = ROOT / "assets/web"


def excluded(path: Path) -> bool:
    parts = path.parts
    name = path.name
    return (
        name == ".last_build_id"
        or name.endswith(".symbols")
        or name.startswith(("skwasm", "wimp"))
        or "experimental_webparagraph" in parts
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--debug", action="store_true", help="build a debug APK")
    output.add_argument("--appbundle", action="store_true", help="build a signed release AAB")
    args = parser.parse_args()
    subprocess.run(["python3", "tools/prepare_stockfish.py"], cwd=ROOT, check=True)
    original = PUBSPEC.read_text()
    if "# LAN_WEB_ASSETS_START" in original:
        raise SystemExit("pubspec.yaml contains a previous temporary bundle block")
    subprocess.run(["flutter", "build", "web", "--release", "--no-wasm-dry-run"],
                   cwd=ROOT, check=True)
    if BUNDLE.exists():
        shutil.rmtree(BUNDLE)
    for source in WEB_BUILD.rglob("*"):
        if source.is_file() and not excluded(source.relative_to(WEB_BUILD)):
            target = BUNDLE / source.relative_to(WEB_BUILD)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    files = sorted(path.relative_to(ROOT).as_posix() for path in BUNDLE.rglob("*")
                   if path.is_file())
    if not files or "assets/web/index.html" not in files:
        raise SystemExit("Web bundle is empty")
    lines = ["    # LAN_WEB_ASSETS_START", *(f"    - {path}" for path in files),
             "    # LAN_WEB_ASSETS_END"]
    if "  assets:\n" not in original:
        raise SystemExit("pubspec.yaml has no Flutter assets section")
    try:
        PUBSPEC.write_text(original.replace("  assets:\n", "  assets:\n" + "\n".join(lines) + "\n", 1))
        command = ["flutter", "build", "appbundle" if args.appbundle else "apk"]
        command += ["--debug"] if args.debug else ["--release"]
        if not args.debug and not args.appbundle:
            command.append("--split-per-abi")
        subprocess.run(command, cwd=ROOT, check=True)
    finally:
        PUBSPEC.write_text(original)
        shutil.rmtree(BUNDLE)


if __name__ == "__main__":
    main()
