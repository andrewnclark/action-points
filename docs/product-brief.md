# ActionPoints — launch brief (hackathon, 2026-07-26)

Outcome of the planning session, 12:00 → 00:00 build window. Durable *why*-decisions live in [docs/adr/](adr/); vocabulary in [CONTEXT.md](../CONTEXT.md). This file is the operational snapshot — expect it to go stale after launch.

## Win condition

A live URL a stranger could pay on tonight. Payments are built against **Stripe test mode** all day; the account's live-payments verification was started in parallel and flipping to the live key is a ~10-minute step *if* it lands. Shipping with test-mode-only payments still counts as a win.

## The product in one line

Paste a meeting transcript → Claude extracts Action Points → user curates them on a Review screen → Push creates issues in Linear.

## Launch parameters

| Parameter | Value |
|---|---|
| Name / URL | ActionPoints, on `actionpoints.fly.dev` (or near variant); real domain only if it has a pulse tomorrow |
| Pack price | £5 for 15 meetings, single pack, one Stripe Checkout + one `checkout.session.completed` webhook |
| Free allowance | 1 Credit seeded per new account |
| Credit rule | 1 Credit = 1 successful Extraction; failures free; re-runs cost a new Credit |
| Transcript cap | ~25,000 words (≈2 hours of speech) |
| Accepted input | Paste, or upload `.txt` / `.vtt` / `.srt` |
| Extraction model | Claude API, Sonnet 5, structured outputs (~pennies per meeting) |
| Auth | `phx.gen.auth`; no signup needed for the landing-page Review demo, account required to Push |
| Linear auth | Pasted personal API key |

## Build order

All development is local — Docker Compose for Postgres, app via `mix phx.server`, nothing running remotely until the final step (ADR-0006).

1. Scaffold + auth + local walking skeleton (Phoenix + dockerised Postgres, `mix test` green)
2. Extraction pipeline + Review screen (the core, biggest chunk)
3. Linear push behind the `TaskSink` behaviour
4. Credits ledger + Stripe test-mode checkout + webhook (webhook exercised locally via Stripe CLI)
5. Landing page copy (Review demo embedded, no signup)
6. Polish / buffer
7. Deploy to Fly — the one and only deploy, once we're happy locally; flip Stripe live key if verification arrived

## Deferred (with revisit triggers)

- **Audio upload** — first addition after launch; 2 Credits per audio meeting; prefer a diarizing STT provider (see ADR-0004)
- **Meeting bots / caption-scraping extension** — roadmap, only if people pay (ADR-0004)
- **Trello, GitHub Issues** — new `TaskSink` implementations when demanded (ADR-0002); Slack rejected outright
- **Subscriptions** — only when usage data shows habitual use (ADR-0003)
- **OAuth for Linear** — when the audience outgrows API-key pasting (ADR-0002)
