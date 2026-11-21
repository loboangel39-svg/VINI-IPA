# Production gradual rollout metrics

## Current split

- `f9453977-aba6-4137-a07b-4c41b32ab578`: 10%
- `c5cb49ea-b669-4903-bc76-08608d26dc7e`: 90%

The split was not changed during this review.

## Observability limits

The installed Wrangler version exposes live `wrangler tail` with a `--version-id` filter, but no historical invocation/metrics command. No Cloudflare Analytics/Workers GraphQL integration is configured in this environment, so historical counts of requests, 5xx, exceptions, or D1 errors per version cannot be retrieved through the available CLI.

The anonymous endpoint check is not evidence of authenticated Login behavior. A synthetic production account cannot be created safely without writing a production D1 user/license/session record; the version preview URL would still use production bindings. Therefore no authenticated production test was performed.

## Recommendation

Maintain 10/90. Do not increase traffic until version-filtered Cloudflare observability or an approved synthetic production identity is available. Do not rollback based on an unverified regression; the isolated legacy-parity tests remain passing and no production error metric is available to compare.
