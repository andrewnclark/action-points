defmodule ActionPoints.RateLimiterTest do
  use ExUnit.Case, async: true

  alias ActionPoints.RateLimiter

  setup do
    name = :"rate_limiter_#{System.unique_integer([:positive])}"
    start_supervised!({RateLimiter, name: name})
    %{limiter: name}
  end

  test "allows calls up to the limit within one window", %{limiter: limiter} do
    assert RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))
    assert RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))
    assert RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))
  end

  test "blocks the call over the limit", %{limiter: limiter} do
    for _ <- 1..3, do: RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))

    refute RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))
  end

  test "keys are counted independently", %{limiter: limiter} do
    for _ <- 1..3, do: RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))

    assert RateLimiter.allow?(limiter, {:session, "other"}, 3, :timer.hours(1))
    assert RateLimiter.allow?(limiter, {:ip, "abc"}, 3, :timer.hours(1))
  end

  test "an expired window starts a fresh count", %{limiter: limiter} do
    for _ <- 1..3, do: RateLimiter.allow?(limiter, {:session, "abc"}, 3, 10)

    Process.sleep(20)

    assert RateLimiter.allow?(limiter, {:session, "abc"}, 3, 10)
  end

  test "reset/1 clears every counter (test isolation helper)", %{limiter: limiter} do
    for _ <- 1..3, do: RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))

    RateLimiter.reset(limiter)

    assert RateLimiter.allow?(limiter, {:session, "abc"}, 3, :timer.hours(1))
  end
end
