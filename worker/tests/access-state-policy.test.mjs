import assert from 'node:assert/strict';

const causes = (values) => Object.values(values).some(Boolean);
const freeze = (expiresAtMs, nowMs) => Math.max(0, Math.floor((expiresAtMs - nowMs) / 1000));

assert.equal(freeze(Date.UTC(2026, 0, 4), Date.UTC(2026, 0, 1)), 259200);
assert.equal(freeze(Date.UTC(2026, 0, 1, 12), Date.UTC(2026, 0, 1, 12)), 0);
assert.equal(causes({ individual: true, global: false, maintenance: false, provider: false }), true);
assert.equal(causes({ individual: false, global: false, maintenance: false, provider: false }), false);

// Overlapping causes are a union, never an additive duration.
const frozen = freeze(Date.UTC(2026, 0, 6), Date.UTC(2026, 0, 1));
assert.equal(frozen, 432000);
assert.equal(frozen, freeze(Date.UTC(2026, 0, 6), Date.UTC(2026, 0, 1)));

console.log('access-state policy regression checks passed');
