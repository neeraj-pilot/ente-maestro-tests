# Auth Maestro test guide

This repository verifies compatible published Ente Auth Android APKs. It does
not build the Auth app. Online CI sparsely checks out only the Museum server at
the fixture-pinned revision.

The [README coverage table](../README.md#latest-verified-coverage) is the
live record of the latest clean `main` run. Keep historical run links, one-off
debugging notes, and app-bug investigations out of this guide; they become
stale quickly and belong in GitHub Actions or the relevant product issue.

## Test layers

| Layer | Purpose | Runs in hosted CI |
| --- | --- | --- |
| Offline core | Public offline setup, organization, settings, tags, and trash behavior. | Yes, in five selected Android shards. |
| Online fixture | Auth login, TOTP challenge, signup, recovery reset, synchronized codes, and persisted mutations against local Museum. | Yes, in account-auth, recovery-password, data-sync, and entity-lifecycle lanes. |
| Platform local | Google Authenticator migration imports, encrypted local backups, and other device-specific behavior. | No; validate on local ARM64 emulators or a device. |
| Product demos | Curated, paced presentations assembled from proven behavior flows. | No; keep separate from regression tests. |

## Published build and fixture contract

Every hosted workflow resolves the newest compatible published Auth APK at
workflow start with `scripts/resolve-nightly-apk.sh`. It prefers beta and
release-candidate assets from `ente/nightly`, then falls back to the stable
`ente/ente` release when promotion has removed the corresponding nightly tag.
Because prerelease tags can be reused, the resolver orders eligible APKs by
asset creation time and passes the exact source repository, asset ID, APK name,
creation time, and digest to every matrix shard. Each shard downloads that
asset ID, verifies its digest, and records the provenance in its job summary.
This deliberately means “latest at run start”, not a possibly different build
for each shard.

The suite does not follow temporary Ente branches. A product change becomes the
test target after it reaches Ente `main` and is present in a compatible published
APK.

Online tests restore the checked-in public Museum fixture before each lane.
Fixture identities are intentionally obvious and their credentials live only
in `museum/fixtures/public-test-credentials.json`. Do not place passwords,
recovery keys, OTTs, or TOTP secrets in step summaries, screenshots, or public
diagnostics.

## Repository layout

| Path | Owns |
| --- | --- |
| `maestro/auth/offline/` | Public offline behavior flows. |
| `maestro/auth/online/` | Museum-backed login, recovery, sync, and mutation flows. |
| `maestro/auth/subflows/` | Small cross-flow public UI setup helpers. |
| `maestro/auth/online/subflows/` | Online-only login, endpoint, and synchronized-code helpers. |
| `maestro/fixtures/` | Public files used by local platform flows. |
| `museum/fixtures/` | Versioned public Museum fixture and its manifest. |
| `scripts/select-auth-*.sh` | Maps a changed path to the smallest safe hosted matrix. |
| `.github/workflows/` | Published-nightly Android workflows. |

Keep a reusable subflow limited to one stable public interaction. Put a flow
next to the behavior it verifies; do not create generic “utility” flows that
hide product state or silently broaden the selected CI matrix.

## Adding or changing a test

1. Exercise real user-visible behavior. Local debug helpers can speed up
   exploration but must not replace the hosted regression path.
2. Create only the state needed by the flow. Use a named subflow when more
   than one test needs the same public setup.
3. Prefer a shipped, action-oriented semantics identifier; then a visible
   label; use coordinates only for Android system UI that exposes neither.
4. Wait for a meaningful ready state such as a code item, sheet title, or
   selected tag. Do not add blanket retries or arbitrary delays.
5. Add the flow to a hosted shard or online runner. Registration validation
   fails if a new flow is not reachable from CI; selector changes still trigger
   the full relevant matrix until the flow has a narrower mapping.
6. Keep encrypted data and secrets out of Maestro debug artifacts. Online
   account/recovery failures retain only a secret-free runtime snapshot.

Run the selector tests and the smallest relevant local suite before pushing.
Use `scripts/download-auth-nightly.sh` immediately before a local run; it
resolves and verifies the newest compatible published asset rather than
trusting a reused release tag.

```sh
apk_path=$(scripts/download-auth-nightly.sh)
scripts/run-auth-android-local.sh --apk "$apk_path" --suite tags
```

## Hosted CI behavior

Pull requests run only the affected offline shards or online lanes. Changes to
shared helpers, fixtures, selectors, or workflows run the full relevant
matrix. Every merge to `main` runs all five offline shards and all four online
lanes. Account-auth and data-sync each use one emulator session. Synchronized
entity lifecycle uses separate create, mutate, and restore/delete sessions;
recovery uses separate reset and verification sessions. Each online emulator
receives 4 GiB of guest memory. The online matrix runs on hosted macOS because
Linux QEMU has crashed during Argon2-heavy recovery and lifecycle operations.

The online fixture uses local PostgreSQL and Museum only. Do not add object
storage, a full Ente checkout, or external services unless the covered behavior
needs them.

## Intentional exclusions

- Google Authenticator migration imports and encrypted local backups remain
  local-only until the published x86 Android picker/runtime supports them
  reliably.
- Logout, passkeys, app lock/biometrics, QR scanning, gallery selection, and
  external intents are not hosted coverage yet.
- Do not add a separate Auth settings status for whether account 2FA is
  enabled solely for testing. The login TOTP challenge is the product behavior
  covered by the online suite.

## Promoting coverage

Add a behavior to required hosted CI only when it has deterministic selectors
in the published nightly, needs no untracked service, keeps diagnostics
secret-free, and has passed clean hosted runs. After a clean full run on
`main`, refresh the README coverage table with that run; do not use targeted
pull-request or manual runs as the dashboard source.
