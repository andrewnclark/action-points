defmodule ActionPoints.Meetings.Extractor.TimingClassificationEvalTest do
  @moduledoc """
  A regression tripwire for the half of Timing the tests cannot reach: whether
  the model classifies the timing language it hears correctly, and attaches it
  to the right Action Point.

  Everything downstream of the classification is covered by fast deterministic
  tests — `Timing` is a pure function, and `ClaudeTest` drives the adapter
  against a stubbed API. What neither can reach is whether "have it ready for
  review by Wednesday" comes back as a `weekday` rather than as `vague`. That
  is model output, not prompt wording, and a prompt rewrite is precisely the
  change nothing else in the suite would catch regressing.

  Deliberately small: a tripwire, not a benchmark. Each fixture pins one kind
  of timing language, and the assertions are on the classification the model
  produced — never on the words of the prompt that produced it.

  Excluded from the default run by the `:eval` tag, because it costs real API
  calls and the model's output is not perfectly repeatable; a flaky failure in
  an automated run trains people to ignore failures, which would leave this
  worse than useless. Run it deliberately, and always when the extraction
  prompt changes:

      export ANTHROPIC_API_KEY=...
      mix test --include eval test/eval

  ## Why each fixture is sampled more than once

  The same Transcript does not always come back classified the same way. Left
  at one call per fixture this suite failed somewhere in a clean run about
  half the time — measured, not guessed — with correct code and an unchanged
  prompt. The classification is right the large majority of the time and
  occasionally collapses to something looser ("in a couple of days" read as
  the end of the week), so a single sample cannot tell a prompt regression
  from the model having an off run, and a tripwire that cannot tell those
  apart is the flaky one the tag exclusion exists to avoid.

  So each fixture is sampled `@samples` times and has to be right in most of
  them. A regression makes a fixture wrong nearly always, which still fails;
  one bad sample no longer does. The samples run concurrently, so the cost is
  API calls rather than wall-clock.
  """

  use ExUnit.Case, async: false

  alias ActionPoints.Meetings.Extractor.Claude

  @moduletag :eval

  # Each fixture is `@samples` concurrent round trips to the API, and
  # extraction is deliberately given a long receive timeout.
  @moduletag timeout: 300_000

  @samples 3
  @required_agreement div(@samples, 2) + 1

  # Each fixture: a Transcript, and the classification each Action Point in it
  # is expected to carry, keyed by a word that must appear in that Action
  # Point's title. Keeping the expectation keyed by topic rather than by
  # position is what lets the last fixture assert *attachment* — that the
  # timing landed on the Action Point the meeting attached it to, not merely
  # that the Extraction mentioned it somewhere.
  #
  # The fixtures are written as real meeting talk — several turns, the work
  # discussed before it is agreed — rather than as the one line that carries
  # the timing phrase. That is not decoration. A two-line Transcript is not
  # what the product is ever given, and the model classifies it visibly worse:
  # "by the 12th" alone came back as `vague` about a quarter of the time,
  # while the same words inside a meeting came back as the date every time. A
  # tripwire built on input the product never sees would fire on its own
  # unrepresentativeness, which is the one way to make it worse than nothing.
  @fixtures [
    %{
      name: "a bare weekday",
      transcript: """
      Sam: Where are we on the pricing page? Marketing keep asking.
      Priya: The copy's signed off. The layout still wants a pass before anyone sees it.
      Sam: Is that a big job?
      Priya: An afternoon, maybe. It's finding the afternoon that's hard.
      Sam: Can you have the pricing page ready for review by Wednesday?
      Priya: Wednesday works.
      """,
      expected: [{"pricing", %{kind: :weekday, weekday: :wednesday, modifier: nil}}]
    },
    %{
      name: "a weekday with a modifier",
      transcript: """
      Dan: The security audit came back. Nothing critical, but the findings need writing up
      for the board.
      Mia: I can do the write-up. Not this week though — I'm on the incident rota until Friday.
      Dan: Next Thursday, then? The board pack goes out the week after.
      Mia: Next Thursday is fine. I'll cover the two medium findings and what we're doing
      about them.
      """,
      expected: [{"audit", %{kind: :weekday, weekday: :thursday, modifier: :next}}]
    },
    %{
      name: "a relative day",
      transcript: """
      Ana: The staging database still has last month's dump on it. QA are testing against
      data that predates the schema change.
      Joe: That explains the failures they raised yesterday.
      Ana: It does. Can we refresh it?
      Joe: I'll refresh the staging database tomorrow, first thing. It's an hour with the
      anonymiser running.
      """,
      expected: [{"staging", %{kind: :relative_day, offset: 1}}]
    },
    %{
      name: "a date said in full",
      transcript: """
      Wes: The insurance renewal is the one hard date this year. The broker wants our
      headcount and claims history before they'll quote.
      Bea: How long do they need?
      Wes: Weeks, apparently. They've been clear about the deadline.
      Bea: Then I'll send the renewal pack to the broker by the 30th of January 2027.
      """,
      expected: [{"renewal", %{kind: :absolute, year: 2027, month: 1, day: 30}}]
    },
    %{
      name: "a date said with its month but not its year",
      transcript: """
      Kim: The regulator has come back asking for the compliance summary. They want the
      control changes we made after the last review.
      Rob: How much detail?
      Kim: Two pages. They've given us a hard date.
      Rob: Fine. I'll get the compliance summary over to them by March the 3rd. I'd rather
      not leave it to the last week.
      """,
      expected: [{"compliance", %{kind: :absolute, year: nil, month: 3, day: 3}}]
    },
    %{
      name: "a date said as a day alone",
      transcript: """
      Nia: Right, month-end. The invoice run goes out on the last working day as usual.
      Tom: Understood. The supplier side is the bit that always slips.
      Nia: It is. Last month we closed three days late because the reconciliation wasn't done.
      Tom: That's on me. I'll have the supplier invoices reconciled by the 12th.
      Nia: The 12th gives us room. Anything blocking you?
      Tom: No, the statements are all in.
      """,
      expected: [{"invoice", %{kind: :absolute, year: nil, month: nil, day: 12}}]
    },
    %{
      name: "the end of a week",
      transcript: """
      Lee: Marketing are waiting on the launch copy. They can't book the ads without it.
      Ivy: I've got a draft. It needs another pass — the second section reads like a spec.
      Lee: How long?
      Ivy: I'll finish the launch copy by the end of the week. They'll have it for their
      Monday planning.
      """,
      expected: [{"copy", %{kind: :span_end, modifier: :this, unit: :week}}]
    },
    %{
      name: "a span that sounds loose but names a stretch of calendar",
      transcript: """
      Raj: Nobody has looked at the onboarding metrics since the redesign shipped. We're
      guessing about whether it helped.
      Eve: I can pull them, but it's a day's work — the events changed name halfway through.
      Raj: It's not urgent. It is worth doing.
      Eve: I'll pull the onboarding metrics together sometime next month, once the migration
      work is off my plate.
      """,
      expected: [{"onboarding", %{kind: :span_end, modifier: :next, unit: :month}}]
    },
    %{
      name: "a duration counted in a number",
      transcript: """
      Gus: Search is the thing customers complain about most. How long do you need for the
      reindex?
      Wes: The reindex itself runs overnight. It's everything around it that takes the time.
      Gus: Meaning it isn't a quick one.
      Wes: It isn't. Give me two weeks and I'll have the search reindex done properly.
      """,
      expected: [{"search", %{kind: :duration, unit: :week, count: 2}}]
    },
    %{
      name: "a duration counted in the one spoken quantifier",
      transcript: """
      Fay: The API docs are out of date since the v2 release. Two support tickets this week
      were people following the old auth flow.
      Omar: I know. The examples all still show the v1 header.
      Fay: Can you get to it?
      Omar: I'll update the API docs in a couple of days. It's mostly the auth page and the
      quickstart.
      """,
      expected: [{"doc", %{kind: :duration, unit: :day, count: :couple}}]
    },
    %{
      name: "a quantifier vaguer than the lexicon holds",
      transcript: """
      Zoe: Can we get the billing migration off the backlog? It's been there since spring.
      Cai: I want to. Support volume is the problem — I'm firefighting most days.
      Zoe: Is there a point where that eases?
      Cai: After the seasonal peak. I'll start the billing migration in a few weeks, once
      support calms down.
      """,
      expected: [{"billing", %{kind: :vague}}]
    },
    %{
      name: "an Action Point the meeting said nothing about the timing of",
      transcript: """
      Hal: The SSO contract is still unsigned. Legal have had their redlines for a
      fortnight and nobody has heard back.
      Ida: I'll chase the vendor. I've got the account manager's number.
      Hal: Thanks. They went quiet the same way last time.
      Ida: I remember.
      """,
      expected: [{"vendor", nil}]
    },
    %{
      name: "timing attached to one Action Point among several",
      transcript: """
      Ben: Three things left before launch. Ari, where's the database migration?
      Ari: Written, not run. It's been tested against a copy of production twice.
      Ben: When can it go?
      Ari: I'll run the database migration by Friday, out of hours.
      Ben: Good. Cleo, the release notes?
      Cleo: I'll draft the release notes. I can't put a date on that yet — I need the final
      scope from you first.
      Ben: Fair. And someone owes me a rollback plan.
      Ari: I'll write the rollback plan too, once things have settled down. No promises
      on when.
      """,
      expected: [
        {"migration", %{kind: :weekday, weekday: :friday, modifier: nil}},
        {"release notes", nil},
        {"rollback", %{kind: :vague}}
      ]
    }
  ]

  setup_all do
    if is_nil(Application.get_env(:action_points, Claude, [])[:api_key]) do
      raise """
      This suite runs against the real API and found no key.

          export ANTHROPIC_API_KEY=...
          mix test --include eval test/eval
      """
    end

    :ok
  end

  for fixture <- @fixtures do
    @fixture fixture

    test "classifies #{fixture.name}" do
      samples = sample(@fixture)
      agreeing = Enum.count(samples, & &1.agrees?)

      assert agreeing >= @required_agreement, report(@fixture, samples, agreeing)
    end
  end

  # `@samples` independent Extractions of the same Transcript, concurrently:
  # they are independent API calls, so sampling costs calls rather than the
  # patience of whoever is waiting on the run. A sample that times out or dies
  # is one disagreeing sample, the same as a failed Extraction below — a
  # tripwire that fell over on one bad call would be the flaky thing it exists
  # not to be.
  defp sample(fixture) do
    1..@samples
    |> Task.async_stream(fn _ -> classify(fixture) end,
      max_concurrency: @samples,
      timeout: 180_000
    )
    |> Enum.map(fn
      {:ok, sample} -> sample
      {:exit, reason} -> %{agrees?: false, found: [], titles: [], error: reason}
    end)
  end

  # One Extraction, read down to what this suite asserts on: the classification
  # each expected topic came back with. A failed Extraction is a sample that
  # agrees with nothing rather than a crash — one refusal or rate limit should
  # read like one wrong sample, not take the run with it.
  defp classify(fixture) do
    case Claude.extract(fixture.transcript) do
      {:ok, %{action_points: action_points}} ->
        found =
          Enum.map(fixture.expected, fn {topic, expected} ->
            {topic, expected, timing_for(action_points, topic)}
          end)

        %{
          agrees?: Enum.all?(found, fn {_topic, expected, actual} -> actual == expected end),
          found: found,
          titles: Enum.map(action_points, & &1.title)
        }

      {:error, reason} ->
        %{agrees?: false, found: [], titles: [], error: reason}
    end
  end

  # The timing on the one Action Point whose title names the topic. Two
  # matches are as much a miss as none: the expectation is that the meeting's
  # commitments came back as distinct Action Points, and a topic naming two of
  # them says the timing cannot have been attached to a single one. Either way
  # the sample disagrees — it reports how many Action Points the topic named,
  # which no classification equals — rather than raising: a fixture the model
  # split unusually in one sample of three is exactly the noise sampling
  # exists to absorb.
  defp timing_for(action_points, topic) do
    case Enum.filter(action_points, &(String.downcase(&1.title) =~ topic)) do
      [action_point] -> action_point.timing
      matches -> {:action_points_named_by_the_topic, length(matches)}
    end
  end

  defp report(fixture, samples, agreeing) do
    """
    #{fixture.name}: #{agreeing} of #{@samples} samples classified as expected, \
    needed #{@required_agreement}.

    #{Enum.map_join(samples, "\n", &describe/1)}
    """
  end

  defp describe(%{error: reason}), do: "  - the Extraction failed: #{inspect(reason)}"

  defp describe(%{agrees?: true}), do: "  - as expected"

  defp describe(sample) do
    mismatches =
      sample.found
      |> Enum.reject(fn {_topic, expected, actual} -> actual == expected end)
      |> Enum.map_join("\n", fn {topic, expected, actual} ->
        ~s(      "#{topic}": expected #{inspect(expected)}, got #{inspect(actual)})
      end)

    """
      - not as expected:
    #{mismatches}
          from: #{Enum.join(sample.titles, ", ")}\
    """
  end
end
