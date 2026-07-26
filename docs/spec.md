---
title: ActionPoints MVP — transcript to Linear tasks, payable
labels: [ready-for-agent]
date: 2026-07-26
---

# ActionPoints MVP

Vocabulary per [CONTEXT.md](../CONTEXT.md); binding decisions per [docs/adr/](adr/); launch parameters per [product-brief.md](product-brief.md).

## Problem Statement

Meetings end with commitments buried in a transcript nobody rereads. Someone has to replay the conversation in their head, pick out who agreed to do what, and retype it all into Linear — so it either eats somebody's afternoon or (more often) doesn't happen, and the actions are lost. Meanwhile the transcript already exists: Zoom, Teams, and Meet export one automatically. The gap is purely between "text record of the meeting" and "tasks in the tool where work actually happens."

## Solution

ActionPoints takes a meeting Transcript (pasted, or an uploaded `.txt`/`.vtt`/`.srt`), runs one Extraction to produce Action Points (title, description, assignee guess, optional due date), and shows them on a Review screen where the user rejects the noise and edits the keepers. One click Pushes the accepted Action Points into their Linear workspace as real issues. Anyone can try the paste → Review flow on the landing page without an account; signing up (which grants one Free Meeting) is required only to Push. Further use is paid via a single £5 Credit Pack (15 meetings), purchased through Stripe Checkout.

## User Stories

### Trying it (anonymous visitor)

1. As a visitor, I want to paste a transcript on the landing page and see Action Points extracted without creating an account, so that I can judge the product before giving up my email.
2. As a visitor, I want the landing-page demo to be the real Review screen (minus the Push button), so that what I'm evaluating is what I'd be buying.
3. As a visitor, I want a sample transcript I can load with one click, so that I can see the product work even when I don't have a meeting transcript to hand.
4. As a visitor, I want to be told clearly that Pushing requires an account, so that the paywall boundary never surprises me mid-flow.
5. As a visitor who signs up after previewing, I want my previewed Extraction to still be there after registration, so that I don't have to re-run it to Push.

### Getting a Transcript in

6. As a user, I want to paste raw transcript text into a textbox, so that I can use output from any meeting tool without worrying about file formats.
7. As a user, I want to upload a `.txt`, `.vtt`, or `.srt` file, so that I can use the export Zoom/Teams/Meet already gave me without opening it.
8. As a user, I want timestamps and cue metadata stripped from `.vtt`/`.srt` files automatically, so that formatting junk doesn't pollute my Action Points.
9. As a user, I want speaker labels (when the transcript has them) preserved into the Extraction, so that the assignee guesses are grounded in who actually spoke.
10. As a user, I want to be rejected clearly and *before* any Credit is spent if my transcript exceeds the size cap (~25k words), so that I'm never charged for an input the product can't handle.
11. As a user, I want an obviously-not-a-transcript input (empty, or trivially short) rejected with a helpful message, so that I don't waste a Credit on garbage.

### Extraction

12. As a user, I want each Action Point to carry a title, a description with enough context to act on, an assignee guess, and a due date when one was said aloud, so that the pushed issue is genuinely useful and not just a headline.
13. As a user, I want vague conversational noise ("we should probably look into that sometime") to be extractable-but-rejectable rather than silently included or excluded, so that I stay in control of the boundary.
14. As a user, I want Extraction to show progress and complete within a reasonable wait, so that I don't assume the product hung.
15. As a user, I want a failed Extraction to tell me it failed, let me retry, and consume no Credit, so that failures cost me nothing (per the Credit rule).

### Review

16. As a user, I want every Action Point presented accepted-by-default with a way to reject each one, so that curation is one quick pass of unticking noise.
17. As a user, I want to edit an Action Point's title and description inline, so that I can fix the model's phrasing without a round trip.
18. As a user, I want to change or clear the assignee guess and due date, so that wrong guesses never reach my workspace.
19. As a user, I want nothing pushed to any Task Sink without passing my Review, so that my Linear workspace is never spammed (ADR-0005).
20. As a user, I want a count of accepted Action Points on the Push button, so that I know exactly what's about to be created.

