# Auth test guide

## Build and CI contract

The Auth Android workflow resolves the newest Auth beta/RC APK in `ente/nightly`,
falling back to a stable `ente/ente` asset only when no prerelease is available.
Selection uses asset creation time, not tag publication time. The offline and
online runners each download that asset once and verify its SHA-256.

These are published-build tests. They do not build or validate unshipped Auth
changes from a product PR. One preparation job validates configuration, selects
suites, resolves the APK and checks its age. Offline and online jobs then run in
parallel, followed by a combined result that requires every selected group to pass.

| Trigger | Execution |
| --- | --- |
| Daily, 01:17 UTC | All hosted suites only if the resolved APK was created in the preceding 24 hours; otherwise an explicit skip summary. |
| Pull request matching workflow paths | Affected suites; shared helpers and fixture changes select the relevant full group. |
| Push to main matching workflow paths | All suites in each affected group. Online-only changes do not launch offline emulators, and vice versa. Documentation-only merges do not run tests. |
| Manual | All suites, the offline/online group, or one selected suite, regardless of APK age. |

The daily freshness check is not build deduplication and is subject to schedule
delays. Do not interpret a skipped run as fresh coverage.

There are four jobs in a full run: preparation, offline, online, and the final
result. Only the two test jobs run concurrently. Offline installs the APK once
and runs basics, organization, tags and trash sequentially in one emulator.
Online runs account auth, recovery, data sync and entity lifecycle sequentially
on one runner. Account auth and data sync each use one emulator session, recovery
uses two, and entity lifecycle uses three. Existing session boundaries are kept;
this consolidation does not assume that emulator restarts can be removed.

An independent suite still runs after an earlier suite fails. Dependent online
phases run only when their prerequisite succeeds, and any failure fails the job.
Suites have separate result paths and job-summary outcomes. This trades parallel
test execution for fewer repeated downloads and tool installations; compare
hosted elapsed time and runner-minutes before splitting a slow group again.

Both test jobs use Ubuntu 24.04 with required KVM acceleration, two virtual CPUs,
and 4 GiB Android guest memory.
Both groups pin emulator 37.1.11 (build `15917651`) with host OpenGL software
rendering (`LIBGL_ALWAYS_SOFTWARE=1`), a virtual X display, and guest Vulkan
disabled. A change to this shared configuration requires both hosted groups to pass.

## Adding or changing a flow

1. Test user-visible behavior and create only the state it needs.
2. Prefer action-oriented semantics identifiers, then visible labels. Use
   coordinates only when the control cannot be targeted reliably otherwise.
3. Wait for a meaningful ready state. Required checks must not be wrapped in
   `when: visible`; reserve conditional flows for optional guidance or known
   starting states.
4. Reuse a small subflow for a stable interaction, not a generic sequence that
   hides product state. Keep product demos separate from regression flows.
5. Register hosted flows in `scripts/suites.py` and new online phases in
   `scripts/run-auth-online.sh`.
   Registration checks catch unreachable flows. Imports and local backups are
   explicit local-only exceptions.
6. Run local configuration checks and the smallest affected device suite before
   pushing. There is no need to dispatch CI for documentation-only cleanup.

```sh
python3 -m unittest discover -s scripts/tests
scripts/tests/apk.sh
scripts/tests/runners.sh
scripts/fixtures/verify-auth-fixture.sh
```

