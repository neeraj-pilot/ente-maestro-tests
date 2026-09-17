#!/usr/bin/env python3
"""Select Auth suites for CI and local runs, using one flow registry."""

import argparse
import json
import os
from pathlib import Path
import subprocess


OFFLINE = {
    "basics": [
        "smoke/onboarding.yaml", "smoke/offline-mode.yaml",
        "offline/manual-setup.yaml", "offline/manual-validation.yaml",
        "offline/settings.yaml", "offline/duplicate-codes.yaml",
    ],
    "organization": [
        "offline/code-lifecycle.yaml", "offline/home-organization.yaml",
        "offline/bulk-pin-edit.yaml",
    ],
    "tags": [
        "offline/tags.yaml", "offline/bulk-tag-edit.yaml",
        "offline/bulk-tag-remove.yaml",
    ],
    "trash": [
        "offline/trash-restore.yaml", "offline/bulk-trash-restore.yaml",
        "offline/bulk-permanent-delete.yaml",
    ],
}
ONLINE = ("account-auth", "recovery-password", "data-sync", "entity-lifecycle")
LOCAL_ONLY = {
    "maestro/auth/offline/imports.yaml", "maestro/auth/offline/local-backup.yaml",
    "maestro/fixtures/plain_text_import.txt", "maestro/fixtures/google_auth_migration.png",
    "scripts/verify-local-auth-backups.sh",
}
SUITES = ("all", "offline", "online", *OFFLINE, *ONLINE)


def selection(offline=(), online=()):
    return {
        "offline": [
            {"suite": suite, "flows": [f"maestro/auth/{flow}" for flow in OFFLINE[suite]]}
            for suite in OFFLINE if suite in offline
        ],
        "online": [suite for suite in ONLINE if suite in online],
    }


def requested(suite):
    if suite == "all":
        return selection(OFFLINE, ONLINE)
    if suite == "offline":
        return selection(OFFLINE)
    if suite == "online":
        return selection(online=ONLINE)
    if suite in OFFLINE:
        return selection([suite])
    if suite in ONLINE:
        return selection(online=[suite])
    raise ValueError(f"Unknown Auth suite: {suite}")


def affected(paths):
    offline, online = set(), set()
    for path in paths:
        if path in LOCAL_ONLY or path.endswith(".md"):
            continue
        if path == "scripts/run-auth-offline.sh":
            offline.update(OFFLINE)
        elif path in ("scripts/run-auth-online.sh", "scripts/current-totp.py") or path.startswith(
            ("museum/", "tools/auth-fixture-generator/", "scripts/fixtures/", "maestro/auth/online/")
        ):
            online.update(ONLINE)
        elif path == ".github/workflows/auth-android.yml" or path.startswith("scripts/"):
            offline.update(OFFLINE)
            online.update(ONLINE)
        elif path.startswith(("maestro/auth/", "maestro/fixtures/")):
            offline.update(OFFLINE)
    return selection(offline, online)


def for_event(event, suite="all", base="", head=""):
    if event == "workflow_dispatch":
        return requested(suite)
    if event == "schedule" or (event == "push" and base and set(base) == {"0"}):
        return requested("all")
    if event not in ("pull_request", "push"):
        raise ValueError(f"Unsupported event: {event}")
    paths = subprocess.check_output(
        ["git", "diff", "--name-only", base, head], text=True,
    ).splitlines()
    return affected(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, default="all")
    parser.add_argument("--github-output", type=Path, help="Select for the GitHub event and write job outputs")
    args = parser.parse_args()
    if args.github_output:
        result = for_event(
            os.environ["EVENT_NAME"], args.suite,
            os.environ.get("BASE_SHA", ""), os.environ.get("HEAD_SHA", ""),
        )
        with args.github_output.open("a") as output:
            for group in ("offline", "online"):
                output.write(f"{group}={json.dumps(result[group], separators=(',', ':'))}\n")
                output.write(f"has_{group}={str(bool(result[group])).lower()}\n")
    else:
        print(json.dumps(requested(args.suite), separators=(",", ":")))


if __name__ == "__main__":
    main()
