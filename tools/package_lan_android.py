#!/usr/bin/env python3
"""Build the Web client and bundle the same revision into an Android APK.

Gradle prepares the LAN Web assets for both this command and Android Studio.
The generated assets never enter pubspec.yaml or a subsequent Web build.
"""

import argparse
import re
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

TRANSIENT_DOWNLOAD_ERROR = re.compile(
    r"Received status code (?:429|500|502|503|504)\b"
    r"|(?:Connect|Read|Connection) timed out"
    r"|Connection reset|Temporary failure in name resolution",
    re.IGNORECASE,
)


def run_flutter_build(command: list[str], network_retries: int = 0) -> None:
    """Stream build logs and back off only after transient download failures."""
    for attempt in range(network_retries + 1):
        tail = ""
        with subprocess.Popen(
            command, cwd=ROOT, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, errors="replace",
        ) as process:
            assert process.stdout is not None
            for line in process.stdout:
                print(line, end="", flush=True)
                tail = (tail + line)[-65536:]
            returncode = process.wait()
        if returncode == 0:
            return
        if attempt == network_retries or not TRANSIENT_DOWNLOAD_ERROR.search(tail):
            raise subprocess.CalledProcessError(returncode, command)
        delay = 30 * (2 ** attempt)
        print(
            f"Dependency download failed temporarily; retrying Android build "
            f"in {delay}s ({attempt + 1}/{network_retries}).",
            flush=True,
        )
        time.sleep(delay)


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
    parser.add_argument(
        "--network-retries", type=int, choices=range(4), default=0,
        help="retry transient dependency download failures with 30/60/120s backoff",
    )
    args = parser.parse_args()
    subprocess.run(["python3", "tools/prepare_stockfish.py"], cwd=ROOT, check=True)
    subprocess.run(["python3", "tools/prepare_pikafish.py"], cwd=ROOT, check=True)
    command = ["flutter", "build", "appbundle" if args.appbundle else "apk"]
    command += ["--debug"] if args.debug else ["--release"]
    if not args.debug and not args.appbundle:
        command.append("--split-per-abi")
    run_flutter_build(command, args.network_retries)


if __name__ == "__main__":
    main()
