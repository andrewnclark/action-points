defmodule ActionPoints.Sinks.FakeTaskSink do
  @moduledoc """
  Test double for the Task Sink port. Tests script results per callback with:

      Application.put_env(:action_points, :fake_task_sink,
        validate: {:error, :invalid_key},
        teams: {:ok, [%{id: "team-1", name: "Engineering"}]}
      )

  Unscripted callbacks return canned successes. A scripted *list* is consumed
  one element per call (then back to the default), which is how tests stage a
  mid-Push failure:

      Application.put_env(:action_points, :fake_task_sink,
        push: [:ok, {:error, :unavailable}]
      )

  Pushed tasks accumulate in the `:fake_task_sink_pushes` env so tests can
  assert what the sink was asked to create.
  """

  @behaviour ActionPoints.Sinks.TaskSink

  # Hierarchy-capable by default, like Linear; scripted off with
  # `supports_hierarchy: false` to stand in for a flat sink.
  @impl true
  def supports_hierarchy?, do: scripted(:supports_hierarchy, true)

  @impl true
  def validate_credentials(_credentials), do: scripted(:validate, :ok)

  @impl true
  def list_teams(_credentials) do
    scripted(
      :teams,
      {:ok, [%{id: "team-1", name: "Engineering"}, %{id: "team-2", name: "Design"}]}
    )
  end

  @impl true
  def list_users(_credentials) do
    scripted(:users, {:ok, [%{id: "user-1", name: "Priya", handle: "priya"}]})
  end

  @impl true
  def push_task(_credentials, team_id, task) do
    await_push_gate()

    case scripted(:push, :ok) do
      :ok ->
        pushes = Application.get_env(:action_points, :fake_task_sink_pushes, [])
        number = length(pushes) + 1
        Application.put_env(:action_points, :fake_task_sink_pushes, pushes ++ [{team_id, task}])

        {:ok,
         %{
           id: "issue-#{number}",
           identifier: "ENG-#{number}",
           url: "https://linear.app/fake/issue/ENG-#{number}"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # With `push_gate: test_pid` scripted, every push_task call announces itself
  # to the test and blocks until told to proceed — how concurrency tests hold
  # a Push deterministically mid-flight.
  defp await_push_gate do
    case Application.get_env(:action_points, :fake_task_sink, [])[:push_gate] do
      nil ->
        :ok

      gate_pid ->
        send(gate_pid, {:push_task_called, self()})

        receive do
          :proceed -> :ok
        end
    end
  end

  defp scripted(key, default) do
    script = Application.get_env(:action_points, :fake_task_sink, [])

    case Keyword.get(script, key, default) do
      [] ->
        default

      [next | rest] ->
        Application.put_env(:action_points, :fake_task_sink, Keyword.put(script, key, rest))
        next

      value ->
        value
    end
  end
end
