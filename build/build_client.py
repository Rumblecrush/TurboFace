#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_destination(destination: Path) -> Path:
    destination = destination.expanduser().resolve()
    home = Path.home().resolve()
    protected = {Path('/').resolve(), home, ROOT}
    if destination in protected:
        raise SystemExit(f"refusing unsafe build output path: {destination}")
    # Never delete the repository, anything inside its source/build metadata, or an ancestor
    # that contains the repository. The one supported in-repo destination is ROOT/dist/* .
    dist_root = (ROOT / "dist").resolve()
    if destination == dist_root:
        raise SystemExit(f"refusing to replace the build-output root itself: {destination}")
    if _is_relative_to(destination, ROOT) and not _is_relative_to(destination, dist_root):
        raise SystemExit(f"build output inside repository must be under {dist_root}: {destination}")
    if _is_relative_to(ROOT, destination):
        raise SystemExit(f"refusing build output path that contains the repository: {destination}")
    if destination.exists() and not _is_relative_to(destination, dist_root):
        raise SystemExit(f"refusing to delete an existing external output directory: {destination}")
    return destination


def copy_tree(source: Path, destination: Path) -> None:
    for path in source.rglob("*"):
        if not path.is_file():
            continue
        target = destination / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)


def build(flavor: str, destination: Path) -> None:
    common = ROOT / "src" / "common"
    client = ROOT / "src" / flavor
    if not client.is_dir():
        raise SystemExit(f"unknown client flavor: {flavor}")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    copy_tree(common, destination)
    copy_tree(client, destination)
    toc = destination / "TurboFace.toc"
    if not toc.is_file():
        raise SystemExit(f"built tree is missing {toc}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("flavor", choices=("classic", "forever"))
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    build(args.flavor, validate_destination(args.out))


if __name__ == "__main__":
    main()
