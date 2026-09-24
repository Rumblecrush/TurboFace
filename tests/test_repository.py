from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON = sys.executable


def inventory(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in root.rglob("*") if path.is_file()
    }


class RepositoryBaselineTests(unittest.TestCase):
    def test_verify_contract(self) -> None:
        result = subprocess.run([PYTHON, "build/verify.py"], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("verification passed", result.stdout)

    def test_builds_match_source_overlays(self) -> None:
        common = inventory(ROOT / "src" / "common")
        with tempfile.TemporaryDirectory() as tmp:
            for flavor in ("classic", "forever"):
                out = Path(tmp) / flavor
                result = subprocess.run(
                    [PYTHON, "build/build_client.py", flavor, "--out", str(out)],
                    cwd=ROOT, text=True, capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                expected = dict(common)
                expected.update(inventory(ROOT / "src" / flavor))
                self.assertEqual(inventory(out), expected)

    def test_builder_rejects_source_tree_output(self) -> None:
        dangerous = [ROOT, ROOT / "src", ROOT / "src" / "common"]
        for out in dangerous:
            result = subprocess.run(
                [PYTHON, "build/build_client.py", "classic", "--out", str(out)],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(any(word in (result.stdout + result.stderr) for word in ("refusing", "must be under")))

    def test_builder_rejects_dist_root_output(self) -> None:
        out = ROOT / "dist"
        out.mkdir(exist_ok=True)
        sentinel = out / "keep-root.txt"
        sentinel.write_text("do not delete")
        try:
            result = subprocess.run(
                [PYTHON, "build/build_client.py", "classic", "--out", str(out)],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(sentinel.is_file())
            self.assertEqual(sentinel.read_text(), "do not delete")
        finally:
            sentinel.unlink(missing_ok=True)

    def test_builder_rejects_existing_external_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "valuable"
            out.mkdir()
            sentinel = out / "keep.txt"
            sentinel.write_text("do not delete")
            result = subprocess.run(
                [PYTHON, "build/build_client.py", "classic", "--out", str(out)],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(sentinel.is_file())
            self.assertEqual(sentinel.read_text(), "do not delete")

    def test_builder_allows_dist_output(self) -> None:
        out = ROOT / "dist" / "_phase33_test"
        try:
            result = subprocess.run(
                [PYTHON, "build/build_client.py", "classic", "--out", str(out)],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((out / "TurboFace.toc").is_file())
        finally:
            if out.exists():
                import shutil
                shutil.rmtree(out)

    def test_no_stale_forever_document_copies(self) -> None:
        for name in (
            "ARCHITECTURE.md", "CHANGELOG.md", "FOREVER_SAVEDVARIABLES_WORKAROUND.md",
            "MULTICLIENT_STRATEGY.md", "PORT_STATUS.md",
        ):
            self.assertFalse((ROOT / "src" / "forever" / name).exists(), name)
        self.assertFalse((ROOT / "src" / "forever" / "build").exists())
        self.assertFalse((ROOT / "docs" / "forever" / "PORT_STATUS.md").exists())
        self.assertEqual(list(ROOT.glob("PHASE*_REPORT.md")), [])

    def test_shared_spellbook_has_no_direct_forever_identity_check(self) -> None:
        text = (ROOT / "src" / "common" / "Trainer" / "UI_Spellbook.lua").read_text(errors="replace")
        self.assertNotIn("IS_TARGET_FOREVER_BUILD", text)
        self.assertNotIn(":IsForever()", text)

    def test_all_lua_sources_compile(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the Lua 5.1-compatible compile check")
        with tempfile.TemporaryDirectory() as tmp:
            bytecode = Path(tmp) / "compiled.luac"
            for source in sorted((ROOT / "src").rglob("*.lua")):
                result = subprocess.run(
                    [luajit, "-b", str(source), str(bytecode)],
                    cwd=ROOT, text=True, capture_output=True,
                )
                self.assertEqual(
                    result.returncode, 0,
                    f"Lua compile failed for {source.relative_to(ROOT)}:\n{result.stdout}{result.stderr}",
                )

    def test_built_packages_have_complete_load_graphs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for flavor in ("classic", "forever"):
                out = Path(tmp) / flavor
                result = subprocess.run(
                    [PYTHON, "build/build_client.py", flavor, "--out", str(out)],
                    cwd=ROOT, text=True, capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

                entries: list[str] = []
                references: set[str] = set()
                xml_entries: list[Path] = []
                for raw in (out / "TurboFace.toc").read_text(errors="replace").splitlines():
                    entry = raw.strip()
                    if not entry or entry.startswith("#"):
                        continue
                    relative = entry.replace("\\", "/")
                    entries.append(relative)
                    references.add(relative)
                    self.assertTrue((out / relative).is_file(), f"{flavor} TOC missing {relative}")
                    if relative.lower().endswith(".xml"):
                        xml_entries.append(Path(relative))

                self.assertEqual(len(entries), len(set(entries)), f"{flavor} TOC has duplicate entries")
                for xml_entry in xml_entries:
                    xml_text = (out / xml_entry).read_text(errors="replace")
                    for target in re.findall(r'(?:file|File)=["\x27]([^"\x27]+)', xml_text):
                        relative = (xml_entry.parent / target.replace("\\", "/")).as_posix()
                        references.add(relative)
                        self.assertTrue((out / relative).is_file(), f"{flavor} XML missing {relative}")

                lua_files = {path.relative_to(out).as_posix() for path in out.rglob("*.lua")}
                self.assertEqual(lua_files - references, set(), f"{flavor} has orphan Lua files")

    def test_release_archives_only_contain_generated_packages(self) -> None:
        common = set(inventory(ROOT / "src" / "common"))
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "release"
            result = subprocess.run(
                [PYTHON, "build/package_release.py", "--out", str(output)],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            archives = sorted(output.glob("*.zip"))
            self.assertEqual(len(archives), 2)
            for flavor, archive in zip(("classic", "forever"), archives, strict=True):
                expected = common | set(inventory(ROOT / "src" / flavor))
                expected.discard("Save-TurboFaceForever.bat")
                with zipfile.ZipFile(archive) as package:
                    members = {name for name in package.namelist() if not name.endswith("/")}
                self.assertEqual(members, {f"TurboFace/{name}" for name in expected})
                self.assertFalse(
                    any(Path(name).suffix.lower() == ".bat" for name in members),
                    f"{flavor} release archive contains a rejected batch launcher",
                )


if __name__ == "__main__":
    unittest.main()
