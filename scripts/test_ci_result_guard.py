"""Exercise result-bundle admission without starting Xcode or a simulator."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class ResultGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        for name in ("test_ios.sh", "check_toolchain.sh"):
            shutil.copy(ROOT / "scripts" / name, self.root / "scripts" / name)
        shutil.copy(ROOT / ".xcode-version", self.root / ".xcode-version")
        version = (self.root / ".xcode-version").read_text().strip()
        fake = self.root / "bin" / "xcodebuild"
        fake.write_text(
            '#!/bin/bash\n'
            f'if [[ "${{1:-}}" == -version ]]; then printf "Xcode {version}\\n"; exit 0; fi\n'
            'printf "%s\\n" "$@" > fake-args\n'
            'while (($#)); do if [[ "$1" == -resultBundlePath ]]; then shift; mkdir -p "$1"; fi; shift; done\n'
            'exit 42\n'
        )
        fake.chmod(0o755)
        self.output = self.root / "github-output"
        self.output.touch()
        self.env = {
            "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
            "CI": "true", "M1_SIMULATOR_ID": "fixture", "M1_ARCHIVE_CI_XCRESULT": "1",
            "GITHUB_OUTPUT": str(self.output),
        }

    def run_script(self, env):
        return subprocess.run(["bash", "scripts/test_ios.sh"], cwd=self.root,
                              env=env, capture_output=True, text=True)

    def test_large_environment_with_private_input_is_rejected(self):
        env = {**self.env, "R2_PRIVATE_INPUT": "/private/fixture"}
        env.update({f"HARMLESS_{i:04d}_" + "X" * 48: "x" for i in range(5000)})
        result = self.run_script(env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Refusing to archive", result.stderr)
        self.assertFalse((self.root / "fake-args").exists())
        self.assertFalse((self.root / "evidence/M1-mock-tests.xcresult").exists())
        self.assertEqual(self.output.read_text(), "")

    def test_failed_test_run_preserves_bundle_and_exit_status(self):
        result = self.run_script(self.env)
        self.assertEqual(result.returncode, 42)
        self.assertTrue((self.root / "evidence/M1-mock-tests.xcresult").is_dir())
        self.assertIn("-resultBundlePath", (self.root / "fake-args").read_text())
        self.assertEqual(self.output.read_text(), "archive_mock_result=true\n")

    def test_preexisting_bundle_does_not_authorize_upload(self):
        bundle = self.root / "evidence/M1-mock-tests.xcresult"
        bundle.mkdir(parents=True)
        result = self.run_script(self.env)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.output.read_text(), "")
        self.assertFalse((self.root / "fake-args").exists())

    def test_missing_output_does_not_authorize_upload(self):
        self.output.unlink()
        result = self.run_script(self.env)
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / "fake-args").exists())

    def test_dangling_bundle_symlink_does_not_authorize_upload(self):
        (self.root / "evidence").mkdir()
        (self.root / "evidence/M1-mock-tests.xcresult").symlink_to("missing")
        result = self.run_script(self.env)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.output.read_text(), "")
        self.assertFalse((self.root / "fake-args").exists())

    def test_environment_scan_failure_does_not_authorize_upload(self):
        script = self.root / "scripts/test_ios.sh"
        content = script.read_text()
        self.assertIn("if ! python3 -I -c '", content)
        script.write_text(content.replace("if ! python3 -I -c '", "if ! false '", 1))
        result = self.run_script(self.env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Refusing to archive", result.stderr)
        self.assertEqual(self.output.read_text(), "")
        self.assertFalse((self.root / "fake-args").exists())

    def test_workflow_separates_guarded_bundle_from_general_evidence(self):
        workflow = (ROOT / ".github/workflows/m1.yml").read_text()
        self.assertIn("!evidence/M1-mock-tests.xcresult/**", workflow)
        self.assertIn("!evidence/M1-mock-tests.xcresult\n", workflow)
        self.assertIn("always() && steps.mock_tests.outputs.archive_mock_result == 'true'", workflow)
        self.assertIn("path: evidence/M1-mock-tests.xcresult", workflow)


if __name__ == "__main__":
    unittest.main()
