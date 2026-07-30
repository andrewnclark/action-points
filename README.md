# ActionPoints

Paste a meeting transcript, get action points you can actually trust, push them to Linear.

An LLM reads the transcript and proposes action points. A human reviews and curates. Accepted items
are pushed to a task tracker. Usage is metered against a credit balance topped up through Stripe.

**Built solo in a twelve-hour sprint.** The interesting question about a build like that isn't
whether it works — it's what survives the speed. What survived here was the test suite, the
architectural seams and the decision log. This README points at those deliberately, because they're
the parts worth reviewing.

---

## The design problem worth talking about

An LLM asked to pull action points out of a transcript will, sometimes, produce a confident quote
that nobody said. In a product whose whole value is trust, that isn't a rough edge — it's fatal.
Prompting the model to behave isn't a solution, it's a hope.

So the guarantee is structural instead. `ActionPoints.Meetings.GroundingQuote` keeps a proposed quote
**only if it appears verbatim in the whitespace-normalised source transcript**. Anything else is
discarded before it can reach the interface.

Note carefully what this does and doesn't promise:

> No quote shown to a user is invented. **Not** that the model quoted well.

The model can still pick a boring or unhelpful quote. It cannot fabricate one. That's a guarantee
tests can enforce, which a prompt cannot.

## Architecture

Conventional Phoenix 1.8 — `lib/action_points` for the core, `lib/action_points_web` for the
interface. Postgres via Ecto, LiveView 1.1 for the UI, Bandit, deployed to Fly.io.

Every external dependency sits behind an explicit behaviour, with a real implementation and a fake
used in tests:

| Behaviour | Real implementation | Purpose |
| --- | --- | --- |
| `Meetings.Extractor` | `Extractor.Claude` | Action-point extraction |
| `Sinks.TaskSink` | `Sinks.Linear` | Pushing accepted items out |
| `Billing.PaymentProvider` | `Billing.Stripe` | Credit purchase |

That's what makes the suite fast and deterministic: no test touches the network, and swapping a
provider is a config change rather than a refactor.

### Extraction runs outside the request

Extraction takes tens of seconds, so it moves onto a supervised `Task.Supervisor` and reports
progress to subscribed LiveViews over `Phoenix.PubSub`. The browser follows a job it isn't waiting on.

### Details that came from hitting the wall

- **Structured output** is validated against a hand-written JSON schema. The Anthropic API rejects
  `maxItems`, so the cap moved into the prompt and is re-checked in `verify/2`. A comment records
  this so the next person doesn't re-derive it.
- **Retry is concurrency-safe.** Reset happens through a single conditional
  `UPDATE ... WHERE status == :failed`, so two rapid retries can never start two concurrent runs.
- **Stored third-party credentials are encrypted at the application layer** — AES-256-GCM with a
  versioned ciphertext layout (`ActionPoints.Vault`), so the key can rotate without a migration.
- **Stripe webhooks verify signatures against the raw body**, captured by a custom body reader
  (`ActionPointsWeb.RawBody`), because a re-encoded body will not verify.
- **Rate limiting** is a fixed-window GenServer holding counters in process state. Its `@moduledoc`
  is honest about the trade-off: per-node, and gone on restart. Fine for a single-node MVP, and it
  would need replacing before it wasn't.

## Tests

539 tests across 45 files — roughly a 1:1 test-to-code ratio.

The ones worth reading:

- `extraction_flow_test.exs` — drives the whole LiveView flow against a stubbed extractor, with an
  `eventually/1` helper for the async task.
- `rate_limiter_test.exs` — starts an isolated named GenServer per test, covering window expiry and
  key independence.
- `grounding_quote_test.exs` — the invariant above.

```sh
mix deps.get
mix ecto.setup
mix test
```

### The classification evaluation suite

One thing the suite above cannot reach: whether the model tags *"have it ready for review by
Wednesday"* as a weekday reference rather than as vague, and whether it attaches that to the right
action point. That's model output, not application logic — and the extraction prompt is exactly the
thing a refactor can silently regress.

`test/eval` holds thirteen fixture transcripts with known expected classifications, run against the
real API. It is **excluded from the default run by the `:eval` tag**, so `mix test` — and anything
automated that calls it — never spends money or fails on an off run from the model. Run it
deliberately, and **always when the extraction prompt changes**:

```sh
export ANTHROPIC_API_KEY=...
mix test --include eval test/eval
```

Each fixture is sampled three times and has to be right in a majority of them. That's not
ceremony: at one call per fixture the suite failed somewhere in a clean run about half the time,
which is how a tripwire trains people to ignore it. A real regression makes a fixture wrong in
nearly every sample and still fails.

## Decision log

`docs/adr/` holds eight numbered architecture decision records written during the build, alongside a
product brief and spec in `docs/`. If you want to know *why* something is as it is, start there — the
ADRs record the alternatives that were rejected, which the code cannot.

ADR-0001 is *"Elixir/Phoenix on Fly over Go"*, which sets up most of what follows.

## Running it

```sh
mix setup
mix phx.server
```

Then visit [`localhost:4000`](http://localhost:4000).

Configuration is entirely environment-driven — see `config/runtime.exs`. Nothing beyond a database is
needed to boot in development; extraction and billing degrade to explicit errors without their keys
rather than failing obscurely.

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Postgres connection |
| `SECRET_KEY_BASE` | Phoenix signing |
| `ANTHROPIC_API_KEY` | Extraction |
| `SINK_ENCRYPTION_KEY` | Credential encryption at rest |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | Billing |

## Honest limitations

Worth stating plainly, given this is a twelve-hour build being shown as a work sample:

- Single-node by design. The rate limiter and its in-process counters assume it.
- Linear is the only task sink implemented, though the behaviour exists to add others.
- No custom telemetry. LiveDashboard gives runtime visibility, but the app emits no domain events.
- Typespec coverage is partial, and there's no Dialyzer or Credo in the toolchain.
