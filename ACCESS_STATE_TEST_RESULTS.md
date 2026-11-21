# Access-state test results

## Legacy-schema parity staging

| Test | Result |
|---|---|
| V2 login with `access-state-v1` | PASS — `active` |
| Pause through panel V2 endpoint | PASS — `license_paused` |
| `/api/app/session` while paused | PASS — `license_paused` |
| Same JWT after pause | PASS |
| Reactivation | PASS — `active` |
| V1/legacy schema compatibility | PASS — no access-state tables required |
| Production D1 modified | PASS — no |

The test account and credentials were synthetic. No production JWT, HWID, license, or personal data was used.

Full JWT-revocation, HWID, blocked-user, protected-endpoint, and remote-patch regression suites remain required before production deployment.
