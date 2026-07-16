# Auth Maestro test rollout

This plan grows Auth coverage without making the first CI suite depend on an
Ente checkout, Museum, object storage, native file pickers, or hosted test
services.

## Baseline and compatibility rule

Evidence was checked on 2026-07-16 against Ente `upstream/main@2660f5dd65`,
the Auth UI branch `auth-ui-refresh@68bfe8ad89`, and the published
`auth-v4.4.25-beta` APK.

The CI target is the newest published `auth-v*-beta` APK from `ente/nightly`.
The package ID is `io.ente.auth.independent`.

Tests must pass against that published APK. Do not copy flows that rely on app
changes which have not reached the nightly build. In particular, the existing
Ente development suite uses semantics IDs and `enteauth://debug/*` deep links
from the Auth UI work. Those are useful for development and demos, but the
current nightly does not contain them.

Prefer, in order:

1. Stable semantics IDs present in the nightly build.
2. User-visible labels when an ID has not shipped yet.
3. Coordinate taps only for native system UI that exposes no stable selector.

Every behavior flow should create its own state through public app behavior or
a clearly named reusable subflow. Debug-only seeding is not a substitute for a
user-visible core-flow test.

## Rollout order

### Phase 0: CI bootstrap

Status: complete.

- Launch the published APK and verify onboarding.
- Enter offline mode, acknowledge the backup warning, and verify the empty
  home screen.
- Run both flows in one Maestro invocation on Android API 34.

These remain the required smoke gate for every workflow or runner change.

### Phase 1: offline core, no native picker or server

Add these in order. Keep them in the existing Android job until the measured
test time, excluding emulator boot, exceeds five minutes.

1. **Manual setup happy path**
   - Enter offline mode.
   - Add a GitHub TOTP account with a known valid secret.
   - Save it and verify the issuer, account, and generated code are visible.
   - Use a real issuer with an icon match; do not use a synthetic `Maestro`
     issuer.
2. **Manual setup validation and advanced fields**
   - Cover required-field validation.
   - Exercise algorithm, digits, period, and HOTP/TOTP selection without
     depending on a native picker.
3. **Single-code lifecycle**
   - Open code details, inspect its QR/dialog surfaces, edit the account and
     note, then verify the saved values.
   - Do not assert clipboard contents until clipboard access is proven stable
     on the hosted emulator.
4. **Reusable UI-only populated state**
   - Add three accounts through the app UI using famous issuers with known
     icons, for example GitHub, Stripe, and Dropbox.
   - Keep the helper small. A flow should seed only the state it needs.
5. **Home organization**
   - Search by issuer and account.
   - Exercise issuer/account/custom sorting and visible filters.
   - Verify the empty-search state and clearing the query.
6. **Tags and editing**
   - Create, attach, rename, and remove a tag.
   - Verify filtering by that tag and the result after removal.
7. **Trash and restore**
   - Trash a code, find it in Trash, and restore it.
   - Add permanent deletion only after its local-auth behavior is handled in
     Phase 2.
8. **Duplicate detection**
   - Add the same account twice through manual setup and verify the duplicate
     group.
   - Keep destructive duplicate cleanup out until authentication is stable.
9. **Settings without external navigation**
   - Verify the Data, Security, General, Support, About, and Theme structure.
   - Cover the version label, theme change, large-icon toggle, language list,
     and app-icon list.
   - Do not open FAQ, social, store, email, or browser links in this phase.

The settings flow should be added after the Auth UI work reaches a nightly.
Testing the old settings hierarchy immediately before it is replaced would
protect the wrong contract.

### Phase 2: offline platform integrations

Keep these separate from `offline-core` because failures can come from Android
system UI, permissions, biometric state, or filesystem setup.

1. App lock and local authentication.
2. Automatic local export, including password setup, folder selection, manual
   backup, and an on-device file assertion.
3. Import from Android Downloads/Files.
4. Google Authenticator migration import.
5. Other supported app imports, performed sequentially in one prepared state
   when that reduces repeated setup.
