# Ente Maestro tests

Maestro smoke and end-to-end tests that run against published Ente apps.

The initial Android workflow downloads the newest `auth-v*-beta` APK from
[`ente/nightly`](https://github.com/ente/nightly/releases), verifies its
checksum, and runs two offline smoke flows on a local GitHub Actions emulator.
It does not build Ente, start Museum, or use Maestro Cloud.

The workflow runs when its test files change and can also be started manually.
Failed runs retain Maestro diagnostics for seven days.

See the [Auth test rollout plan](docs/auth-test-rollout.md) for the order in
which offline, platform-integrated, and Museum-backed coverage will be added.
