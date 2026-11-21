# Pause persistence audit

## Panel routes

- Legacy table action: `POST /api/users/:id/pause` toggles `users.is_paused`.
- V2 access-state action: `POST /api/access-state/users/:id/pause` writes `license_access_state.individual_pause`.
- The panel's V2 user controls use the second route.

On production, the second route cannot work because its table and its original `SELECT` columns are absent. The existing production-compatible pause field is `users.is_paused`, with `paused_at` available for audit metadata.

The proposed compatibility fallback writes only `users.is_paused`, `users.paused_at`, and `updated_at`; it does not alter expiry, HWID, session version, plans, or patches.
