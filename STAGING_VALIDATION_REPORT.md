# Staging validation — paused access

Date: 2026-11-21

## Isolated resources

- Worker: `vini-v2-api-staging-20261121`
- URL: `https://vini-v2-api-staging-20261121.loboangel39.workers.dev`
- D1: `vini-v2-db-staging-20261121`
- R2: `vini-patches-staging-20261121`
- D1 ID: recorded only in `wrangler.staging.toml`; it is not a production resource.
- Secrets: generated independently for staging; no production secret was read or copied.

## Results

| Test | Result |
|---|---|
| V2 login with `access-state-v1` | PASS — `active` |
| Valid JWT + administrative pause | PASS — session remained valid and returned `license_paused` |
| Protected endpoint while paused | PASS — HTTP 423 |
| Reactivation with same session | PASS — `active` without new login |
| Session version revocation | PASS — HTTP 401 |
| V2 maintenance | PASS — `maintenance` |
| V1 active login without access capability | PASS — valid and no `access` field |
| Production Worker changed | PASS — no |
| Production D1/R2 changed | PASS — no |

The pause was reproduced in staging by changing only the staging user's `is_paused` flag. No real license or production record was used.

## Follow-up root cause reproduction

The administrative V2 route is `/api/access-state/users/:id/pause` and writes `license_access_state.individual_pause`. The legacy table route is `/api/users/:id/pause` and writes `users.is_paused`.

Before the follow-up correction, a test account with `license_plan_enabled = 0` returned `active` from the access-state calculation even after the V2 pause route. This was the first divergence: the pause was stored, but `getAccessState` exited through the legacy compatibility branch before reading access controls.

The minimal staging correction passes an explicit access-state-client flag only from `/api/app/session`, the V2 app authorization gate, and `/api/app/validate-license`. Administrative and legacy calculations retain the pilot gate. After redeployment, the same `license_plan_enabled = 0` test account returned `license_paused`, then `active` after resume, with the same JWT.

## Client audit

`LoginManager` sends `X-VINI-Capabilities: license-plan-v1,access-state-v1` on license validation and stored-session verification. `App.swift` routes `maintenance` and `license_paused` before `ContentView`. `clearSession()` is only reached for revoked/invalid session paths; an authenticated `license_paused` result returns from session validation without clearing the session.

Remote patch synchronization remains guarded by the existing `5575bf1` policy: legacy `access == nil` is allowed, while explicit blocking states are suppressed. No patch engine files changed.

## Production rollout (not executed)

After approval and a production maintenance window, upload the reviewed Worker using the production `wrangler.toml`, then deploy the new version. The rollback target is version `27fa60ce-4431-4135-abef-d2a6047a4866`.

Production deployment remains intentionally pending approval.
