# Ente Auth Maestro tests

Android regression tests against published Ente Auth APKs. Tests run on Ubuntu
with KVM-accelerated Android emulators. Online tests use disposable PostgreSQL
and a pinned Museum container. Museum is a test dependency, not the product under
test. No Maestro Cloud or production account is required.

## Results

[Auth Android runs](https://github.com/neeraj-pilot/ente-maestro-tests/actions/workflows/auth-android.yml)
use two test runners in parallel: one offline and one online, using the same APK.
Selected suites run sequentially within each runner. The online runner restores
its disposable backend between independent suites, retaining state between
related recovery or lifecycle phases.

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
| Online data sync | Prepared-account login; active and trashed codes; Account/Security settings; bulk-tag edits verified after fresh login; logout persisted across a cold relaunch. |
| Online entity lifecycle | Import, edit, notes, tags, pin, trash, restore and permanent deletion, with fresh-session persistence checks. |
| Offline basics | Onboarding, offline backup warning, manual creation and field validation; Settings, General, About, themes and duplicate-code groups. |
| Offline organization | Editing and cold-relaunch persistence; search, sorting, and bulk pin/unpin. |
| Offline tags | Create/filter tags; bulk apply and removal. |
| Offline trash | Single and bulk trash/restore; permanent deletion. |

### Local Android platform coverage

| Suite | Behavior tested |
| --- | --- |
| Imports | Plain-text and Google Authenticator migration imports through Android Downloads. |
| Backup | Automatic and manual backup creation; encrypted-file structure and absence of the fixture account in plaintext. **Restoration is not tested yet.** |

These platform flows are excluded from hosted CI pending reliable picker
validation. Do not report local results as hosted coverage. App lock/biometrics,
passkeys and camera scanning are not currently covered by hosted tests.

## Run locally

Requires Android platform tools, Java 17+, Maestro, Python 3.9+, GitHub CLI and jq.
Use a dedicated test device or emulator: flows clear Auth state, and the local runner reinstalls
the independent Auth package. Do not point it at an app containing personal codes.

```sh
apk_path=$(scripts/apk.sh fetch)
scripts/run-auth-android-local.sh --apk "$apk_path" --serial <adb-serial> --suite basics
```

Local suites: `smoke`, `basics`, `organization`, `tags`, `trash`,
`imports`, `backup`, or `required` (all hosted offline suites). Each run gets its
own directory under `artifacts/maestro/local/`, printed by the runner. Set
`MAESTRO_ARTIFACTS_DIR` to use another parent directory. The runner and hosted CI
share the same offline suite definitions.
To run several suites with one APK installation, pass e.g. `--suite "basics tags"`.
Each suite has its own results directory; a failure does not prevent the next
independent suite from running, and the command still exits unsuccessfully.

For a single flow, use Maestro directly, for example:
`maestro test -e APP_ID=io.ente.auth.independent maestro/auth/offline/settings.yaml`.

See the [test guide](docs/auth-test-rollout.md) for CI selection, adding flows,
diagnostics and online setup, and the [fixture guide](museum/fixtures/README.md)
for restoring or regenerating public test accounts.