### Accounts

21. As a visitor, I want to register with just my email, so that signup takes seconds.
22. As a user, I want to log in via a magic link rather than managing a password, so that access stays low-friction.
23. As a new user, I want one Free Meeting credited automatically, so that my first real Extraction-and-Push costs nothing.

### Connecting Linear

24. As a user, I want to paste my Linear personal API key in settings, so that I can connect without an OAuth dance.
25. As a user, I want my key validated immediately on save (with the failure reason shown), so that I don't discover a bad key mid-Push.
26. As a user, I want to choose which Linear team new issues land in, so that pushed Action Points arrive where my team actually works.
27. As a user, I want my API key stored encrypted and never rendered back in full, so that connecting doesn't create a new leak risk.
28. As a user, I want to replace or disconnect my key at any time, so that I stay in control of the access I've granted.

### Push

29. As a user, I want one click to create all accepted Action Points as Linear issues, so that the last mile is effortless.
30. As a user, I want assignee guesses matched to Linear users where possible and left unassigned otherwise, so that a bad guess never mis-assigns a colleague.
31. As a user, I want confirmation with links to the created issues, so that I can verify the result in one click.
32. As a user, I want a mid-Push failure to report exactly which Action Points were created and which weren't, and let me retry only the failures, so that a partial Push can't create duplicates.
33. As a user, I want a Push (and any retry of it) to consume no additional Credit — the Credit belongs to the successful Extraction — so that billing matches the stated rule.

### Credits & payment

34. As a user, I want my Credit balance always visible while signed in, so that I'm never surprised by running out.
35. As a user with zero Credits, I want the Extraction attempt to route me to buying a Pack rather than failing coldly, so that running out is a purchase moment, not a dead end.
36. As a user, I want to buy the £5/15-meeting Pack through Stripe Checkout without entering card details into ActionPoints itself, so that I never have to trust a day-old product with my card.
37. As a user, I want my balance to increase by 15 promptly after Checkout completes, so that I can get straight back to work.
38. As a user, I want a Checkout I abandon or that fails to change nothing, so that money and Credits never desynchronise.
39. As a user, I want a Credit consumed only on successful Extraction, never on failure, with re-runs of the same Transcript costing a new Credit, so that the rules are simple and predictable.
40. As the operator, I want every Credit grant and consumption recorded in a transactions ledger, so that any balance dispute is resolvable from the record.

### Trust & operations

41. As a visitor, I want the anonymous demo rate-limited, so that abuse can't burn the operator's API budget (and so the free preview survives launch day).
42. As a user, I want my Transcript handled only to produce my Action Points — not shared, with a plain-English one-liner saying so — so that I'm comfortable pasting internal meetings into a brand-new product.
43. As the operator, I want the product live on a public URL with payments running end-to-end in Stripe test mode, so that flipping to live keys (if verification lands) is a config change, not a build task.

## Implementation Decisions

- **Stack:** Elixir/Phoenix with LiveView for every screen, Postgres (ADR-0001). Single Phoenix app; no API-first split. All development is local — Docker Compose provides Postgres; no remote instances until the final deploy to Fly.io (ADR-0006).
- **Domain contexts:** roughly four — accounts/auth (generated by `phx.gen.auth`, magic-link login), the meetings pipeline (Transcript → Extraction → Action Points → Review state), billing (Credit ledger + Stripe), and sinks (Task Sink adapters + stored connection credentials).
- **Three ports to the outside world**, each an Elixir behaviour with a real adapter and a test fake:
  - **Extractor** — takes normalised transcript text, returns structured Action Points or a typed failure. Real adapter: Claude API, Sonnet 5, structured outputs, so the response is schema-validated rather than parsed from prose.
  - **TaskSink** (ADR-0002) — `validate_credentials`, list teams/users, `push_tasks`. Linear (GraphQL, personal API key) is the only launch implementation; the behaviour is the seam future Trello/GitHub adapters implement.
  - **PaymentProvider** — create a Checkout session; verify and interpret webhook events. Real adapter: Stripe, one Product, `checkout.session.completed` only.
