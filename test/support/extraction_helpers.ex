defmodule ActionPoints.ExtractionHelpers do
  @moduledoc """
  Shared helpers for tests that drive Extractions end to end. Tests using the
  stubs must be `async: false` — they script globals (app env, the shared
  rate limiter).
  """

  alias ActionPoints.RateLimiter

  @doc """
  Scripts the FakeExtractor's next result, restored on test exit.
  """
  def stub_extractor(result) do
    Application.put_env(:action_points, :fake_extractor_result, result)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:action_points, :fake_extractor_result)
    end)
  end

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
end
