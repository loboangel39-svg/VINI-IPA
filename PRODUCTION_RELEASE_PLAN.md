# Production release plan

## Current state

Production remains at `c5cb49ea-b669-4903-bc76-08608d26dc7e` with 100% traffic. The new compatibility code is not deployed.

## Proposed release

1. Review the Worker-only diff in the compatibility commit.
2. Run `node --check` and `wrangler deploy --dry-run` with production bindings.
3. Upload a version, verify D1/R2 bindings and secret names, then deploy 100% only after explicit approval.
4. Verify anonymous rejection, synthetic/staging regression evidence, and production error rate.

No migration, D1 write, R2 operation, license update, session invalidation, or patch assignment change is part of this release.

## Rollback

```powershell
npx wrangler versions deploy c5cb49ea-b669-4903-bc76-08608d26dc7e --name vini-v2-api
```

Rollback changes traffic only and does not revert data.