- **Transcript normalisation** happens before the Extractor: `.vtt`/`.srt` parsed to plain text, cue/timestamp junk dropped, speaker labels kept as `Name:` prefixes. The word-count cap is enforced here, pre-Credit.
- **Extraction runs async** (background job with LiveView progress state), not in the request cycle — LLM latency on a big transcript is tens of seconds.
- **Review state is persisted server-side** (an Extraction and its Action Points are rows, with accepted/rejected/edited state), which is what lets an anonymous preview survive signup and lets a Push retry know what was already created.
- **Anonymous preview** is the same Review LiveView keyed to the visitor's session, with Push gated behind auth; extraction from the landing page is rate-limited per IP/session and consumes no Credit (there's no account to charge).
- **Credit ledger** (ADR-0003): an append-only transactions table (grants: signup seed, pack purchase; consumptions: successful Extraction) with the balance derived or cached; consumption is atomic with marking the Extraction successful, so a crash can't charge without delivering.
- **Push idempotency:** each Action Point records its created-issue reference on success; retry pushes only unreferenced ones.
- **Stripe webhook** is the only writer of purchase grants (redirect-back is untrusted), verified by signature; test mode throughout, live key as config.
- **Linear API keys** encrypted at rest (e.g. Cloak-style application-layer encryption), displayed masked.

## Testing Decisions

- **One seam philosophy:** tests drive from the top — `ConnTest`/`LiveViewTest` walking real router → LiveViews → contexts → Postgres — with only the three external ports (Extractor, TaskSink, PaymentProvider) replaced by fakes. No mocking between internal modules; internal behaviour is asserted through what the UI and DB show.
- **Good tests here assert external behaviour:** what the user sees on the Review screen, what rows the ledger holds, what the TaskSink fake was asked to create — never which internal function was called.
- **The flows that must have top-level tests:** anonymous preview → signup → Push carry-over; happy path paste → Review → Push with credit decrement; failed Extraction charges nothing; zero-credit user is routed to purchase; webhook grants exactly 15 credits exactly once (replayed webhook is a no-op); partial Push retry creates no duplicates; oversize transcript rejected before charge.
- **Pure functions tested directly where the top-level would be wasteful:** the `.vtt`/`.srt` normaliser and the word-count cap get plain unit tests on samples of real exports.
- **Prior art:** greenfield — the convention *is* the prior art. `phx.gen.auth`'s generated tests set the house style; pipeline tests follow it.

## Out of Scope

- Audio upload and any speech-to-text (first post-launch addition, 2 Credits/meeting — ADR-0004)
- Meeting bots and caption-scraping browser extensions (roadmap only — ADR-0004)
- Trello, GitHub Issues, or any second Task Sink; Slack permanently rejected (ADR-0002)
- Subscriptions (revisit with usage data — ADR-0003)
- OAuth for Linear (API-key paste only at launch — ADR-0002)
- Teams/multi-user accounts, sharing, roles — accounts are individual
- Custom domain, transactional email beyond magic links, analytics dashboards, admin UI
- Editing/re-running an Extraction in place (re-run = new Extraction, new Credit)

## Further Notes

- Build window is 12 hours (ends midnight 2026-07-26); the build order in [product-brief.md](product-brief.md) is the schedule. If time runs short, the payment stories (34–40) degrade first — the free-credit product must still work end-to-end.
- Stripe live-mode verification is in progress externally; nothing in this spec depends on it landing tonight.
- The Review screen is the product's face and its landing-page demo — polish spent anywhere else first is misallocated.
