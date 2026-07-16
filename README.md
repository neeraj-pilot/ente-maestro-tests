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
