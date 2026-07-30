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

No `.env` is needed and no asset build is needed: the test suite swaps every external port (extractor, task sink, payments) for fakes in `test/support/`, and Phoenix tests render without built assets — do not waste time on `mix assets.build` or npm.

Completion: healthy Postgres on your own host port, `deps/` fetched, both env vars exported in the shell that will run tests.

## Implement

Follow `/implement` for issue #N: `/tdd` at pre-agreed seams, CONTEXT.md vocabulary, ADRs in `docs/adr/` respected.

Tests run on the host against your own forwarded port — `config/test.exs` reads `DB_PORT` (default 5433), and the `mix test` alias creates and migrates `action_points_test` in your container on first run; there is no shared database to trample.

```bash
DB_PORT=$((5500+N)) mix test test/action_points/...   # single files while working
DB_PORT=$((5500+N)) mix test                          # full suite once at the end
```

(The Setup exports already cover this if you stay in one shell — restate them in any new one.)

Never run mix tasks in the developer's main checkout — the `_build` lock wedges their running dev server. Your worktree has its own `_build`; everything happens there, and the first compile is cold.

Completion: full suite green.

## Deliver

One task, one commit, no attribution. Push the branch and open the PR:

```bash
git push -u origin N-<slug>
gh pr create --base main --title "<issue title>" --body "Closes #N"
```

## Teardown

On success, always (with `COMPOSE_PROJECT_NAME` still exported, from the worktree):

```bash
docker compose down -v
cd <repo> && git worktree remove ../wt-N
```

On failure (suite not green, blocked mid-issue): **park** — leave the worktree and stack running, push nothing, and report exactly what blocked you.

Completion: either a PR exists and the environment is gone, or a parked report exists and the environment is intact.
