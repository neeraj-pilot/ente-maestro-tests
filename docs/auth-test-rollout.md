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

Hosted and promotion-candidate tests must pass against that published APK. Do
not copy flows that rely on app changes which have not reached the nightly
build. In particular, the existing Ente development suite uses semantics IDs
and `enteauth://debug/*` deep links from the Auth UI work. Those are useful
for development and demos, but only IDs actually exposed by the installed
nightly may be used. The current universal APK exposes refreshed form IDs on
the hosted x86_64 emulator while its arm64 UI still needs a small legacy
fallback.

Local-only platform checks may target an explicit current-source debug APK
when the nightly lacks the required UI. They must create public state, use no
debug deep links, and be labeled local-only. They cannot count as published
nightly or required CI coverage.

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

These remain the required smoke gate for every workflow or runner change. Pull
requests run only the affected hosted suite, except shared helpers, onboarding,
and workflow changes, which run the full matrix. Every merge to `main` runs the
full hosted matrix before its result is recorded in the README.

### Phase 1: offline core, no native picker or server

Add these in order. Keep them in the existing Android job until the measured
test time, excluding emulator boot, exceeds five minutes.

1. **Manual setup happy path**
   - Status: complete on Android. Promoted after two clean hosted runs of
     `3c4cb51` on 2026-07-16: [push](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29504146339)
     and [repeat](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29504375068).
   - Enter offline mode.
   - Add a GitHub TOTP account with a known valid secret.
   - Save it and verify the issuer, account, and generated code are visible.
   - Use a real issuer with an icon match; do not use a synthetic `Maestro`
     issuer.
2. **Manual setup validation and advanced fields**
   - Status: complete on Android. Promoted after two clean hosted runs of
     `9a48bab` on 2026-07-16: [push](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29505095659)
     and [repeat](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29505610153).
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
   - Status: complete on Android. Promoted after two clean hosted matrix runs:
     [first](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29524172187)
     and [repeat](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29524701204).
   - Search by issuer and account.
   - Exercise issuer/account/custom sorting and visible filters.
   - Verify the empty-search state and clearing the query.
6. **Tags and editing**
   - Status: tag creation and filtering are complete on Android. Promoted
     after two clean hosted tag shards in
     [29527901812](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29527901812)
     and [29528427436](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29528427436).
     Rename/delete remain deferred because the published nightly exposes a
     different selected-tag overflow surface than the refreshed source UI.
   - Next: cover attach, rename, and remove once the published overflow
     surface is stable; the current promoted flow verifies create and filter.
7. **Trash and restore**
   - Trash a code, find it in Trash, and restore it.
   - Add permanent deletion only after its local-auth behavior is handled in
     Phase 2.
8. **Duplicate detection**
   - Status: complete on Android. The full hosted matrix passed on
     [29555954743](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29555954743),
     then again after merge to `main` on
     [29556312742](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29556312742).
   - Add the same account twice through manual setup and verify the duplicate
     group without deleting it. Destructive cleanup remains deferred until
     local authentication is stable.
9. **Settings without external navigation**
   - Status: complete on Android. Promoted after two clean hosted settings
     shards in [29526305068](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29526305068)
     and [29526973851](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29526973851).
     Assertions use the published nightly's visible labels and page titles;
     they do not require development-only semantics IDs.
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
2. Automatic local export
   - Status: complete as local-only ARM64 Android API 34 coverage with Maestro
     `2.6.1` against the current source debug APK. The flow creates public
     offline state, enables automatic backups, sets a password and folder,
     creates a manual backup, then verifies both automatic and manual JSON
     files contain encrypted backup fields without the test account in
     plaintext.
   - Promotion requires a nightly that exposes the controls and two clean
     hosted runs. It is not part of the required hosted gate.
3. Import from Android Downloads/Files. The combined plain-text and Google
   Authenticator flow is implemented in `maestro/auth/offline/imports.yaml`
   and passes on the local ARM64 API 34 emulator. It is intentionally not in
   the required GitHub x86_64 smoke matrix yet: the published nightly returns
   from the x86 DocumentsUI picker with an unreadable selected-file path,
   producing a false `Could not parse the selected file` failure. Keep this
   flow for ARM64/physical-device validation until the picker/runtime
   combination is fixed; do not mark the x86 smoke workflow green by hiding
   the assertion.
4. Google Authenticator migration import.
5. Other supported app imports, performed sequentially in one prepared state
   when that reduces repeated setup.
6. QR scanning, gallery selection, Android sharing, and external intents.

For imports, place fixtures in Android Downloads with `adb push` before the
flow. The test should still exercise Ente's native picker and import UI; the
host runner should not depend on an interactive desktop file chooser.

### Phase 3: online Auth with a local Museum dependency

Use a separate workflow and keep it manual until its provisioning is proven
repeatable. Passkeys are out of scope for the first online suite.

Museum can run without S3 for Auth-only tests. The Ente example configuration
explicitly allows the entire `s3` section to be omitted. Do not start MinIO or
configure buckets.

PostgreSQL is currently required: Museum opens the `postgres` driver and runs
PostgreSQL migrations, so SQLite is not a compatible replacement. The first
workflow uses digest-pinned public Museum and PostgreSQL images. This avoids an
Ente checkout, a server build, MinIO, and hosted services while keeping the
server revision reproducible:

1. Start the two containers with the checked-in minimal config.
2. Wait for `GET /ping` without printing Museum request logs.
3. Point the Android app at `http://10.0.2.2:8080` through its developer
   settings.

Add online flows in this order:

