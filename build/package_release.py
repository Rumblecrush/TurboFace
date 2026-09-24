#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import tempfile
import zipfile
from pathlib import Path

from build_client import ROOT, build, validate_destination


VERSION_PATTERN = re.compile(r"^## Version:\s*(\S+)\s*$", re.MULTILINE)


def toc_version(package: Path) -> str:
    toc = package / "TurboFace.toc"
    match = VERSION_PATTERN.search(toc.read_text(errors="replace"))
    if not match:
        raise SystemExit(f"missing ## Version metadata in {toc}")
    return match.group(1)


def write_archive(package: Path, archive: Path) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    archive.unlink(missing_ok=True)
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for source in sorted(path for path in package.rglob("*") if path.is_file()):
            relative = source.relative_to(package)
            output.write(source, (Path("TurboFace") / relative).as_posix())


def main() -> None:
    parser = argparse.ArgumentParser(description="Build both installable TurboFace release archives")
    parser.add_argument("--version", help="release version; defaults to the Classic TOC version")
    parser.add_argument("--out", type=Path, default=ROOT / "release")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="turboface-release-") as temporary:
        staging = Path(temporary)
        classic = validate_destination(staging / "classic")
        forever = validate_destination(staging / "forever")
        build("classic", classic)
        build("forever", forever)

        classic_version = toc_version(classic)
        forever_version = toc_version(forever)
        release_version = (args.version or classic_version).removeprefix("v")
        if release_version != classic_version:
            raise SystemExit(
                f"release version {release_version!r} does not match Classic TOC version {classic_version!r}"
            )
        if not forever_version.startswith(release_version):
            raise SystemExit(
                f"Forever TOC version {forever_version!r} does not share release version {release_version!r}"
            )
        release_notes = ROOT / "docs" / "releases" / f"{release_version}.md"
        if args.version and not release_notes.is_file():
            raise SystemExit(f"missing tagged release notes: {release_notes}")

        output = args.out.expanduser().resolve()
        classic_archive = output / f"TurboFace-Classic-{classic_version}.zip"
        forever_archive = output / f"TurboFace-Forever-{forever_version}.zip"
        write_archive(classic, classic_archive)
        write_archive(forever, forever_archive)

    print(classic_archive)
    print(forever_archive)


if __name__ == "__main__":
    main()
