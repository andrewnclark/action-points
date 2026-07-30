defmodule ActionPoints.Sinks.FakeFlatTaskSink do
  @moduledoc """
  A Task Sink double that does *not* declare the optional relation capability
  — how tests exercise Push against a sink that can only receive flat tasks.
  Everything else behaves exactly like `ActionPoints.Sinks.FakeTaskSink`.
  """

  @behaviour ActionPoints.Sinks.TaskSink

  alias ActionPoints.Sinks.FakeTaskSink

  @impl true
  defdelegate validate_credentials(credentials), to: FakeTaskSink

  @impl true
  defdelegate list_teams(credentials), to: FakeTaskSink

  @impl true
  defdelegate list_users(credentials), to: FakeTaskSink

  @impl true
  defdelegate push_task(credentials, team_id, task), to: FakeTaskSink
end
