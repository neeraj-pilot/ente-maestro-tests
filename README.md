# Ente Maestro tests

Maestro smoke and end-to-end tests that run against published Ente apps.

The Android workflows download the newest `auth-v*-beta` APK from
[`ente/nightly`](https://github.com/ente/nightly/releases), verify its checksum,
and run it on a local GitHub Actions emulator. The required smoke workflow is
offline. A separately dispatched online Auth workflow covers signup,
recovery-key acknowledgement, and password login. It starts local
PostgreSQL and Museum only as backend dependencies. Neither workflow builds
Ente or uses Maestro Cloud.

On a pull request, the offline workflow runs only the affected hosted suite;
shared helpers, onboarding, and workflow changes run the full matrix. Every
merge to `main` runs the full hosted matrix. The online workflow remains manual
while it is being proven. Offline failures retain Maestro diagnostics for seven
days; the online workflow retains only JUnit results so credentials and recovery
material cannot enter artifacts.

See the [Auth test rollout plan](docs/auth-test-rollout.md) for the order in
which offline, platform-integrated, and Museum-backed coverage will be added.

## Latest verified coverage

This table is the post-run record of what is currently green.

### Hosted Android CI (published nightly)

The latest clean hosted runs use `ente-auth-v4.4.25-beta` on Android API 34
with Maestro `2.6.1`. The required offline run completed on 2026-07-17 UTC
([run 29554441320](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29554441320));
the clean online run completed on 2026-07-16 UTC
([run 29523464564](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564)).
Each badge opens the exact hosted run.

| Flow | Verified behavior |
| --- | --- |
| Online unknown-account login | [![Passed: run 29523464564](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564) Configures the local Auth endpoint and verifies the expected “Email not registered.” error. |
| Online signup and recovery-key acknowledgement | [![Passed: run 29523464564](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564) Signs up with a unique CI email, deterministic OTT `123456`, creates a password, acknowledges the recovery key, and reaches Settings. |
| Online password login | [![Passed: run 29523464564](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564) Starts from fresh Auth state, configures the endpoint, and signs into the account created earlier in the same run. |
| Offline setup and validation | [![Passed: run 29554441320](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29554441320) Covers onboarding, offline mode, the backup warning, GitHub TOTP setup, required-field validation, advanced fields, and HOTP/TOTP selection. |
| Offline lifecycle and organization | [![Passed: run 29554441320](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29554441320) Covers code details/editing, issuer/account search, empty results, sorting, and home-list organization. |
| Offline settings | [![Passed: run 29554441320](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29554441320) Covers Settings plus Data, Security, General, Support, About, Theme, and version-label surfaces. |
| Offline tags | [![Passed: run 29554441320](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29554441320) Creates a tag and filters the offline code list by it. |
| Offline trash | [![Passed: run 29554441320](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29554441320) Moves a code to Trash, opens Trash, and restores the code without permanently deleting it. |

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
- Online TOTP two-factor login and recovery-key password reset are planned but
  are not covered by the last green online run.
- Local encrypted backups are not part of the required hosted gate yet. App
  lock/biometrics, QR scanning, and other native platform integrations remain
  deferred.
- Tag rename/delete and permanent Trash deletion remain deferred until the
  published nightly exposes stable UI surfaces for them.

Update this table from a clean full run on `main`, not a targeted pull-request
run. Keep historical failed or cancelled runs in GitHub Actions; this table
should represent the latest clean result, not hide the debugging history.
