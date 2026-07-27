# Unit economics: what one Extraction costs, and the margin on a £5 / 15-Credit Pack

Research for [issue #42](https://github.com/andrewnclark/action-points/issues/42). All
external rates verified against live primary sources on **2026-07-27**; all repo facts
read from the code on the same date.

## TL;DR

| Figure | Value |
|---|---|
| Cost per Extraction (typical ~5,000-word Transcript) | **~$0.06 ≈ 4.4p** (standard pricing; 2.9p on intro pricing until 2026-08-31) |
| Cost per Extraction (worst-case ~25,000-word Transcript) | **~$0.22 ≈ 16.6p** |
| Gross margin on a £5 / 15-Credit Pack, all 15 Credits consumed | **~£4.07 (≈81%)** typical; **~£2.24 (≈45%)** if every Extraction is worst-case |
| Monthly fixed floor (Fly.io) | **~$4.2/mo ≈ £3.20/mo** ceiling (less in practice — the app machine auto-stops) |
| Pack sales to clear £1,000/month net | **~247 Packs/month** (~£1,235 gross) at typical usage; ~448 if all worst-case |

## 1. What an Extraction calls (from the code)

- `lib/action_points/meetings/extractor/claude.ex` — one `POST https://api.anthropic.com/v1/messages`
  per Extraction, model **`claude-sonnet-5`**, structured outputs (`output_config.format`
  json_schema), `max_tokens: 16_000`, no `thinking` config → **adaptive thinking runs by
  default on Sonnet 5 and its tokens bill as output tokens**.
- Fixed prompt overhead per request: system prompt (146 words ≈ 250 tokens) + output
  schema (2.6 KB ≈ 650 tokens) ≈ **~900 input tokens** on top of the transcript.
  Prompt caching is not used (single-shot request; nothing to reuse).
- Each Extraction debits exactly 1 Credit (`lib/action_points/billing.ex`, `amount: -1`).
  Nothing else bills per-Extraction: Linear's API is free, the prod mailer is a log-only
  stopgap (no Resend key yet), and errors short-circuit without a retry loop.

### Token estimates (Sonnet 5 tokenizer ≈ 1.7 tokens/word on English transcripts)

| Scenario | Input | Output (JSON + thinking) |
|---|---|---|
| Typical, ~5,000 words | ~8,500 + 900 ≈ **9,400** | ~700 JSON (≈10 Action Points) + ~1,300 thinking ≈ **2,000** |
| Worst case, ~25,000 words | ~42,500 + 900 ≈ **43,500** | ~2,500 JSON + ~3,500 thinking ≈ **6,000** (hard cap 16,000) |

Sonnet 5's tokenizer produces ~30% more tokens for the same text than Sonnet 4.6, which
is folded into the 1.7 tokens/word factor above.

## 2. Provider rates (verified live, 2026-07-27)

| Source | Rate |
|---|---|
| Anthropic — Claude Sonnet 5 ([pricing](https://platform.claude.com/docs/en/about-claude/pricing.md)) | **Intro through 2026-08-31: $2 / $10 per MTok (in/out). Standard from 2026-09-01: $3 / $15.** Thinking tokens bill as output ([docs](https://platform.claude.com/docs/en/build-with-claude/extended-thinking.md)). |
| Fly.io ([pricing](https://fly.io/docs/about/pricing/)) | shared-cpu-1x 256MB ≈ **$2.02/mo**; stopped-machine rootfs $0.15/GB/mo; volumes $0.15/GB/mo; shared IPv4 free; no monthly minimum (pay-as-you-go). Unmanaged single-node dev Postgres ≈ $2/mo + volume. (Managed Postgres Basic would be $38/mo — not what fly.toml implies.) |
| Stripe UK ([pricing](https://stripe.com/gb/pricing)) | Standard UK cards **1.5% + 20p**; EEA 2.5% + 20p; international 3.25% + 20p (+2% if FX). No monthly fee. |
| FX | £1 ≈ $1.33 (approximate; 1-sig-fig confidence) |

All margin figures below use **standard** Anthropic pricing ($3/$15) — the durable
planning number. Intro-pricing figures are shown in parentheses where they matter.

## 3. Cost per Extraction

| Scenario | Input cost | Output cost | Total (USD) | Total (GBP) |
|---|---|---|---|---|
| Typical | 9,400 × $3/M = $0.028 | 2,000 × $15/M = $0.030 | **$0.058** ($0.039 intro) | **≈ 4.4p** (2.9p intro) |
| Worst case | 43,500 × $3/M = $0.131 | 6,000 × $15/M = $0.090 | **$0.221** ($0.147 intro) | **≈ 16.6p** (11.1p intro) |

## 4. Margin on a £5 / 15-Credit Pack (all 15 Credits consumed)

Pack from `config/config.exs`: `credits: 15, price_pence: 500, currency: "gbp"`.

| Line | Typical | All worst-case |
|---|---|---|
| Revenue | £5.00 | £5.00 |
| Stripe fee (1.5% + 20p, standard UK card) | −£0.275 | −£0.275 |
| LLM cost, 15 Extractions | −£0.66 (−£0.44 intro) | −£2.49 (−£1.66 intro) |
| **Gross margin** | **£4.07 ≈ 81%** (£4.29 intro) | **£2.24 ≈ 45%** (£3.07 intro) |

Sensitivities: an EEA card cuts margin by ~5p, an international card by ~9p. The free
signup-grant Credit costs ~4.4p per signup at typical usage — negligible.

## 5. Monthly fixed floor

From `fly.toml` (one `shared-cpu-1x` 256MB app machine, `auto_stop_machines`,
`min_machines_running = 0`, region lhr) plus the attached unmanaged Postgres:

| Item | Ceiling |
|---|---|
| App machine (if running 24/7 — actual is less, it auto-stops) | $2.02 |
| Postgres machine (runs 24/7) + 1GB volume | $2.02 + $0.15 |
| IPv4 (shared) / bandwidth at MVP volume | ~$0 |
| **Total** | **≈ $4.2/mo ≈ £3.20/mo** |

No other fixed costs: Stripe, Anthropic, and Linear have no monthly fee; the mailer is
log-only. (If Resend is added later, its free tier covers MVP volume.)

## 6. Packs/month to clear £1,000 net

Net per Pack ≈ £4.07 (typical, standard pricing). Break-even on fixed costs is ~1 Pack.

- **(£1,000 + £3.20) / £4.07 ≈ 247 Packs/month** (~£1,235/month gross).
- On intro pricing: ≈ 234 Packs/month.
- If every Extraction were worst-case: ≈ 448 Packs/month.

## Assumptions & caveats

- Token counts are estimates (1.7 tokens/word heuristic), not `count_tokens` measurements;
  transcripts with dense speaker labels/timestamps run higher. The worst-case row is the
  hedge — real usage lands between the columns.
- Thinking-token spend is the least certain input (adaptive thinking decides per request);
  it is bounded by `max_tokens: 16_000`, which caps even a pathological Extraction at
  ~$0.37 (~28p) on standard pricing.
- "All 15 credits consumed" is the conservative margin frame; unconsumed Credits are pure
  margin until used (they are a liability, not a cost).
- FX at £1 ≈ $1.33; a 5% GBP move shifts the typical Pack margin by ~±3p.
- Intro Anthropic pricing expires 2026-08-31 — five weeks from now — so standard pricing
  is the right basis for any decision that outlives August.
