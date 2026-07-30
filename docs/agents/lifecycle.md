# Ticket agent lifecycle

You are implementing issue #N in complete isolation: your own worktree, your own compose project, your own Postgres. Nothing you do can touch the developer's live stack (their Postgres holds host port 5433, their Phoenix server holds port 4000) or any sibling agent. `N` is the issue number throughout.

## Setup

```bash
git -C <repo> fetch origin main
git -C <repo> worktree add ../wt-N -b N-<slug> origin/main
cd ../wt-N
export COMPOSE_PROJECT_NAME=ap-N
export DB_PORT=$((5500+N))
docker compose up -d db
mix deps.get
```

Wait until `docker inspect -f '{{.State.Health.Status}}' ap-N-db-1` reports `healthy`.

If docker answers `permission denied` on `/var/run/docker.sock` even outside the sandbox, your shell's group list is stale (the session predates the user's docker group membership) — wrap the command in `sg docker -c '…'`.

No `.env` is needed and no asset build is needed: the test suite swaps every external port (extractor, task sink, payments) for fakes in `test/support/`, and Phoenix tests render without built assets — do not waste time on `mix assets.build` or npm.

Completion: healthy Postgres on your own host port, `deps/` fetched, both env vars exported in the shell that will run tests.

## Implement

Follow `/implement` for issue #N: `/tdd` at pre-agreed seams, CONTEXT.md vocabulary, ADRs in `docs/adr/` respected.

Run any review pass through **synchronous (foreground) sub-agents** — the fresh context window is the point of a sub-agent reviewer, so keep it, but the spawn must block until the report returns. Never spawn reviewers in the background and stop to wait: their completion signals route to the orchestrator, not to you, and a turn ended "waiting" is a stall.

Tests run on the host against your own forwarded port — `config/test.exs` reads `DB_PORT` (default 5433), and the `mix test` alias creates and migrates `action_points_test` in your container on first run; there is no shared database to trample.

```bash
DB_PORT=$((5500+N)) mix test test/action_points/...   # single files while working
DB_PORT=$((5500+N)) mix test                          # full suite once at the end
```

(The Setup exports already cover this if you stay in one shell — restate them in any new one.)

If you generate a migration, make its version collision-proof against sibling agents: after `mix ecto.gen.migration`, rename the file so the timestamp's minute-and-second field is your issue number zero-padded (e.g. issue #33 → `...T0033_...` becomes `20260731000033_name.exs`-style: keep the date, set the last four digits to 0033). Two sibling agents defaulting to the same generated minute produced duplicate versions once, and Ecto silently skips the second file — fresh databases then miss a table.

Never run mix tasks in the developer's main checkout — the `_build` lock wedges their running dev server. Your worktree has its own `_build`; everything happens there, and the first compile is cold.

Completion: full suite green.

## Deliver

One task, one commit, no attribution. The PR body is the durable record — a later reviewer or reconciler reads it when your context is gone, so `Closes #N` alone is not enough. After that line, cover: what was built against each part of the spec; every judgement call or deviation and its reasoning; any pattern you established that a sibling ticket might also touch; anything deliberately deferred and why. Then push the branch and open the PR:

```bash
git push -u origin N-<slug>
gh pr create --base main --title "<issue title>" --body "<Closes #N + the record above>"
```

## Teardown

On success, always (with `COMPOSE_PROJECT_NAME` still exported, from the worktree):

```bash
docker compose down -v
cd <repo> && git worktree remove ../wt-N
```

On failure (suite not green, blocked mid-issue): **park** — leave the worktree and stack running, push nothing, and report exactly what blocked you.

Completion: either a PR exists and the environment is gone, or a parked report exists and the environment is intact.
