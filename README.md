# Ente Maestro tests

Maestro smoke and end-to-end tests that run against published Ente apps.

At the start of every run, the Android workflows resolve the newest compatible
Auth beta or release-candidate APK from
[`ente/nightly`](https://github.com/ente/nightly/releases), falling back to the
[`ente/ente`](https://github.com/ente/ente/releases) stable APK during the
normal promotion gap. They order eligible builds by the APK asset creation time,
then pin every shard in that run to the same source, asset ID, and SHA-256 digest.
The required smoke workflow is offline. A parallel online Auth workflow runs on
hosted macOS and isolates recovery and synchronized-code lifecycle phases in
fresh emulator sessions. It starts local PostgreSQL and a fixture-pinned Museum
server as backend dependencies. Neither workflow builds the Auth app or uses
Maestro Cloud.

The tests target published builds, not a temporary Ente branch. UI changes are
therefore exercised automatically after they reach Ente `main` and appear in a
compatible nightly APK.

Both hosted workflows also check once daily at 01:17 UTC. A scheduled run
starts the suites only when the resolved Auth APK asset was created within the
previous 24 hours; push, pull-request, and manual runs keep their existing
behavior.

On a pull request, both workflows run only the affected hosted suites; shared
helpers and workflow changes run their full matrices. Manual runs can target one
suite, while every merge to `main` runs the complete hosted baseline. Offline
failures retain Maestro diagnostics for seven days. Online account-auth retains
only JUnit results so passwords and recovery material cannot enter artifacts;
failures also retain a secret-free runtime health snapshot for three days.
Recovery and data-sync failures may retain public-fixture diagnostics for three
days.

See the [Auth test guide](docs/auth-test-rollout.md) for the hosted, local, and
Museum-backed coverage boundaries.

## Run locally

Always resolve the APK immediately before a local run. Release tags can be
reused, so the helper downloads the exact resolved asset ID and verifies its
immutable digest rather than trusting a tag or filename.

```sh
apk_path=$(scripts/download-auth-nightly.sh)
scripts/run-auth-android-local.sh --apk "$apk_path" --suite trash
```

## Latest verified coverage

This table is the post-run record of what is currently green.

### Hosted Android CI (published build)

The latest clean required runs used the same published Auth asset on Android API
34 with Maestro `2.6.1`. The release tag is reusable, so the asset timestamp,
asset ID, and checksum identify the tested build precisely.

| Build detail | Verified value |
| --- | --- |
| APK | `ente-auth-v4.4.25.apk` (`auth-v4.4.25`, stable fallback) |
| Asset created | 2026-07-30 07:52:45 UTC<br>2026-07-30 13:22:45 IST |
| Asset ID | `495080331` |
| SHA-256 | `a01c23b94f9221123e2a2e0218107713788e4c1de24c2232d38aa0b0b2c66afa` |

The clean online run and required offline run both completed on 2026-08-03 UTC:
[online run 30819190261](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261)
and [offline run 30819190013](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013).
Online emulators use 4 GiB of guest memory for Argon2-heavy account operations.
Each badge opens the exact authoritative `main` run.

| Flow | Verified behavior |
| --- | --- |
| Online prepared password login | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Signs into a stable fixture, verifies synchronized GitHub and Microsoft codes, verifies a Dropbox code in Trash, and opens Account and Security settings. |
| Online TOTP login | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Signs into a prepared two-factor account, completes its live TOTP challenge, verifies its synchronized GitHub code, and opens Security settings. |
| Online unknown-account login | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Configures the local Auth endpoint and verifies the expected “Email not registered.” error. |
| Online signup and first Auth key | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Creates a unique account with deterministic OTT `123456`, acknowledges its recovery key, adds its first GitHub code, and verifies the Auth key and entity reached Museum. |
| Online password login | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Starts from fresh Auth state, signs into the account created earlier in the run, and verifies its synchronized GitHub code. |
| Online recovery-key password reset | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Resets a fixture account with its recovery key, proves the old password is rejected, signs in with the replacement password from fresh state, and verifies its synchronized Google code remains visible. |
| Online persisted bulk tag edit | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Selects two synchronized Work codes, applies one tag to both, verifies two Museum mutations, then signs in from fresh state and verifies both codes through that tag. |
| Online synchronized entity lifecycle | [![Passed: run 30819190261](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190261) Imports a synchronized Google code, edits it to Slack, adds a note, tag, and pin, trashes it, verifies that state after a cold reload, restores it, and permanently deletes it while checking Museum state. |
| Offline setup and validation | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Covers onboarding, offline mode, the backup warning, GitHub TOTP setup, required-field validation, advanced fields, and HOTP/TOTP selection. |
| Offline lifecycle and organization | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Covers code details/editing, issuer/account search, empty results, sorting, and home-list organization. |
| Offline bulk pin actions | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Uses Select all for a uniform selection, then exercises Pin, Unpin, and mixed-state actions that change only the applicable code. |
| Offline settings | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Covers Settings plus Data, Security, General, Support, About, Theme, and version-label surfaces. |
| Offline duplicate codes | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Creates two identical GitHub accounts and verifies their two-code group in Data → Duplicate codes without deleting data. |
| Offline tags | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Creates a tag and filters the offline code list by it. |
| Offline bulk tag edit | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Selects GitHub and Stripe, applies one new `Finance` tag to both, and verifies both through the tag filter. |
| Offline bulk tag removal | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Removes `Finance` from two selected codes and confirms the tag filter disappears. |
| Offline trash | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Moves one code to Trash, opens Trash, and restores it without permanently deleting it. |
| Offline bulk trash and restore | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Moves GitHub and Stripe to Trash together, proves both are there, then restores both to All. |
| Offline permanent deletion | [![Passed: run 30819190013](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/30819190013) Moves GitHub and Stripe to Trash, then permanently deletes both. |

### Local Android platform coverage

These checks use a local ARM64 Android API 34 emulator and are not hosted
nightly results or required CI gates. Their badges open the versioned flow.

| Flow | Verified behavior |
| --- | --- |
| Multi-format native imports | [![Local ARM64: passed](https://img.shields.io/badge/Local%20ARM64-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/auth/offline/imports.yaml) Imports plain text and a Google Authenticator migration from Android Downloads. The full multi-format flow remains local because the hosted x86_64 picker cannot reliably return the Google migration file. |
| Local encrypted backups | [![Local ARM64: passed](https://img.shields.io/badge/Local%20ARM64-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/auth/offline/local-backup.yaml) Creates public offline state, enables automatic backups, sets a password and Android backup folder, then creates a manual backup. The runner requires both JSON files to have encrypted backup fields and not expose the test account in plaintext. |

### Not yet green or intentionally deferred

- Logout remains tracked separately: the current published x86 nightly does
  not expose a Logout action in its accessibility hierarchy.
- Local encrypted backups are not part of the required hosted gate yet. App
  lock/biometrics, QR scanning, and other native platform integrations remain
  deferred.
- Tag rename/delete remain deferred until the published nightly exposes stable
  UI surfaces for them.

Update this table from a clean full run on `main`, not a targeted pull-request
run. Keep historical failed or cancelled runs in GitHub Actions; this table
should represent the latest clean result, not hide the debugging history.
