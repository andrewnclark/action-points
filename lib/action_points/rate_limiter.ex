defmodule ActionPoints.RateLimiter do
  @moduledoc """
  Fixed-window rate limiter for the anonymous landing preview, so abuse can't
  burn the operator's API budget. Counters live in this process's state —
  per-node and gone on restart, which is plenty for a single-node MVP.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records one call against `key` and returns whether it is within `limit`
  calls per `window_ms`. Denied calls are not recorded, so being over the
  limit never extends the window.
  """
  def allow?(server \\ __MODULE__, key, limit, window_ms) do
    GenServer.call(server, {:allow?, key, limit, window_ms})
  end

  @doc """
  Clears every counter. For test isolation only.
  """
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:allow?, key, limit, window_ms}, _from, counters) do
    now = System.monotonic_time(:millisecond)

    {count, window_started_at} =
      case counters do
        %{^key => {_count, started_at} = counter} when now - started_at < window_ms -> counter
        _expired_or_absent -> {0, now}
      end

    if count < limit do
      {:reply, true, Map.put(counters, key, {count + 1, window_started_at})}
    else
      {:reply, false, counters}
    end
  end

  def handle_call(:reset, _from, _counters), do: {:reply, :ok, %{}}
end
