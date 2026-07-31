defmodule ActionPoints.ExtractionHelpers do
  @moduledoc """
  Shared helpers for tests that drive Extractions end to end. Tests using the
  stubs must be `async: false` — they script globals (app env, the shared
  rate limiter).
  """

  alias ActionPoints.RateLimiter

  @doc """
  Scripts the FakeExtractor's next result, restored on test exit.

  A bare list of Action Points is shorthand for "and the Transcript stated no
  meeting date", so the many tests with nothing to say about the meeting date
  need not restate the whole port shape. The shorthand lives here rather than
  in the double, which speaks only the port's own shape.
  """
  def stub_extractor(result) do
    Application.put_env(:action_points, :fake_extractor_result, expand(result))

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:action_points, :fake_extractor_result)
    end)
  end

  defp expand({:ok, action_points}) when is_list(action_points) do
    {:ok, %{action_points: action_points, meeting_date: nil}}
  end

  defp expand(result), do: result

  @doc """
  Overrides the anonymous rate limits and resets the shared limiter, both
  restored on test exit.
  """
  def override_anon_limits(limits) do
    original = Application.fetch_env!(:action_points, :anon_extraction_rate_limits)
    Application.put_env(:action_points, :anon_extraction_rate_limits, limits)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:action_points, :anon_extraction_rate_limits, original)
    end)

    RateLimiter.reset()
    ExUnit.Callbacks.on_exit(fn -> RateLimiter.reset() end)
  end

  @doc """
  The Extraction runs in a background task, so screens settle asynchronously —
  retries the assertion until it passes or time runs out.
  """
  def eventually(fun, tries \\ 100) do
    fun.()
  rescue
    e in [ExUnit.AssertionError] ->
      if tries == 0 do
        reraise(e, __STACKTRACE__)
      else
        Process.sleep(20)
        eventually(fun, tries - 1)
      end
  end

  @doc """
  Accepts every one of an Extraction's Action Points, leaving the Review where
  the old `:accepted` default used to leave it.

  Since ADR-0010 an Action Point starts `:undecided`, so a test about what
  happens *after* Review — a Push, a pushed relation, a tally, a screen that
  only makes sense for an accepted Action Point — has to state the decisions it
  stands on instead of inheriting them from a default. Returns the Action
  Points as stored, in the order given.
  """
  def accept_action_points(action_points) when is_list(action_points) do
    Enum.map(action_points, &ActionPoints.Meetings.set_action_point_status(&1, :accepted))
  end
end
