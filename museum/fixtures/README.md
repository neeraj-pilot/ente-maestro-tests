# Auth Museum fixture v2

This directory contains a public, disposable Museum database fixture for Auth
Maestro tests. Its identities, passwords, recovery keys, and TOTP seed are test
data committed in [`public-test-credentials.json`](public-test-credentials.json)
on purpose. Never restore this fixture to a shared or production environment.

The three accounts have stable, visibly synthetic `@example.org` identities:

- `basic`: password login, account settings, four active codes, and one trashed
  code for sync and mutation coverage
- `totp`: password login followed by a live TOTP challenge, with one synced code
- `recovery`: recovery-key password reset, old-password rejection, login with
  the replacement password, and one code that must survive the reset

The seven Auth entities use familiar issuers (`GitHub`, `Google`, `Microsoft`,
`Stripe`, and `Dropbox`) so icon matching is exercised alongside stable
`@example.org` account labels, tags, notes, pin state, and trash state.

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
restores exactly three tagged accounts, three Auth data keys, seven encrypted
entities, and one TOTP account, then starts Museum on
`http://127.0.0.1:8080`.

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
generated recovery and TOTP material, creates every Auth data key and entity
through Museum's real authenticated APIs, dumps PostgreSQL, destroys the source
database, restores the dump into a fresh project, and verifies password/TOTP
login plus exact client-side decryption of every entity. Review every generated
file together; the dump, checksum, manifest, and credentials are one atomic
fixture revision.

Regenerate only when the fixture contract changes or a pinned Ente/Museum
revision can no longer restore and authenticate successfully. Do not regenerate
merely to refresh timestamps or secrets.
