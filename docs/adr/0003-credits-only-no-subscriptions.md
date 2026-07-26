# Credits only — no subscriptions

Monetisation is one-off Credit Packs, not a subscription, even though "a couple of quid a month" was the original pitch. Reasons: meeting processing is lumpy, discrete usage, which packs fit and subscriptions punish; a stranger will hand £5 once to a brand-new product but won't grant it recurring card access; and credits skip the entire subscription state machine (cancellation, dunning, active-subscriber logic). Credits monetise curiosity; subscriptions monetise retention we can't yet demonstrate.

One Credit is consumed per successful Extraction only — failures are never charged. New accounts are seeded with one free Credit, because nobody pays before seeing their own transcript converted.

## Consequences

- The ledger is deliberately subscription-ready: credits are an integer plus a transactions table, so adding a monthly tier later requires no migration of the model.
- Revisit subscriptions only when usage data shows habitual (e.g. weekly) pack-burning — then the data also tells us the price.
- Pack pricing (initially £5 for 15 meetings) is a config value, not part of this decision; change it freely.
