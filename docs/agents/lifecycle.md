# Ticket agent lifecycle — ActionPoints overlay

This file is an **overlay**, not a whole lifecycle. The phases, their completion criteria, and
the obligations that hold regardless of stack come from the `implement-parallel` skill:
`lifecycle-core.md` for the discipline, `lifecycle-elixir-phoenix.md` for the mix and compose
commands. Only what is genuinely particular to this repo lives here.

If something below contradicts the core discipline, the core wins and this file is wrong.

## What this repo holds

**Names and ports.** Compose project `ap-N`, worktree `../wt-N`, branch `N-<slug>`, database on
host port `5500+N`, health-checked as `ap-N-db-1`.

**The developer's own stack is live while you work.** Their Postgres holds host port `5433` and
their Phoenix server holds `4000`. Neither is yours, and the `5500+N` scheme exists to keep out
of their way.

**No `.env`, and no asset build.** The suite substitutes fakes in `test/support/` for every
external port — Extractor, Task Sink, payments — so no API keys are needed, and Phoenix tests
render without built assets. Do not spend time on `mix assets.build` or npm; nothing in the
suite needs them.

(For running the app by hand, `.claude/launch.json` sources `.env` — without it every Extraction
fails `missing_api_key`. That is for the developer, not for agents.)

**The test database bootstraps itself.** `config/test.exs` reads `DB_PORT` (default `5433`), and
the `mix test` alias creates and migrates `action_points_test` inside your own container on
first run. There is no shared database to trample.

**Migration versions are guarded, not coordinated.** Generate migrations normally with
`mix ecto.gen.migration`. Sibling agents occasionally produce the same timestamp;
`migration_versions_test.exs` fails the suite loudly when the branches meet, and whoever merges
second renumbers one file. Validation over convention-bending.

**Credo is calibrated, not stock.** `.credo.exs` sets `CyclomaticComplexity` to 11 and `Nesting`
to 3 — the codebase's current worst cases, so the check means "do not get worse". A finding means
your change introduced it: fix the change. If a threshold genuinely needs to move, argue for it
in the PR body.

## Domain obligations

Follow `/implement` for the issue: `/tdd` at pre-agreed seams, **CONTEXT.md vocabulary**, and the
ADRs in `docs/adr/` respected. CONTEXT.md is the authority on domain terms — a name that
contradicts it is a bug, and a term the code needs but CONTEXT.md lacks is worth raising rather
than inventing.

## Completion

`mix precommit` green — `compile --warning-as-errors`, `deps.unlock --unused`, `format`, `credo`,
`test` — not `mix test` alone.
