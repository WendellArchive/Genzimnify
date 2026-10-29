#!/usr/bin/env python3
"""Mirror the standalone Studio into the /docs GitHub Pages source."""
import argparse
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = ("index.html", "style.css", "app.js", "transpiler.js", "favicon.svg",
         "rizzgame-preview.js", "rizzgame.py", "runner.js", "runtime-worker.js")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the Pages copy is stale")
    args = parser.parse_args()
    target = ROOT / "docs" / "studio"
    if not args.check:
        target.mkdir(parents=True, exist_ok=True)
    stale = []
    for name in FILES:
        source = ROOT / "studio" / name
        destination = target / name
        if args.check:
            if not destination.exists() or source.read_bytes() != destination.read_bytes():
                stale.append(name)
        else:
            shutil.copyfile(source, destination)
    if stale:
        print("Studio Pages mirror is stale: " + ", ".join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
