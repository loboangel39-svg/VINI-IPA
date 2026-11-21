# Access-state compatibility plan

## Selected approach

Use the existing production `users.is_paused` field for individual pause when access-state tables are absent. The Worker detects the presence of all access-state tables before querying them.

V2 app requests still receive `access.status = license_paused` or `active`; V1 requests retain their legacy contract. A missing schema never becomes `active` by accident: the legacy fallback only reports the existing `is_paused`/expiry state.

Global maintenance, provider maintenance, frozen-time accounting, and access event history require the absent access-state schema and remain explicitly unavailable until a separately approved additive migration.

## Required Worker changes

- `getAccessState`: schema preflight and legacy fallback.
- `handleGetUserAccessState`: schema-compatible user lookup.
- `handleSetUserPause`: schema-compatible lookup and legacy pause write.

No D1 migration is required for individual pause/reactivation.
