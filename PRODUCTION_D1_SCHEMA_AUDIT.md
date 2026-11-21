# Production D1 schema audit

Read-only audit performed against `vini-v2-db`.

## Findings

- `users` exists and contains `is_paused`, `paused_at`, `license_expires_at`, and `session_version`.
- `users` does **not** contain `license_plan_enabled` or `provider_id`.
- No `access_controls`, `license_access_state`, `provider_maintenance`, `providers`, or `access_state_events` tables exist.
- No production writes, migrations, inserts, updates, deletes, or schema changes were executed.

The production schema is an older legacy schema. The repository's access-state migrations cannot be applied blindly because several columns are already present while the access-state structures are absent.
