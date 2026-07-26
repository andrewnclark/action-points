# Elixir/Phoenix on Fly.io, not Go

Built during a 12-hour hackathon (2026-07-26) whose win condition was "a stranger can pay on a live URL by midnight". Go was seriously considered as a learning goal, but learning a language while shipping auth, payments, and a deploy carries a 2–3 hour tax plus slow debugging late at night. We chose the known stack: Elixir/Phoenix with LiveView for all UI, deployed to Fly.io (already set up from past projects), Postgres attached there.

## Consequences

- Go remains a worthwhile goal for a hackathon whose win condition is learning, not shipping.
- Tonight's code is intended as the seed of the real product, not a throwaway — another reason the familiar stack won.
