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
ONLINE = {
    "account-auth": [
        "password-login.yaml", "prepared-totp-login-start.yaml",
        "prepared-totp-login-complete.yaml", "signup-recovery-login.yaml",
        "unknown-login.yaml", "subflows/add-online-code.yaml",
    ],
    "recovery-password": [
        "prepared-recovery-login.yaml", "prepared-recovery-old-password.yaml",
        "prepared-recovery-password-reset.yaml",
    ],
    "data-sync": [
        "prepared-password-login.yaml", "prepared-logout.yaml",
        "prepared-bulk-mutation-start.yaml", "prepared-bulk-mutation-complete.yaml",
        "prepared-basic-login.yaml",
    ],
    "entity-lifecycle": [
        "prepared-entity-lifecycle-create.yaml", "prepared-entity-lifecycle-mutate.yaml",
        "prepared-entity-lifecycle-restore.yaml", "prepared-entity-lifecycle-delete.yaml",
        "prepared-basic-login.yaml", "subflows/add-online-code.yaml",
        "fixtures/lifecycle-import.txt",
    ],
}
LOCAL_ONLY = {
    "maestro/auth/offline/imports.yaml", "maestro/auth/offline/local-backup.yaml",
    "maestro/fixtures/plain_text_import.txt", "maestro/fixtures/google_auth_migration.png",
    "scripts/verify-local-auth-backups.sh",
}
SUITES = ("all", "offline", "online", *OFFLINE, *ONLINE, "startup")


def selection(offline=(), online=()):
    return {
        "offline": {"include": [
            {"suite": suite, "flows": [f"maestro/auth/{flow}" for flow in OFFLINE[suite]]}
            for suite in OFFLINE if suite in offline
        ]},
        "online": [suite for suite in (*ONLINE, "startup") if suite in online],
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
    if suite in ONLINE or suite == "startup":
        return selection(online=[suite])
    raise ValueError(f"Unknown Auth suite: {suite}")


def affected(paths, full_groups=False):
    offline, online = set(), set()
    for path in paths:
        if path in LOCAL_ONLY or path.endswith(".md"):
            continue
        if path == "scripts/run-auth-android-local.sh":
            offline.update(OFFLINE)
        elif path == "scripts/run-auth-online.sh" or path.startswith(
            ("museum/", "tools/auth-fixture-generator/", "scripts/fixtures/")
        ):
            online.update(ONLINE)
        elif path == "scripts/current-totp.py":
            online.add("account-auth")
        elif path == ".github/workflows/auth-android.yml" or path.startswith("scripts/"):
            offline.update(OFFLINE)
            online.update(ONLINE)
        elif path.startswith("maestro/auth/online/"):
            name = path.removeprefix("maestro/auth/online/")
            owners = [suite for suite, flows in ONLINE.items() if name in flows]
            online.update(owners or ONLINE)
        elif path.startswith("maestro/auth/"):
            name = path.removeprefix("maestro/auth/")
            owners = [suite for suite, flows in OFFLINE.items() if name in flows]
            offline.update(owners or OFFLINE)
        elif path.startswith("maestro/fixtures/"):
            offline.update(OFFLINE)
    if full_groups:
        return selection(OFFLINE if offline else (), ONLINE if online else ())
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
    return affected(paths, full_groups=event == "push")


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
                selected = result[group]["include"] if group == "offline" else result[group]
                output.write(f"has_{group}={str(bool(selected)).lower()}\n")
    else:
        print(json.dumps(requested(args.suite), separators=(",", ":")))


if __name__ == "__main__":
    main()
