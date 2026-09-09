# Auth test guide

## Build and CI contract

Each hosted workflow resolves the newest Auth beta/RC APK in `ente/nightly`,
falling back to a stable `ente/ente` asset only when no prerelease is available.
Selection uses asset creation time, not tag publication time. Every shard within
that workflow receives the same asset ID and verifies its SHA-256.

These are published-build tests. They do not build or validate unshipped Auth
changes from a product PR. Offline and online workflows resolve independently.

| Trigger | Execution |
| --- | --- |
| Daily, 01:17 UTC | Full hosted matrix only if the resolved APK was created in the preceding 24 hours; otherwise an explicit skip summary. |
| Pull request matching workflow paths | Affected suites; shared helpers and fixture changes select the relevant full matrix. |
| Push to main matching workflow paths | Full matrix for each triggered workflow. Documentation-only merges do not run tests. |
| Manual | Full matrix or one selected suite/lane, regardless of APK age. |

The daily freshness check is not build deduplication and is subject to schedule
delays. Do not interpret a skipped run as fresh coverage.

Offline uses five Ubuntu shards. Online uses four Ubuntu lanes with required
KVM acceleration, two virtual CPUs, and 4 GiB Android guest memory. Account auth
and data sync each use one emulator session, recovery uses two, and entity
lifecycle uses three.

## Adding or changing a flow

1. Test user-visible behavior and create only the state it needs.
2. Prefer action-oriented semantics identifiers, then visible labels. Use
   coordinates only when the control cannot be targeted reliably otherwise.
3. Wait for a meaningful ready state. Required checks must not be wrapped in
   `when: visible`; reserve conditional flows for optional guidance or known
   starting states.
4. Reuse a small subflow for a stable interaction, not a generic sequence that
   hides product state. Keep product demos separate from regression flows.
5. Register hosted offline flows in `scripts/select-auth-ci-suites.sh`, or online
   phases in `.github/scripts/run-auth-online-tests.sh` and their lane selector.
   Registration checks catch unreachable flows. Imports and local backups are
   explicit local-only exceptions.
6. Run local configuration checks and the smallest affected device suite before
   pushing. There is no need to dispatch CI for documentation-only cleanup.

```sh
scripts/test-select-auth-ci-suites.sh
scripts/test-select-auth-online-lanes.sh
scripts/test-hosted-flow-registration.sh
scripts/test-resolve-nightly-apk.sh
scripts/test-ci-helpers.sh
scripts/fixtures/verify-auth-fixture.sh
```

The helper tests mock downloads and devices; they do not contact GitHub, launch
emulators or need Museum. The [README](../README.md#run-locally) has the device
runner command.

## Online fixture setup

Restore the [public Museum fixture](../museum/fixtures/README.md) before each
independent lane. Preserve backend state between phases within a lane. The
fixture generator is for deliberate refreshes, not normal test runs.

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

- Manually select the online `startup` lane to inspect cold startup without
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
- Each job summary records immutable APK provenance, suite and outcome.
- JUnit results are retained for seven days.
- Local runners create a separate artifact directory for each invocation;
  reruns do not mix reports or debug files from different attempts.
- Offline failures retain Maestro diagnostics for seven days.
- Online failures retain runtime health for three days. Device state and app
  memory are captured inside the runner before emulator teardown. Workflow-level
  diagnostics provide host memory/disk information and the local Museum log.
- Online public-fixture lanes retain failure screenshots and traces for three
  days. Their credentials are already checked in. The account-auth lane does not
  upload Maestro debug output because signup generates a private test password.

Coverage descriptions live in the README; executed outcomes live in Actions,
not hand-edited green badges. Keep app bugs and performance investigations in
product issues rather than growing a chronological troubleshooting log here.

## Promoting platform coverage

Imports and local backups stay local-only until they work reliably on the hosted
Android runtime. Backup restore remains a coverage gap; encrypted JSON fields
alone do not prove a usable backup. Promote a flow after its selectors and device
behavior are validated, then require a clean hosted run before claiming coverage.

## Tag-sheet accessibility limitation

On APK asset `551456158` (created September 8, 2026), creating a long tag
(`FixturePersisted`) beside `Work` makes the tag chips wrap. After the sheet grows,
the reported accessibility bounds remain below the rendered controls: Maestro
taps below `Done`, leaving the sheet open. Waiting ten seconds does not fix the
mismatch. See the [captured failure](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/34350696836).

Online fixtures use short tags (`Synced`, `Flow`) to keep this sheet on one row.
Bulk edits and fresh-login persistence remain asserted; wrapped-sheet
accessibility is **not covered**. Investigate the sheet's semantics after dynamic
resizing in Auth/Flutter, and restore a long-tag regression once fixed.
