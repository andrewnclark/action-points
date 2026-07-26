defmodule ActionPoints.Sinks.TaskSink do
  @moduledoc """
  The Task Sink port: a destination system that receives pushed Action Points
  as real tasks (ADR-0002). Linear is the only launch implementation
  (`ActionPoints.Sinks.Linear`); tests replace it with
  `ActionPoints.Sinks.FakeTaskSink` via the `:task_sink` application env.

  `push_task/3` pushes one task at a time so a mid-Push failure leaves a
  per-task record of what was and wasn't created, and a retry can create only
  the missing ones.
  """

  @type credentials :: %{required(:api_key) => String.t()}
  @type team :: %{required(:id) => String.t(), required(:name) => String.t()}
  @type sink_user :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:handle) => String.t()
        }

  @type task :: %{
          required(:title) => String.t(),
          required(:description) => String.t() | nil,
          required(:assignee_id) => String.t() | nil,
          required(:due_date) => Date.t() | nil
        }

  @type created_task :: %{
          required(:id) => String.t(),
          required(:identifier) => String.t(),
          required(:url) => String.t()
        }

  @type failure :: :invalid_key | :rate_limited | :unavailable | :api_error

  @callback validate_credentials(credentials()) :: :ok | {:error, failure()}
  @callback list_teams(credentials()) :: {:ok, [team()]} | {:error, failure()}

  # Deactivated members are filtered out by the adapter — the caller never
  # sees someone who has left the workspace (ADR-0007).
  @callback list_users(credentials()) :: {:ok, [sink_user()]} | {:error, failure()}
  @callback push_task(credentials(), team_id :: String.t(), task()) ::
              {:ok, created_task()} | {:error, failure()}
end
