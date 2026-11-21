# Paused flow evidence

## First divergence

| Layer | Before correction | After staging correction |
|---|---|---|
| Panel endpoint | `/api/access-state/users/:id/pause` | same |
| D1 write | `license_access_state.individual_pause = 1` | same |
| Worker calculation (`license_plan_enabled = 0`) | `active` due legacy gate | `license_paused` for access-state clients |
| `/api/app/session` | `access.status = active` | `access.status = license_paused` |
| JWT | valid | valid and retained |
| App routing | Home | `PausedLicenseView` when the updated IPA receives the response |

The staging test used a synthetic account only. No JWT, password, HWID, or personal data is included here.

## Client audit

`LoginManager.verifyStoredSession` calls `/api/app/session` with `access-state-v1`, parses `access.status`, and reports it through `StoredSessionResult.valid`. `App.swift` assigns that result to its single `@State accessState`; its root switch gives `license_paused` priority over `ContentView`. `clearSession()` is only called for revoked/expired/unauthorized paths.

The client already had opening, foreground, and 60-second checks. No additional polling or interface change was required for this root cause.
