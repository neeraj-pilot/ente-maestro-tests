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
                        ["/bin/bash", str(root / "museum/restore-fixture.sh")],
                        env={**os.environ, "ALLOW_AUTH_FIXTURE_RESTORE": "1"},
                        capture_output=True, text=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Invalid public Auth fixture credentials", result.stderr)

    def test_publish_only_after_verification(self):
        for failure in ("generate", "restore", "counts", "verify", "none"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                shutil.copytree(ROOT / "museum", root / "museum")
                (root / "tools/auth-fixture-generator").mkdir(parents=True)
                fixtures = root / "museum/fixtures"
                source_manifest = json.loads((fixtures / "manifest.json").read_text())
                stale_manifest = {**source_manifest, "enteSourceRevision": "0" * 40}
                (fixtures / "manifest.json").write_text(json.dumps(stale_manifest))
                before = {path.name: path.read_bytes() for path in fixtures.iterdir() if path.is_file()}
                bin_dir = root / "bin"
                bin_dir.mkdir()
                staging = root / "staging"
                staging.mkdir()
                mocks = {
                    "cargo": '''#!/usr/bin/env bash
set -eu
if [[ "$1" == metadata ]]; then
    printf '%s\\n' "$SOURCE_METADATA"
    exit
fi
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
    *'config --format json'*) printf '%s\\n' "$SOURCE_COMPOSE" ;;
    *pg_dump*) printf 'generated snapshot' ;;
    *pg_restore*) [[ "$FAILURE" != restore ]] || exit 42 ;;
    *"source = 'authMaestroFixture'"*)
        if [[ "$FAILURE" == counts ]]; then echo '3|3|1|3|4|0'; else echo '3|3|1|3|5|0'; fi
        ;;
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
                    ["/bin/bash", str(root / "museum/generate-fixture.sh")],
                    env={
                        **os.environ,
                        "PATH": f"{bin_dir}:{os.environ['PATH']}",
                        "TMPDIR": str(staging),
                        "FAILURE": failure,
                        "SOURCE_CREDENTIALS": str(ROOT / "museum/fixtures/public-test-credentials.json"),
                        "SOURCE_METADATA": json.dumps({"packages": [
                            {"name": name, "source": "git+https://github.com/ente-io/ente.git#" + source_manifest["enteSourceRevision"]}
                            for name in ("ente-accounts", "ente-core")
                        ]}),
                        "SOURCE_COMPOSE": json.dumps({"services": {
                            name: {"image": source_manifest[key]}
                            for name, key in (("museum", "museumImage"), ("postgres", "postgresImage"))
                        }}),
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
                    self.assertEqual(manifest["enteSourceRevision"], source_manifest["enteSourceRevision"])
                    self.assertEqual(manifest["museumImage"], source_manifest["museumImage"])
                    self.assertEqual(manifest["postgresImage"], source_manifest["postgresImage"])
                else:
                    self.assertEqual(result.returncode, {"generate": 41, "restore": 42, "counts": 1, "verify": 43}[failure], result.stderr)
                    self.assertEqual(after, before, "Failed generation changed the checked-in fixture")
