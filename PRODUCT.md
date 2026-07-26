# Product

<!-- impeccable:product-schema 1 -->

> **This file is a digest, not an authority.** It exists because the design tooling reads a
> single product record. Where it disagrees with anything else in this repo, the other source
> wins: [CONTEXT.md](CONTEXT.md) owns the vocabulary, [docs/adr/](docs/adr/) owns the
> decisions and their reasoning, and the GitHub issues own the current scope. Fix drift by
> editing this file, never the sources.

## Platform

web

## Users

Software team leads, product managers, and engineers who run recurring meetings and already
live in Linear. The situation is the ten minutes after a call ends: the meeting produced
promises, the meeting tool produced a transcript, and the next call starts soon. Their job
is to get the commitments out of that transcript and into the tracker before they evaporate,
without re-reading the transcript or typing the issues by hand.

A second audience meets the product first as an anonymous visitor on the landing page, who
runs a Demo without an account and only signs up at the moment of Push.

## Product Purpose

ActionPoints turns a meeting transcript into curated tasks in the user's project-management
tool. The user supplies a Transcript, an Extraction proposes Action Points, the user curates
them in Review — accepting, rejecting, editing — and Pushes the keepers into a Task Sink,
where they become real tasks. Success is the meeting's commitments landing in Linear,
correctly worded and correctly assigned, in less time than it would take to type them.

## Positioning

The curation step is the product. Nothing reaches a Task Sink without passing Review: every
Action Point is a proposal the user accepts, edits, or rejects, one at a time. Competing
"AI meeting notes" products summarise, or auto-create tasks and leave the user to clean up
after them. ActionPoints is transcript-in **for now** — it does not join calls, record audio,
or sit in the meeting — so it works with whatever meeting tool the team already runs.
ADR-0004 defers capture rather than rejecting it: audio upload is the first thing planned
after launch, and capture is named there as the likely moat. Surfaces should not claim
transcript-only as a permanent position.

## Operating Context

- The input is text the user already has: an export pasted in, or a `.txt`, `.vtt`, or `.srt`
  file dropped in. Transcripts run up to ~25,000 words (about two hours of speech).
- An Extraction takes seconds to about a minute, so the waiting state is a real, frequently
  seen screen — not an edge case.
- Review is the screen users spend their time on: typically a handful to a dozen Action
  Points from one meeting, each with a title, description, assignee guess, and a due date
  only when one was said aloud.
- Push writes to Linear via a personal API key the user pastes into Sink Settings. A Push
  can fail partway; pushing again creates only the missing tasks, never duplicates.
- Desktop is the primary scene — a work machine, in office daylight or a home office, with
  Linear open in another tab. Mobile must not break but is not where the work happens.

## Capabilities and Constraints

- **Vocabulary is fixed and load-bearing.** [CONTEXT.md](CONTEXT.md) is the authority for
  Transcript, Extraction, Action Point, Review, Push, Task Sink, Credit, Pack, Free Meeting.
  The UI uses these words verbatim; a term that feels wrong is challenged at the glossary,
  never silently renamed in the interface.
- **Commerce is Credits only.** One Credit is consumed by one successful Extraction; failed
  Extractions consume nothing; a re-run of the same Transcript costs a new Credit. Every new
  account gets one Free Meeting. There are no subscriptions, seats, or tiers (ADR-0003).
  A Pack is £5 for 15 Credits *today* — ADR-0003 treats the price and size as config, free to
  change, so no surface should be built in a way that makes changing them expensive.
- **Anonymous Demo.** The landing page runs a real Extraction and Review keyed to the
  visitor's session, rate-limited rather than charged. Signup is required only at Push, and
  the Demo's Review carries over through signup.
- **Task Sinks are pluggable** behind one behaviour. Linear is the only sink today.
- **Stack:** Phoenix LiveView, Tailwind v4 with CSS-file config, heroicons, a vendored
  daisyUI kept as theming plumbing. No new runtime dependencies; no component library.
  Fonts must be free-licence and self-hosted — no CDN loading.
- **States that must be designed, not left over:** Extraction in progress, Extraction
  failed (and no Credit charged), empty Review, Push success, Push failure, Credits gate.
- **Dark is the canonical theme.** A light-theme direction was mocked up and rejected in the
  July 2026 design round; light ships as a derived theme, not the design target.

## Brand Commitments

- The name **ActionPoints** stays. The wordmark is text-only; there is no logo project.
- Voice is a precise, confident tool voice: short declarative sentences, benefit-led but
  hype-free, product vocabulary used verbatim. Empty states and the post-Push success
  moment may carry a single degree of warmth; nothing else does.
- Both a light and a dark theme ship, expressed as semantic tokens, with a system/light/dark
  toggle that persists. No third theme.

## Evidence on Hand

- A real sample Transcript ships in the app (a product-team standup) and its Action Points
  are the demonstration data used across design work — believable names, descriptions,
  assignee guesses, and dates. It is fictional and labelled as a sample.
- Working screens exist for landing/Demo, Review, Buy Pack, Sink Settings, and auth, with a
  LiveView test suite covering their behaviour.
- **No customers, testimonials, logos, benchmarks, or usage numbers exist.** The product has
  testers, not references. None of this may be fabricated in any surface.
- Pricing (£5 / 15 Credits, one free Credit) is real and may be stated.

## Product Principles

1. **Nothing is created until the user says so.** Review is a gate, not a formality, and the
   interface should make that obvious at a glance.
2. **The proposal must justify itself.** Each Action Point carries the context that lets the
   user accept it without re-reading the transcript.
3. **Failure is a designed state.** Extractions and Pushes fail; those moments must build
   trust — say what happened, say what it cost (usually nothing), offer the next move.
4. **The product teaches its own vocabulary** by using it consistently everywhere.
5. **Speed of curation beats richness of interface.** The screen exists to be got through.

## Accessibility & Inclusion

Semantic HTML, visible focus states on every interactive control, and contrast-sane colour
choices in both themes are a floor, not a project. A formal WCAG audit is out of scope for
now and must not be claimed.
