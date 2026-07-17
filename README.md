# Ente Maestro tests

Maestro smoke and end-to-end tests that run against published Ente apps.

The Android workflows download the newest `auth-v*-beta` APK from
[`ente/nightly`](https://github.com/ente/nightly/releases), verify its checksum,
and run it on a local GitHub Actions emulator. The required smoke workflow is
offline. A parallel online Auth workflow isolates the recovery-key password
reset on a fresh emulator, alongside account-authentication and synchronized-
data lanes. It starts local PostgreSQL and Museum only as backend dependencies.
Neither workflow builds Ente or uses Maestro Cloud.

On a pull request, both workflows run only the affected hosted suites; shared
helpers and workflow changes run their full matrices. Manual runs can target one
suite, while every merge to `main` runs the complete hosted baseline. Offline
failures retain Maestro diagnostics for seven days. Online account-auth retains
only JUnit results so passwords and recovery material cannot enter artifacts;
failures also retain a secret-free runtime health snapshot for three days.
Data-sync failures may retain public-fixture diagnostics for three days.

See the [Auth test rollout plan](docs/auth-test-rollout.md) for the order in
which offline, platform-integrated, and Museum-backed coverage will be added.

## Run locally

Always resolve the APK immediately before a local run. Auth beta release tags
can be reused, so the helper verifies the immutable release-asset digest rather
than trusting a filename such as `ente-auth-v4.4.25-beta.apk`.

```sh
apk_path=$(scripts/download-auth-nightly.sh)
scripts/run-auth-android-local.sh --apk "$apk_path" --suite trash
```

## Latest verified coverage

This table is the post-run record of what is currently green.

### Hosted Android CI (published nightly)

The latest clean required offline run used `ente-auth-v4.4.25-beta`
(SHA-256 `8b7d44e6fe180f3a592a130c89775692ac24b816bb3259bdc42f8c5ba99cbaea`)
on Android API 34 with Maestro `2.6.1`. The required offline run completed on
2026-07-17 UTC
([run 29568421839](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839));
the clean online run completed on 2026-07-17 UTC
([run 29574838453](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29574838453)).
Each badge opens the exact hosted run.

| Flow | Verified behavior |
| --- | --- |
| Online prepared password login | [![Passed: run 29574838453](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29574838453) Restores a stable fixture identity, signs in from fresh Auth state, and verifies the Account settings surfaces. |
| Online TOTP login | [![Passed: run 29574838453](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29574838453) Signs into a prepared two-factor account and completes its live TOTP challenge with a code generated at test time. |
| Online unknown-account login | [![Passed: run 29574838453](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29574838453) Configures the local Auth endpoint and verifies the expected “Email not registered.” error. |
| Online signup and recovery-key acknowledgement | [![Passed: run 29574838453](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29574838453) Signs up with a unique CI email, deterministic OTT `123456`, creates a password, acknowledges the recovery key, and reaches Settings. |
| Online password login | [![Passed: run 29574838453](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29574838453) Starts from fresh Auth state, configures the endpoint, and signs into the account created earlier in the same run. |
| Online recovery-key password reset | [![Passed: run 29574838453](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29574838453) Resets a prepared account with its stored recovery key, proves the old password is rejected, and signs in with the replacement password from fresh state. |
| Offline setup and validation | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Covers onboarding, offline mode, the backup warning, GitHub TOTP setup, required-field validation, advanced fields, and HOTP/TOTP selection. |
| Offline lifecycle and organization | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Covers code details/editing, issuer/account search, empty results, sorting, and home-list organization. |
| Offline bulk pin actions | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Uses Select all for a uniform selection, then exercises Pin, Unpin, and mixed-state actions that change only the applicable code. |
| Offline settings | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Covers Settings plus Data, Security, General, Support, About, Theme, and version-label surfaces. |
| Offline duplicate codes | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Creates two identical GitHub accounts and verifies their two-code group in Data → Duplicate codes without deleting data. |
| Offline tags | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Creates a tag and filters the offline code list by it. |
| Offline bulk tag edit | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Selects GitHub and Stripe, applies one new `Finance` tag to both, and verifies both through the tag filter. |
| Offline bulk tag removal | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Removes `Finance` from two selected codes and confirms the tag filter disappears. |
| Offline trash | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Moves one code to Trash, opens Trash, and restores it without permanently deleting it. |
| Offline bulk trash and restore | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Moves GitHub and Stripe to Trash together, proves both are there, then restores both to All. |
| Offline permanent deletion | [![Passed: run 29568421839](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29568421839) Moves GitHub and Stripe to Trash, then permanently deletes both. |

### Local Android platform coverage

These checks use a local ARM64 Android API 34 emulator and are not hosted
nightly results or required CI gates. Their badges open the versioned flow.

| Flow | Verified behavior |
| --- | --- |
| Native file imports | [![Local ARM64: passed](https://img.shields.io/badge/Local%20ARM64-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/auth/offline/imports.yaml) Imports plain text and a Google Authenticator migration from Android Downloads. Hosted x86_64 is excluded because DocumentsUI returns an unreadable selected-file path. |
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
