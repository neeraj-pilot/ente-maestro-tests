# Ente Auth Maestro tests

Android regression tests against published Ente Auth APKs. Tests run on Ubuntu
with KVM-accelerated Android emulators. Online tests use disposable PostgreSQL
and a pinned Museum container. Museum is a test dependency, not the product under
test. No Maestro Cloud or production account is required.

## Results

- [Online runs](https://github.com/neeraj-pilot/ente-maestro-tests/actions/workflows/auth-android-online.yml)
- [Offline runs](https://github.com/neeraj-pilot/ente-maestro-tests/actions/workflows/auth-android-smoke.yml)

Open a run's job summaries for the **APK name, creation date, asset ID, SHA-256,
selected suite and result**. Release tags are reused; a version name alone does
not identify the tested build. A successful workflow that skipped its emulator
jobs is **not a passing test run**. JUnit artifacts contain the executed tests.

## Coverage

This is a coverage inventory, not a manually maintained green-status dashboard.

### Hosted Android CI (published build)

| Suite | Behavior tested |
| --- | --- |
| Online account auth | Signup and first code upload; fresh password login; unknown-account rejection; live TOTP challenge and synchronized code visibility. |
| Online recovery | Recovery-key password reset; old-password rejection; new-password login with the synchronized code preserved. |
| Online data sync | Prepared-account login; active and trashed codes; Account/Security settings; bulk-tag edits verified after fresh login. |
| Online entity lifecycle | Import, edit, notes, tags, pin, trash, restore and permanent deletion, with fresh-session persistence checks. |
| Offline setup | Onboarding, offline backup warning, manual account creation, and required/advanced-field validation. |
| Offline organization | Editing and cold-relaunch persistence; search, sorting, and bulk pin/unpin. |
| Offline settings | Settings sections, General, About, theme choices and duplicate-code groups. |
| Offline tags | Create/filter tags; bulk apply and removal. |
| Offline trash | Single and bulk trash/restore; permanent deletion. |

### Local Android platform coverage

| Suite | Behavior tested |
| --- | --- |
| Imports | Plain-text and Google Authenticator migration imports through Android Downloads. |
| Backup | Automatic and manual backup creation; encrypted-file structure and absence of the fixture account in plaintext. **Restoration is not tested yet.** |

These platform flows are excluded from hosted CI pending reliable picker
validation. Do not report local results as hosted coverage. App lock/biometrics,
passkeys, camera scanning and logout are not currently covered by hosted tests.

## Run locally

Requires Android platform tools, Java, Maestro, GitHub CLI and jq. Use a dedicated
test device or emulator: flows clear Auth state, and the local runner reinstalls
the independent Auth package. Do not point it at an app containing personal codes.

```sh
apk_path=$(scripts/download-auth-nightly.sh)
scripts/run-auth-android-local.sh --apk "$apk_path" --serial <adb-serial> --suite setup
```

Local suites: `smoke`, `setup`, `organization`, `settings`, `tags`, `trash`,
`imports`, `backup`, or `required` (all hosted offline suites). Each run gets its
own directory under `artifacts/maestro/local/`, printed by the runner. Set
`MAESTRO_ARTIFACTS_DIR` to use another parent directory. The runner and hosted CI
share the same offline suite definitions.

See the [test guide](docs/auth-test-rollout.md) for CI selection, adding flows,
diagnostics and online setup, and the [fixture guide](museum/fixtures/README.md)
for restoring or regenerating public test accounts.
