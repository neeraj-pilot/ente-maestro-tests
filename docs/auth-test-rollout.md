# Auth Maestro test guide

This repository verifies the published Ente Auth Android beta. It is not an
Ente checkout and does not build the app.

The [README coverage table](../README.md#latest-verified-coverage) is the
live record of the latest clean `main` run. Keep historical run links, one-off
debugging notes, and app-bug investigations out of this guide; they become
stale quickly and belong in GitHub Actions or the relevant product issue.

## Test layers

| Layer | Purpose | Runs in hosted CI |
| --- | --- | --- |
| Offline core | Public offline setup, organization, settings, tags, and trash behavior. | Yes, in five selected Android shards. |
| Online fixture | Auth login, TOTP challenge, signup, recovery reset, synchronized codes, and persisted mutations against local Museum. | Yes, in account-auth, recovery-password, and data-sync lanes. |
| Platform local | Android file pickers, encrypted local backups, and other device-specific behavior. | No; validate on local ARM64 emulators or a device. |
| Product demos | Curated, paced presentations assembled from proven behavior flows. | No; keep separate from regression tests. |

## Nightly and fixture contract

Every hosted workflow resolves the newest published `auth-v*-beta` release at
workflow start with `scripts/resolve-auth-nightly.sh`. It passes that release
tag, APK name, and asset digest to every matrix shard. Each shard downloads the
exact asset, verifies both its digest and `SHA256SUMS`, and records the result
in its job summary. This deliberately means “latest at run start”, not a
possibly different latest release for each shard.

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
5. Add the flow to the correct selector mapping. A new hosted flow must choose
   a lane or shard explicitly; unknown hosted paths deliberately trigger the
   full relevant matrix.
6. Keep encrypted data and secrets out of Maestro debug artifacts. Online
   account/recovery failures retain only a secret-free runtime snapshot.

Run the selector tests and the smallest relevant local suite before pushing.
Use `scripts/download-auth-nightly.sh` immediately before a local run; it
resolves and verifies the newest nightly asset rather than trusting a reused
beta tag.

```sh
apk_path=$(scripts/download-auth-nightly.sh)
scripts/run-auth-android-local.sh --apk "$apk_path" --suite tags
```

## Hosted CI behavior

Pull requests run only the affected offline shards or online lanes. Changes to
shared helpers, fixtures, selectors, or workflows run the full relevant
matrix. Every merge to `main` runs all five offline shards and all three online
lanes. The online lanes are isolated because recovery performs several Argon2
derivations; each online emulator receives 4 GiB of guest memory.

The online fixture uses local PostgreSQL and Museum only. Do not add object
storage, a full Ente checkout, or external services unless the covered behavior
needs them.

## Intentional exclusions

- Native file imports and encrypted local backups remain local-only until the
  published x86 Android picker/runtime supports them reliably.
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
