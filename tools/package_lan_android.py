#!/usr/bin/env python3
"""Build the Web client and bundle the same revision into an Android APK.

Gradle prepares the LAN Web assets for both this command and Android Studio.
The generated assets never enter pubspec.yaml or a subsequent Web build.
"""

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def excluded(path: Path) -> bool:
    parts = path.parts
    name = path.name
    return (
        path.as_posix() == "assets/assets/pikafish/pikafish.nnue"
        or name == ".last_build_id"
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
    subprocess.run(["python3", "tools/prepare_pikafish.py"], cwd=ROOT, check=True)
    command = ["flutter", "build", "appbundle" if args.appbundle else "apk"]
    command += ["--debug"] if args.debug else ["--release"]
    if not args.debug and not args.appbundle:
        command.append("--split-per-abi")
    subprocess.run(command, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
