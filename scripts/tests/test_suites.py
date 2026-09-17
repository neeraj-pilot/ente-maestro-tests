import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import suites


class SelectionTests(unittest.TestCase):
    def test_manual_suites(self):
        self.assertEqual(suites.requested("all"), suites.selection(suites.OFFLINE, suites.ONLINE))
        self.assertEqual(suites.requested("offline"), suites.selection(suites.OFFLINE))
        self.assertEqual(suites.requested("online"), suites.selection(online=suites.ONLINE))
        for name in suites.OFFLINE:
            with self.subTest(suite=name):
                self.assertEqual(suites.requested(name), suites.selection([name]))
        for name in suites.ONLINE:
            with self.subTest(suite=name):
                self.assertEqual(suites.requested(name), suites.selection(online=[name]))
        with self.assertRaises(ValueError):
            suites.requested("typo")

    def test_shared_dependencies_and_local_exclusions(self):
        cases = [
            (["maestro/auth/offline/tags.yaml", "maestro/auth/offline/trash-restore.yaml"], suites.OFFLINE, []),
            (["maestro/auth/online/unknown-login.yaml", "maestro/auth/online/prepared-password-login.yaml"], [], suites.ONLINE),
            (["maestro/auth/subflows/new-helper.yaml"], suites.OFFLINE, []),
            (["maestro/auth/offline/new-flow.yaml"], suites.OFFLINE, []),
            (["maestro/fixtures/new-fixture.json"], suites.OFFLINE, []),
            (["maestro/auth/online/subflows/new-helper.yaml"], [], suites.ONLINE),
            (["maestro/auth/online/new-flow.yaml"], [], suites.ONLINE),
            (["scripts/run-auth-offline.sh"], suites.OFFLINE, []),
            (["scripts/run-auth-online.sh"], [], suites.ONLINE),
            (["scripts/current-totp.py"], [], suites.ONLINE),
            (["museum/fixtures/manifest.json"], [], suites.ONLINE),
            (["scripts/fixtures/restore-auth-fixture.sh"], [], suites.ONLINE),
            (["tools/auth-fixture-generator/Cargo.lock"], [], suites.ONLINE),
            (["notes.md", *suites.LOCAL_ONLY], [], []),
        ]
        for path in (".github/workflows/auth-android.yml", "scripts/apk.sh", "scripts/install-maestro.sh", "scripts/run-maestro.sh", "scripts/suites.py", "scripts/tests/test_suites.py"):
            cases.append(([path], suites.OFFLINE, suites.ONLINE))
        for paths, offline, online in cases:
            with self.subTest(paths=paths):
                self.assertEqual(suites.affected(paths), suites.selection(offline, online))

    def test_event_selection(self):
        self.assertEqual(suites.for_event("schedule"), suites.requested("all"))
        self.assertEqual(suites.for_event("push", base="0" * 40), suites.requested("all"))
        self.assertEqual(suites.for_event("workflow_dispatch", suite="account-auth"), suites.requested("account-auth"))
        with patch.object(suites.subprocess, "check_output", return_value="maestro/auth/online/prepared-logout.yaml\n") as diff:
            self.assertEqual(suites.for_event("pull_request", base="before", head="after"), suites.requested("online"))
            diff.assert_called_with(["git", "diff", "--name-only", "before", "after"], text=True)
            self.assertEqual(suites.for_event("push", base="before", head="after"), suites.requested("online"))
        with patch.object(suites.subprocess, "check_output", side_effect=subprocess.CalledProcessError(128, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                suites.for_event("pull_request", base="missing", head="after")

    def test_cli_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/suites.py"), "--suite", "tags", "--github-output", str(output)],
                env={**os.environ, "EVENT_NAME": "workflow_dispatch"}, check=True,
            )
            values = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(json.loads(values["offline"]), suites.requested("tags")["offline"])
            self.assertEqual(json.loads(values["online"]), [])
            self.assertEqual(values["has_offline"], "true")
            self.assertEqual(values["has_online"], "false")


class RegistrationTests(unittest.TestCase):
    def reachable(self, entrypoints, scopes):
        visited, queue = set(), list(entrypoints)
        while queue:
            flow = queue.pop()
            if flow in visited:
                continue
            self.assertTrue(flow.is_file(), f"Missing flow: {flow}")
            self.assertTrue(any(flow.is_relative_to(ROOT / scope) for scope in scopes), f"Flow escapes scope: {flow}")
            visited.add(flow)
            for dependency in re.findall(r'^\s*file:\s*[\'\"]?([^\'\"\s]+)', flow.read_text(), re.MULTILINE):
                queue.append((flow.parent / dependency).resolve())
        return visited

    def test_offline_registration(self):
        scopes = [f"maestro/auth/{part}" for part in ("offline", "smoke", "subflows")]
        entrypoints = [ROOT / "maestro/auth" / flow for flows in suites.OFFLINE.values() for flow in flows]
        self.assertEqual(len(entrypoints), len(set(entrypoints)), "Duplicate offline execution")
        reachable = self.reachable(entrypoints, scopes)
        expected = {flow for scope in scopes for flow in (ROOT / scope).rglob("*.yaml") if str(flow.relative_to(ROOT)) not in suites.LOCAL_ONLY}
        self.assertEqual(reachable, expected)

    def test_online_registration(self):
        runner = (ROOT / "scripts/run-auth-online.sh").read_text()
        entrypoints = {ROOT / flow for flow in re.findall(r'maestro/auth/online/[\w./-]+\.yaml', runner)}
        self.assertTrue(entrypoints)
        self.assertEqual(self.reachable(entrypoints, ["maestro/auth/online"]), set((ROOT / "maestro/auth/online").rglob("*.yaml")))
