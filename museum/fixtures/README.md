# Auth Museum fixture v1

This directory contains a public, disposable Museum database fixture for Auth
Maestro tests. Its identities, passwords, recovery keys, and TOTP seed are test
data committed in [`public-test-credentials.json`](public-test-credentials.json)
on purpose. Never restore this fixture to a shared or production environment.

The three accounts have stable, visibly synthetic `@example.org` identities:

- `basic`: password login and account settings
- `totp`: password login followed by a live TOTP challenge
- `recovery`: recovery-key password reset, old-password rejection, and login
  with the replacement password

Normal CI restores the checked-in PostgreSQL dump and does not compile Ente.
The generator is reserved for deliberate fixture refreshes and pins both the
Ente source revision and container image digests recorded in
[`manifest.json`](manifest.json).

## Restore locally

Restoration is destructive for the selected Compose project, so the explicit
guard is required:

```sh
ALLOW_AUTH_FIXTURE_RESTORE=1 \
  AUTH_FIXTURE_COMPOSE_PROJECT=ente-auth-fixture \
  scripts/fixtures/restore-auth-fixture.sh
```

This verifies the dump checksum and metadata, creates fresh PostgreSQL storage,
restores exactly three tagged accounts including one TOTP account, and starts
Museum on `http://127.0.0.1:8080`.

Remove the local stack with:

```sh
docker compose --project-name ente-auth-fixture \
  --file museum/compose.yaml down --volumes --remove-orphans
```

## Regenerate deliberately

From a clean local Docker environment, run:

```sh
scripts/fixtures/generate-auth-fixture.sh
```

The script creates all accounts through Ente's real Auth flow, captures the
generated recovery and TOTP material, dumps PostgreSQL, destroys the source
database, restores the dump into a fresh project, and verifies password and
TOTP login against the restored Museum. Review every generated file together;
the dump, checksum, manifest, and credentials are one atomic fixture revision.

Regenerate only when the fixture contract changes or a pinned Ente/Museum
revision can no longer restore and authenticate successfully. Do not regenerate
merely to refresh timestamps or secrets.