1. Configure the endpoint and complete signup/basic login with a deterministic
   OTT. Status: complete for the current published nightly. The three-flow
   Auth suite passed twice on clean hosted Android runners on 2026-07-16:
   [first run](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29522907722)
   and [repeat](https://github.com/neeraj-pilot/ente-maestro-tests/actions/runs/29523464564).
   It covers unknown-account error handling, signup with OTT and recovery-key
   acknowledgement, then password login after a fresh app state.
2. Log in to a prepared account with TOTP two-factor authentication.
3. Reset a password with the recovery key and deterministic OTT.
4. Verify account settings and logout after the Logout action is exposed by the
   published nightly on the hosted x86 emulator. The current nightly's
   accessibility hierarchy omits Logout and places Delete account in its slot,
   so CI does not make a false logout assertion; this remains a tracked Auth UI
   compatibility item.

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

## App and runner follow-up backlog

This is a deliberately small, evidence-backed list from the Auth Android
rollout. It separates observed defects from improvements that would make
local iteration, demos, and hosted tests faster and more deterministic.

### Confirmed app defects

1. **Plain-text import can overstate how many codes were added.**
   `mobile/apps/auth/lib/ui/settings/data/import/import_flow.dart` returns the
   number of parsed codes after it calls `CodeStore.addCode`, but ignores an
   `AddResult.duplicate`. The success sheet therefore says that duplicate
   entries were imported even though they were rejected. Count only accepted
   results, and add a regression that imports the same fixture twice and
   expects zero newly added codes on the second import. The Google importer
   already demonstrates the intended duplicate-aware behavior.
2. **File import assumes every selected Android file has a readable path.**
   `pickAndProcessImportFile` dereferences `PlatformFile.path`. On the hosted
   x86_64 emulator, DocumentsUI can return a selection whose path is not
   readable by Auth, producing “Could not parse the selected file” for a valid
   fixture. The app should accept a path when available and otherwise process
   the returned bytes (or copy them to an app-owned temporary file), with
   explicit size bounds and cleanup ownership. That is the prerequisite for
   promoting import coverage to hosted CI.

### App changes that improve testability without weakening production UX

1. Ship stable, action-oriented semantics identifiers for the offline entry
   action, backup-warning confirmation, select all, Pin/Unpin, Add tag, Trash,
   tag-name input, and tag creation/Done actions. Keep the public labels as a
   fallback; do not expose account names, OTP values, passwords, or recovery
   material as identifiers.
   - Observed compatibility gap: the published `auth-v4.4.25-beta` exposed a
     visible Select all action on local ARM64, but not in the hosted x86_64
     selection hierarchy. Both surfaces exposed the selection count and Add
     tag. Until the action has a shared shipped identifier, cross-platform
     coverage should select two accounts individually; this is not a data
     mutation defect, but it makes selector-based tests non-portable.
   - The hosted x86_64 accessibility value for `auth_selection_count` currently
     duplicates its visible label (for example, `2 selected\n2 selected`).
     Expose the count once so assistive technology and exact selectors receive
     the same value; until then, tests use a count-specific multiline regex.
2. Keep onboarding tips and safety warnings in production. Their primary
   actions should be identifiable and dismissible through semantics. A
   debug-only/demo build may opt out of one-time education after exercising it
   in a regression flow; the published-nightly gate must still exercise the
   real warning at least once.
3. Keep the existing debug code-seeding/deep-link hooks local to debug builds.
   They are useful for fast pre-push exploration but must never replace
   public-UI setup in the hosted release test.
4. For time-dependent OTP UI, test the resulting visible state rather than a
   full animation settling. If a deterministic clock is added for debug builds,
   keep it build-gated and use it only for local development tests.

### CI changes that improve reproducibility and cost

1. Install the exact Maestro version declared by the workflow. The workflow
   currently reports `2.6.1` but its installer fetches the latest CLI. Download
   and checksum the requested release instead, then report the actual binary
   version.
2. Resolve the Auth nightly tag once in the selector job and pass that immutable
   tag to every matrix shard. Today each shard independently asks for the
   newest release, so a new nightly published mid-matrix can make one workflow
   test different APKs.
3. Retain targeted pull-request selection and a full `main` matrix. Before
   changing the number of shards, record emulator boot time, test duration, and
   runner-minutes from several clean runs. Do not combine unrelated suites just
   to reduce job count if that makes failures slower to reproduce.
4. Keep per-flow public setup and avoid generic retries. The re-launch in the
   shared offline-entry helper is a narrow recovery for a cleared-state app
   that was not foregrounded; it is not an assertion retry.

### Next coverage increments

1. Add a public offline **bulk edit** flow: create GitHub and Stripe accounts,
   long-press one, select all visible accounts, apply a newly created `Finance`
   tag, then filter by that tag and verify both accounts. This proves selection,
   mutation across multiple codes, and the visible result without destructive
   cleanup.
2. Add bulk trash and bulk restore as a separate follow-up after the tag flow
   is stable. It should prove the selection count, confirmation, Trash list,
   and restoration, while continuing to avoid permanent deletion.
3. Once the two import defects are fixed, promote the existing sequential
   plain-text and Google Authenticator import flow to hosted Android and add
   the duplicate-count regression above.

## Promotion gates

A phase is ready to become required only when:

- every flow passes twice on a clean hosted runner;
- selectors exist in the published nightly, not only an unmerged app branch;
- failure artifacts identify the failing flow without exposing secrets;
- median job time and runner count remain proportionate to the covered risk;
- no external service is started unless a tested behavior needs it.