6. QR scanning, gallery selection, Android sharing, and external intents.

For imports, place fixtures in Android Downloads with `adb push` before the
flow. The test should still exercise Ente's native picker and import UI; the
host runner should not depend on an interactive desktop file chooser.

### Phase 3: Museum-backed Auth

Use a separate workflow and keep it manual until its provisioning is proven
repeatable. Passkeys are out of scope for the first online suite.

Museum can run without S3 for Auth-only tests. The Ente example configuration
explicitly allows the entire `s3` section to be omitted. Do not start MinIO or
configure buckets.

PostgreSQL is currently required: Museum opens the `postgres` driver and runs
PostgreSQL migrations, so SQLite is not a compatible replacement. Docker is
not required on GitHub-hosted Ubuntu runners:

1. Start the bundled PostgreSQL 16 service with
   `sudo systemctl start postgresql.service`.
2. Create a disposable Museum role and database.
3. Check out a pinned `ente/ente` revision and build Museum directly with Go.
4. Write a minimal local config containing only database credentials, fixed
   development crypto/JWT keys, `internal.silent: true`, and a hardcoded OTT
   suffix/value.
5. Start Museum as a background process and wait for `GET /ping`.
6. Point the Android app at `http://10.0.2.2:8080` through its developer
   settings.

Add online flows in this order:

1. Configure the endpoint and complete signup/basic login with a deterministic
   OTT.
2. Log in to a prepared account with TOTP two-factor authentication.
3. Reset a password with the recovery key and deterministic OTT.
4. Verify account settings and logout.

Use unique emails ending in the configured local suffix. Never scrape Museum
logs for verification codes, and never place passwords, recovery keys, or TOTP
secrets in GitHub summaries or uploaded plaintext logs.

### Phase 4: iOS and product demonstrations

- Port stable cross-platform flows to iOS after Android behavior is reliable.
- Keep demo/product-story flows separate from regression flows.
- Demo flows may reduce checks and add pacing, but they should compose already
  proven subflows instead of defining a second behavior implementation.

## Runner strategy

One Android runner is currently faster and cheaper because emulator setup is
about three minutes while the smoke flows take under thirty seconds.

Use the AOSP system image for offline suites. Add Google APIs or Play Store
images only when a tested behavior demonstrates that dependency; the heavier
Pixel Launcher image can introduce unrelated launcher ANRs.

Introduce at most two parallel Android jobs when `offline-core` itself exceeds
five minutes:

- `offline-core`: setup, lifecycle, search, tags, and trash.
- `offline-settings`: settings and other read-only surfaces.

Keep `offline-platform` and `museum-auth` in separate jobs because they have
different provisioning and failure modes. Do not shard individual short flows
or download and boot an emulator per flow.

## Failure reporting

The first reporting layer has no additional reporting service:

- Maestro emits JUnit plus flattened debug output.
- GitHub's job summary records the tested nightly, Android API, Maestro
  version, and outcome.
- A failed run uploads JUnit, Maestro logs, hierarchy dumps, and screenshots as
  `auth-maestro-diagnostics` for seven days.
- The workflow re-fails after reporting, so a captured failure cannot become a
  green check.

Add reporting incrementally:

1. Parse JUnit into a short list of failed flow names in the job summary. Do
   not copy raw command logs or entered values into the public summary.
2. Capture bounded Android logcat only when it has a demonstrated diagnostic
   use and can be scrubbed of sensitive values.
3. Record the emulator during platform flows, but retain video only on failure.
4. Keep product-demo recordings as explicit artifacts, not as failure output.

Do not automatically retry failed assertions. Maestro already waits for UI
conditions; blanket retries hide real regressions. Isolate and fix a flaky
selector or platform dependency before expanding the required suite.

## Promotion gates

A phase is ready to become required only when:

- every flow passes twice on a clean hosted runner;
- selectors exist in the published nightly, not only an unmerged app branch;
- failure artifacts identify the failing flow without exposing secrets;
- median job time and runner count remain proportionate to the covered risk;
- no external service is started unless a tested behavior needs it.
