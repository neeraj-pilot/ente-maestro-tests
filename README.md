# Ente Maestro tests

Maestro smoke and end-to-end tests that run against published Ente apps.

The Android workflows download the newest `auth-v*-beta` APK from
[`ente/nightly`](https://github.com/ente/nightly/releases), verify its checksum,
and run it on a local GitHub Actions emulator. The required smoke workflow is
offline. A separately dispatched online Auth workflow covers signup,
recovery-key acknowledgement, and password login. It starts local
PostgreSQL and Museum only as backend dependencies. Neither workflow builds
Ente or uses Maestro Cloud.

The offline workflow runs when its test files change and can also be started
manually. The online workflow remains manual while it is being proven. Offline
failures retain Maestro diagnostics for seven days; the online workflow retains
only JUnit results so credentials and recovery material cannot enter artifacts.

See the [Auth test rollout plan](docs/auth-test-rollout.md) for the order in
which offline, platform-integrated, and Museum-backed coverage will be added.

## Latest verified coverage

This table is the post-run record of what is currently green. It is based on
the latest clean hosted runs against `ente-auth-v4.4.25-beta` on Android API
34, with Maestro `2.6.1`. The latest required offline run completed on
2026-07-16 UTC ([run 29536365665](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29536365665));
the latest clean online run completed on 2026-07-16 UTC
([run 29523464564](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564)).

The green badges open the exact hosted run. The local-import badge opens the
flow, because that platform-specific validation does not have a hosted run.

| Track | What the test exercises | Status |
| --- | --- | --- |
| Offline setup and validation | Onboarding, entering offline mode, acknowledging the backup warning, manual GitHub TOTP setup, required-field validation, algorithm/digits/period fields, and HOTP/TOTP selection | [![Passed: run 29536365665](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29536365665) |
| Offline lifecycle and organization | Code details and editing, issuer/account search, empty search results, sorting, and home-list organization | [![Passed: run 29536365665](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29536365665) |
| Offline settings | Settings structure plus Data, Security, General, Support, About, Theme, and version-label surfaces | [![Passed: run 29536365665](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29536365665) |
| Offline tags | Creating a tag and filtering the offline code list by that tag | [![Passed: run 29536365665](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29536365665) |
| Offline trash | Moving a code to Trash, opening Trash, and restoring the code without permanent deletion | [![Passed: run 29536365665](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29536365665) |
| Online unknown-account login | Configuring the local Auth endpoint and verifying the expected “Email not registered.” error | [![Passed: run 29523464564](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564) |
| Online signup and recovery-key acknowledgement | Signup with a unique CI email, deterministic OTT `123456`, password creation, recovery-key acknowledgement, and reaching Settings | [![Passed: run 29523464564](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564) |
| Online password login | Fresh Auth app state, endpoint configuration, and password login using the account created earlier in the same run | [![Passed: run 29523464564](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564) |
| Native file imports | Plain-text import and Google Authenticator migration import using files placed in Android Downloads. Hosted x86_64 is excluded because its DocumentsUI returns an unreadable selected-file path. | [![Local ARM64: passed](https://img.shields.io/badge/Local%20ARM64-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/auth/offline/imports.yaml) |

### Not yet green or intentionally deferred

- Logout remains tracked separately: the current published x86 nightly does
  not expose a Logout action in its accessibility hierarchy.
- Online TOTP two-factor login and recovery-key password reset are planned but
  are not covered by the last green online run.
- Automatic local export, app lock/biometrics, QR scanning, and other native
  platform integrations are not part of the required hosted gate yet.
- Tag rename/delete and permanent Trash deletion remain deferred until the
  published nightly exposes stable UI surfaces for them.

When a hosted run is promoted, update this table with its run link and move
any newly covered flow out of the deferred list. Keep historical failed or
cancelled runs in GitHub Actions; this table should represent the latest
clean result, not hide the debugging history.