The helper tests mock downloads and devices; they do not contact GitHub, launch
emulators or need Museum. The [README](../README.md#run-locally) has the device
runner command.

## Script boundaries

| Entry point | Responsibility |
| --- | --- |
| `scripts/suites.py` | One suite registry for local execution and CI change selection. Python standard library only. |
| `scripts/apk.sh` | Resolve release metadata, download a resolved asset, or fetch the latest APK locally. |
| `scripts/install-maestro.sh` | Install the exact CLI archive into the GitHub runner's temporary directory. |
| `scripts/run-auth-android-local.sh` | Prepare an Android device and run offline suites, locally or on CI. |
| `scripts/run-auth-online.sh` | Run online phases against a prepared Museum fixture. |
| `scripts/run-maestro.sh` | Shared Maestro invocation, JUnit requirement and post-run device health check. |
| `scripts/current-totp.py` | Generate a public-fixture TOTP without an additional package or Node runtime. |
| `scripts/fixtures/` | Deliberate fixture regeneration/restore, verification and native local Museum lifecycle. |
| `scripts/verify-local-auth-backups.sh` | Inspect local backup files; not a backup-restore test. |
| `scripts/tests/` | Fast host checks for selectors, APK handling, TOTP and runners. |

Keep orchestration in the workflow and reusable behavior in these scripts. Do not
add forwarding wrappers or create a generic command framework for unrelated tasks.

## Workflow dependencies and security

- Keep `contents: read` as the default token permission; the final result job
  needs no token permissions. Checkout must not persist credentials. Do not run
  pull-request code with elevated permissions through `pull_request_target`.
- Pin actions to full commit SHAs, with the release version in a comment. Pin
  backend images by digest. Review upstream changes and security advisories
  before updating either, and run the affected suites.
- Maestro's [installation guide](https://docs.maestro.dev/maestro-cli/how-to-install-maestro-cli)
  offers a shell installer, Homebrew and release archives. CI deliberately uses
  the official release archive with a fixed version and SHA-256, then checks the
  installed version. This avoids executing a changing installer or adding a
  third-party setup action. Update the version and checksum together after
  verifying the upstream release; use the same CLI version locally.
- Resolve the Auth APK once, pass compact metadata to each test runner, and verify
  each download against the release asset digest. An API error must fail the
  run, not silently select a stable build. Stable fallback is only for an absent
  compatible prerelease.
- Pass event data through quoted environment variables, not interpolated shell
  commands. Keep private signup credentials masked and out of uploaded traces;
  public-fixture diagnostics have a separate, restricted upload scope.

These conventions follow GitHub's [secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use).
They do not make pull-request code trusted: fork contributions still need review
before approval to run. No production secrets or accounts belong in this repo.

## Online fixture setup

Restore the [public Museum fixture](../museum/fixtures/README.md) before each
independent suite. Data sync and entity lifecycle mutate the same basic account,
so sharing their modified backend state would make execution order significant.
Reuse the existing restore helper, which recreates the local stack; there is only
one stack running at a time. Preserve backend state between phases within a suite.
The fixture generator is for deliberate refreshes, not normal test runs.

Hosted and local Docker setup use the same pinned Museum and PostgreSQL images.
The native macOS fixture scripts remain available for local use. Neither path
needs production services or object storage.

The online runner defaults to a rootable emulator and seeds only the endpoint
and guidance/screen-cover preferences in Flutter's preferences file. Login and
subsequent account operations still happen through the UI. For a non-rooted
device, use `AUTH_APP_PREPARATION=ui` and an endpoint reachable from that device;
the UI endpoint-setup subflow replaces preference seeding.
For a USB-connected Android device, `adb -s <serial> reverse tcp:8080 tcp:8080`
lets the app use `http://127.0.0.1:8080` without using the host's LAN address.

Keep the real offline warning in onboarding tests. Do not require Auth to show a
2FA-settings status solely for a test: the live login challenge tests that behavior.

## Results and diagnostics

- Manually select the online `startup` suite to inspect cold startup without
  entering credentials. It uses the same emulator, backend, and preference
  preparation as the online suites, waits up to 60 seconds for `Log in`, and
  stops at the empty email screen. Its three-day diagnostic artifact includes
  Maestro command timings, screenshots, UI hierarchy, and device logs. It is
  excluded from scheduled/full-suite runs; a pass is not authentication coverage.
- CI pins Maestro 2.10.0 and its archive checksum in `scripts/install-maestro.sh`.
  Use the same version locally when validating an upgrade.
- Local runners and CI disable analytics and route Maestro's API to loopback.
  The analytics opt-out alone does not disable exception-report uploads
  ([upstream issue](https://github.com/mobile-dev-inc/Maestro/issues/3488)).
  This repository does not use Maestro Cloud.
- The preparation summary records immutable APK provenance and selected suites.
  Each suite reports its outcome and JUnit artifact; the final result checks both groups.
- JUnit results are retained for seven days.
- Local runners create a separate artifact directory for each invocation;
  reruns do not mix reports or debug files from different attempts.
- Offline failures retain Maestro diagnostics for seven days.
- Online failures retain runtime health for three days. Device state and app
  memory and Museum logs are captured inside the runner before emulator teardown
  and before the next fixture restore. Workflow-level diagnostics provide host
  memory/disk information.
- Hosted and local runners share `scripts/run-maestro.sh`. Each invocation must
  produce a nonempty JUnit report and leave the device responsive;
  Maestro can otherwise report success after a crash during driver cleanup.
- Online public-fixture suites retain failure screenshots and traces for three
  days. Their credentials are already checked in. The account-auth suite uploads
  only its public TOTP fixture phases, never the private signup/login phases.

Coverage descriptions live in the README; executed outcomes live in Actions,
not hand-edited green badges. Keep app bugs and performance investigations in
product issues rather than growing a chronological troubleshooting log here.

## Promoting platform coverage

Imports and local backups stay local-only until they work reliably on the hosted
Android runtime. Backup restore remains a coverage gap; encrypted JSON fields
alone do not prove a usable backup. Promote a flow after its selectors and device
behavior are validated, then require a clean hosted run before claiming coverage.

## App follow-ups

### Tag-sheet accessibility

On APK asset `551456158` (created September 8, 2026), creating a long tag
(`FixturePersisted`) beside `Work` makes the tag chips wrap. After the sheet grows,
the reported accessibility bounds remain below the rendered controls: Maestro
taps below `Done`, leaving the sheet open. Waiting ten seconds does not fix the
mismatch. See the [captured failure](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/34350696836).

Online fixtures use short tags (`CI`, `Flow`) to keep this sheet on one row.
Bulk edits and fresh-login persistence remain asserted; wrapped-sheet
accessibility is **not covered**. Investigate the sheet's semantics after dynamic
resizing in Auth/Flutter, and restore a long-tag regression once fixed.

### Progress-dialog lifecycle

[Recovery diagnostics](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/34352639810)
captured `ProgressDialog.hide()` throwing a null-check error and leaving
`Please wait...` over the recovery page after email verification succeeded.
The shared dialog uses global context/state and a fixed 200 ms delay for readiness.
Replace that with per-dialog lifecycle ownership and test dismissal before the
first frame. A local widget test reproduced a retained dialog by awaiting
`show()` and `hide()` before pumping its first frame. The Maestro flow does not
dismiss stuck progress dialogs.
