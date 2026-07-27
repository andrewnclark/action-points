# Credits only — no subscriptions

Monetisation is one-off Credit Packs, not a subscription, even though "a couple of quid a month" was the original pitch. Reasons: meeting processing is lumpy, discrete usage, which packs fit and subscriptions punish; a stranger will hand £5 once to a brand-new product but won't grant it recurring card access; and credits skip the entire subscription state machine (cancellation, dunning, active-subscriber logic). Credits monetise curiosity; subscriptions monetise retention we can't yet demonstrate.

One Credit is consumed per successful Extraction only — failures are never charged. New accounts are seeded with one free Credit, because nobody pays before seeing their own transcript converted.

## Consequences

- The ledger is deliberately subscription-ready: credits are an integer plus a transactions table, so adding a monthly tier later requires no migration of the model.
- Revisit subscriptions only when usage data shows habitual (e.g. weekly) pack-burning — then the data also tells us the price.
- Pack pricing (initially £5 for 15 meetings) is a config value, not part of this decision; change it freely.

## When subscriptions do arrive, they feed credits — they don't replace them

Added 27 Jul 2026, from [the commercial-model ticket](https://github.com/andrewnclark/action-points/issues/45). What this ADR rejected was a subscription *replacing* credits. The shape to build instead, when the revisit trigger above fires:

- **Keep £5 / 15 Packs** for the stranger who wants one meeting sorted, and **add a monthly tier that grants credits** (e.g. £25/month for 100). One currency, two doors — the customer never learns a second unit, and consumption logic is untouched: an Extraction costs one Credit regardless of where it came from. A recurring grant is a scheduled row in the existing transactions table, which is what the subscription-readiness consequence above was for.
- **The real cost is not the Stripe wiring — it is one policy call: do granted credits roll over or expire?** Roll over and light months subsidise heavy ones while liability grows unbounded; expire and you have built the thing customers resent about credits. Decide that before writing code.
- **Seat-based pricing is not the alternative.** Seats price headcount; this product's value scales with meetings processed, which Credits already track exactly. Only one person per meeting logs in (paste → Review → Push, ADR-0005), so seats collapse to 1–3 per team. Seats only become coherent if capture lands (ADR-0004) and the product gains a per-attendee relationship.
- **£5 / 15 is unvalidated and probably low** — roughly 10× under the cheapest incumbent (£70–250/user/year), in a category with no free tier for this use case. Cheap signals "toy" to a team buyer. Raising the price is the cheapest untried lever; test it before assuming the model is what needs changing.
