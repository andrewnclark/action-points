defmodule ActionPoints.Sinks.FakeTaskSink do
  @moduledoc """
  Test double for the Task Sink port. Tests script results per callback with:

      Application.put_env(:action_points, :fake_task_sink,
        validate: {:error, :invalid_key},
        teams: {:ok, [%{id: "team-1", name: "Engineering"}]}
      )

  Unscripted callbacks return canned successes. Pushed tasks accumulate under
  the `:pushes` key of the `:fake_task_sink_pushes` env so tests can assert
  what the sink was asked to create.
  """

  @behaviour ActionPoints.Sinks.TaskSink

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
    scripted(:users, {:ok, [%{id: "user-1", name: "Priya"}]})
  end

  @impl true
  def push_task(_credentials, team_id, task) do
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

  defp scripted(key, default) do
    :action_points
    |> Application.get_env(:fake_task_sink, [])
    |> Keyword.get(key, default)
  end
end
