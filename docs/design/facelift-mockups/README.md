# Facelift — divergent round (issue #14)

Design directions for the ActionPoints facelift ([#13](https://github.com/andrewnclark/action-points/issues/13)),
each mocked as a full **homepage** and a full **Review** screen. Three dark directions were
built for the divergent round; a fourth, light one was added afterwards on request and
rejected (see below).

**These are throwaway artifacts.** They are not application code, they are not wired to
anything, and only the winning direction survives — rebuilt as real design tokens in
issue #15. The losing directions are not maintained after the choice is made.

## Viewing them

Open `index.html` in a browser — it's the side-by-side chooser with rationales, palettes,
and links into every page. No server needed; every page is a self-contained HTML file
with its CSS inline and its fonts loaded from `fonts/`.

```
xdg-open docs/design/facelift-mockups/index.html
```

Each page carries a small pill in the bottom-left corner to hop between Home, Review, and
the chooser. That pill is scaffolding for this review round, not part of any design.

## The divergent round

Graphite is the chosen direction; the others are kept only as the record of the round.

| | Graphite ✓ | Ledger | Signal |
|---|---|---|---|
| **Rationale** | The cold instrument: neutral graphite surfaces, tight radii and one electric indigo — dense and quiet, so the Action Points are the only thing with colour on the screen. | The meeting record, typeset: warm ink surfaces, hairline rules and IBM Plex Mono labels — the app looks like the minutes it produces. | Confident where it counts: a true-black canvas, Space Grotesk headlines and one loud lime — generous radii and air, so the product reads as a finished commercial tool with an opinion. |
| **Surface** | Cold neutral `#0B0D10` | Warm ink brown `#14110E` | True black `#07080A` |
| **Accent** | Electric indigo `#6E7BFF` | Amber `#E0A24A` | Lime `#B7F04A` |
| **Type** | Inter (grotesque) | IBM Plex Sans + Plex Mono | Space Grotesk + Inter |
| **Density / radius** | Dense, 6px | Medium, 2px (sharp) | Airy, 14px (pills) |
| **Review layout** | Compact cards, sticky Push bar | Ruled entries with a numbered gutter | Roomy cards, floating Push bar |

Divergence is deliberate on the four axes the parent ticket named: surface temperature,
accent personality, type character, and density/radius language.

## What is held constant

- **The substantive copy is the same in every direction** — headline, lede, the three steps,
  the pricing facts, and every Action Point's words. The copy pass belongs to the per-screen
  tickets; holding the words still here makes this a comparison of look and feel. Small
  per-direction chrome does differ (Graphite shows a `⌘↵` hint, Ledger a word count); it
  carries no argument either way.
- **The data is identical**: the same six Action Points, extracted from the product-sync
  sample transcript already shipped in `HomeLive`. Believable names, descriptions,
  assignee guesses, and due dates — no lorem ipsum.
- **The same states are shown** on every Review screen so they can be compared: five
  accepted, one rejected (struck through, one tap from coming back), and one open in the
  editor.

## Fonts

Every family is SIL Open Font License, downloaded as latin-subset `.woff2` into
`fonts/` and referenced with local `@font-face` rules — no CDN, nothing to license, and
whichever direction wins can ship its files as-is with the app's static assets.

| File | Family | Licence |
|---|---|---|
| `Inter-var.woff2` | Inter (variable, 100–900) | SIL OFL 1.1 |
| `IBMPlexSans-var.woff2` | IBM Plex Sans (variable) | SIL OFL 1.1 |
| `IBMPlexMono-400.woff2`, `IBMPlexMono-500.woff2` | IBM Plex Mono | SIL OFL 1.1 |
| `SpaceGrotesk-var.woff2` | Space Grotesk (variable) | SIL OFL 1.1 |
| `LibreCaslonDisplay-400.woff2` | Libre Caslon Display (Bond) | SIL OFL 1.1 |
| `PublicSans-var.woff2` | Public Sans (variable, Bond) | SIL OFL 1.1 |
| `SplineSansMono-var.woff2` | Spline Sans Mono (variable, Bond) | SIL OFL 1.1 |

## The fourth direction: Bond (rejected)

After seeing the first three the product owner asked for a light-theme take, so a fourth
direction was run through the `/impeccable` flow: **Bond**, a utility patent drawing sheet —
warm bond stock `#F4F0E6`, india ink `#1B2432`, hairline rules terminating in circles,
reference numerals in the gutter, carmine reserved for what is under examination, a green seal
for what has been granted, and hatching for what is void. Libre Caslon Display heads, Public
Sans text, Spline Sans Mono numerals (all SIL OFL, in `fonts/`).

It was rejected on sight. It is kept here as the record of what was tried, not as a candidate.
The direction contract for it survives as an HTML comment at the top of each Bond page.

## Carried forward to the copy pass

One glossary question surfaced while writing these and is **not** settled here: the mockups
describe a Pack as both "15 meetings" (Graphite, Signal — matching what the app says today)
and "15 Credits" (Ledger, Bond — matching CONTEXT.md, which defines a Pack as a fixed number
of Credits and lists *meeting* under Transcript's _Avoid_). The app's current copy is the
odd one out against its own glossary. Settle it in the copy pass, at the glossary first.

## Decision

**Graphite**, chosen 26 July 2026. Dark-first stands — the light theme is derived from the
dark tokens rather than designed first. Issue #15 rebuilds Graphite as semantic design tokens
and pilots it on Review and the homepage.
