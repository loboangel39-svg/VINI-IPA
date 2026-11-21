# Staging schema parity report

Created isolated parity resources:

- Worker: `vini-v2-api-parity-20261121`
- D1: `vini-v2-db-prod-parity-20261121`
- R2: existing isolated staging bucket only

The parity D1 contains a synthetic production-shaped `users` table and `activity_log`, but no access-state tables or pilot columns. No production data was copied.

The uncorrected Worker reproduced HTTP 500 during V2 validation. After the fallback and handler lookup changes, the same account completed login, pause, session refresh, reactivation, and session refresh successfully.
