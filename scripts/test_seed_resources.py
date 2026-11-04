"""Exercise the real generator in disposable roots; never rewrite repo resources."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
SOURCE = (REPOSITORY / "scripts/seed_resources.py").read_text(encoding="utf-8")
LOCALES = {"en", "zh-Hans", "zh-Hant", "ja"}


class SeedResourcesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="station-localizations-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for folder in ["scripts", "Resources", "contracts/fixtures"]:
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        self.script = self.root / "scripts/seed_resources.py"
        self.script.write_text(SOURCE, encoding="utf-8")
        self.errors = self.root / "contracts/error-localizations.json"
        shutil.copyfile(REPOSITORY / "contracts/error-localizations.json", self.errors)
        self.output = self.root / "Resources/Localizations.json"

    def generate(self):
        return subprocess.run([sys.executable, "-B", str(self.script)], cwd=self.root,
                              capture_output=True, text=True, timeout=20, check=False)

    def test_real_generator_produces_complete_deterministic_four_language_resources(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        first = self.output.read_bytes()
        values = json.loads(first)
        self.assertEqual(set(values), LOCALES)
        english_keys = set(values["en"])
        self.assertGreater(len(english_keys), 500)
        for locale in LOCALES:
            self.assertEqual(set(values[locale]), english_keys)
            self.assertTrue(all(isinstance(text, str) and text for text in values[locale].values()))
        self.assertEqual(values["en"]["shareCardTitle"], "Share card")
        self.assertEqual(values["en"]["noFavorites"], "Save a song to find it here.")
        self.assertEqual(values["zh-Hans"]["noFavorites"], "收藏喜欢的歌曲，就能在这里找到。")
        self.assertEqual(values["en"]["notebookTitle"], "Notebook")
        self.assertEqual(values["zh-Hans"]["notebookTitle"], "笔记本")
        self.assertEqual(values["zh-Hant"]["notebookTitle"], "筆記本")
        self.assertEqual(values["ja"]["notebookTitle"], "ノート")
        self.assertEqual(values["en"]["radio.headline"], "Tonight,\ntune into a song.")
        for locale, entries in json.loads(self.errors.read_text(encoding="utf-8")).items():
            for key, text in entries.items():
                self.assertEqual(values[locale][key], text)
        self.assertTrue((self.root / "contracts/fixtures/catalog.json").is_file())
        repeated = self.generate()
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(self.output.read_bytes(), first)

    def test_duplicate_rows_fail_before_replacing_existing_resources(self):
        # Cover duplicates within each block and across separately appended blocks.
        cases = [
            ("first block", "rows='''", "shareCardTitle"),
            ("second block", "rows+='''\n", "isolatedMusic"),
            ("first and second blocks", "rows+='''\n", "shareCardTitle"),
            ("first and radio blocks", "rows += r'''\n", "shareCardTitle"),
            ("radio block", "rows += r'''\n", "radio.aboutStationCat"),
        ]
        existing = b'{"existing":"must survive duplicate input"}\n'
        fixture = self.root / "contracts/fixtures/catalog.json"
        fixture_bytes = b'{"existing":"catalog must also survive"}\n'
        for name, marker, key in cases:
            with self.subTest(blocks=name):
                self.assertEqual(SOURCE.count(marker), 1, "Update the injection anchor if a rows block moves")
                duplicate = key + "|Duplicate|重复|重複|重複\n"
                self.script.write_text(SOURCE.replace(marker, marker + duplicate, 1), encoding="utf-8")
                self.output.write_bytes(existing)
                fixture.write_bytes(fixture_bytes)
                result = self.generate()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Duplicate localization key: " + key, result.stderr)
                self.assertEqual(self.output.read_bytes(), existing)
                self.assertEqual(fixture.read_bytes(), fixture_bytes)

    def test_error_contract_merge_retains_its_existing_override_behavior(self):
        # Error contracts intentionally merge last; this is separate from a
        # duplicate within rows. Preserve that compatibility rather than using
        # the rows guard to silently change a contract's established precedence.
        errors = json.loads(self.errors.read_text(encoding="utf-8"))
        for locale in LOCALES:
            errors[locale]["shareCardTitle"] = "Contract override " + locale
        self.errors.write_text(json.dumps(errors, ensure_ascii=False), encoding="utf-8")
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(self.output.read_text(encoding="utf-8"))
        for locale, entries in errors.items():
            for key, text in entries.items():
                self.assertEqual(values[locale][key], text)
        self.assertEqual(values["en"]["noFavorites"], "Save a song to find it here.")


if __name__ == "__main__":
    unittest.main(verbosity=2)
