#!/usr/bin/env python3
"""Generate Android assets for the LAN Web client without changing pubspec."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys

from package_lan_android import excluded

ROOT = Path(__file__).resolve().parent.parent
WEB_BUILD = ROOT / "build/web"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", required=True, help="Flutter executable from the Android SDK configuration")
    parser.add_argument("--output", type=Path, required=True, help="Generated Android assets directory")
    args = parser.parse_args()
    if "# LAN_WEB_ASSETS_START" in (ROOT / "pubspec.yaml").read_text():
        raise SystemExit("Remove the legacy temporary LAN Web assets block from pubspec.yaml first")
    subprocess.run([sys.executable, str(ROOT / "tools/prepare_stockfish.py"), "--web-only"],
                   cwd=ROOT, check=True)
    # Deleted static files may otherwise survive in Flutter's Web output.
    if WEB_BUILD.exists():
        shutil.rmtree(WEB_BUILD)
    subprocess.run([args.flutter, "build", "web", "--release", "--no-pub", "--no-wasm-dry-run"],
                   cwd=ROOT, check=True)
    for required in ("index.html", "main.dart.js", "flutter_bootstrap.js"):
        if not (WEB_BUILD / required).is_file():
            raise SystemExit(f"Web bundle is incomplete: missing {required}")
    # Flutter rootBundle.load('assets/web/...') resolves this Android asset path.
    output = args.output.resolve()
    if output.exists():
        shutil.rmtree(output)
    bundle = output / "flutter_assets/assets/web"
    for source in WEB_BUILD.rglob("*"):
        relative = source.relative_to(WEB_BUILD)
        if source.is_file() and not excluded(relative):
            target = bundle / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    print(f"LAN Web client bundled in {bundle}", flush=True)


if __name__ == "__main__":
    main()
