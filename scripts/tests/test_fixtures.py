import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class FixtureGenerationTests(unittest.TestCase):
    def test_reject_nonfixture_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "scripts/fixtures", root / "scripts/fixtures")
            shutil.copytree(ROOT / "museum", root / "museum")
            credentials = root / "museum/fixtures/public-test-credentials.json"
            original = credentials.read_text()
            for invalid in ("classification", "endpoint", "email", "duplicate-id", "codes"):
                with self.subTest(invalid=invalid):
                    data = json.loads(original)
                    if invalid == "classification":
                        data["classification"] = "PRIVATE"
                    elif invalid == "endpoint":
                        data["allowedEndpoint"] = "https://api.ente.io"
                    elif invalid == "email":
                        data["accounts"]["basic"]["email"] = "person@example.org"
                    elif invalid == "duplicate-id":
                        data["accounts"]["basic"]["userId"] = data["accounts"]["totp"]["userId"]
                    else:
                        data["accounts"]["basic"]["codes"].pop()
                    credentials.write_text(json.dumps(data))
                    result = subprocess.run(
                        ["/bin/bash", str(root / "scripts/fixtures/verify-auth-fixture.sh")],
                        capture_output=True, text=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Invalid public Auth fixture credentials", result.stderr)

    def test_publish_only_after_verification(self):
        for failure in ("generate", "restore", "counts", "verify", "none"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                shutil.copytree(ROOT / "scripts/fixtures", root / "scripts/fixtures")
                shutil.copytree(ROOT / "museum", root / "museum")
                (root / "tools/auth-fixture-generator").mkdir(parents=True)
                fixtures = root / "museum/fixtures"
                before = {path.name: path.read_bytes() for path in fixtures.iterdir() if path.is_file()}
                bin_dir = root / "bin"
                bin_dir.mkdir()
                staging = root / "staging"
                staging.mkdir()
                mocks = {
                    "cargo": '''#!/usr/bin/env bash
set -eu
output=${@: -1}
[[ "$output" == "$AUTH_FIXTURE_DIR/public-test-credentials.json" ]]
if [[ "$*" == *" generate "* ]]; then
    [[ "$FAILURE" != generate ]] || exit 41
    cp "$SOURCE_CREDENTIALS" "$output"
else
    [[ "$FAILURE" != verify ]] || exit 43
fi
''',
                    "docker": '''#!/usr/bin/env bash
set -eu
case "$*" in
    *pg_dump*) printf 'generated snapshot' ;;
    *pg_restore*) [[ "$FAILURE" != restore ]] || exit 42 ;;
    *"source = 'authMaestroFixture'"*)
        if [[ "$FAILURE" == counts ]]; then echo '3|3|1|3|4|0'; else echo '3|3|1|3|5|0'; fi
        ;;
    *'SELECT 1'*) echo 1 ;;
esac
''',
                    "curl": '''#!/usr/bin/env bash
echo '{"id":"0137a0c754ac0fe4f2c4c7421727c349327eb990"}'
''',
                }
                for name, content in mocks.items():
                    path = bin_dir / name
                    path.write_text(content)
                    path.chmod(0o755)
                result = subprocess.run(
                    ["/bin/bash", str(root / "scripts/fixtures/generate-auth-fixture.sh")],
                    env={
                        **os.environ,
                        "PATH": f"{bin_dir}:{os.environ['PATH']}",
                        "TMPDIR": str(staging),
                        "FAILURE": failure,
                        "SOURCE_CREDENTIALS": str(ROOT / "museum/fixtures/public-test-credentials.json"),
                    },
                    capture_output=True, text=True,
                )
                after = {path.name: path.read_bytes() for path in fixtures.iterdir() if path.is_file()}
                self.assertEqual(list(staging.iterdir()), [], "Generation left temporary fixtures behind")
                if failure == "none":
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    dump = after["auth-fixture-v2.dump"]
                    self.assertEqual(dump, b"generated snapshot")
                    manifest = json.loads(after["manifest.json"])
                    self.assertEqual(manifest["dumpSha256"], hashlib.sha256(dump).hexdigest())
                else:
                    self.assertEqual(result.returncode, {"generate": 41, "restore": 42, "counts": 1, "verify": 43}[failure], result.stderr)
                    self.assertEqual(after, before, "Failed generation changed the checked-in fixture")
