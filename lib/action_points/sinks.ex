defmodule ActionPoints.Sinks do
  @moduledoc """
  Task Sink connections: validating a pasted API key against the sink,
  storing it encrypted alongside the chosen team, and disconnecting.

  The sink itself sits behind the `ActionPoints.Sinks.TaskSink` behaviour —
  Linear in production, a fake in tests — selected via the `:task_sink`
  application env.
  """

  import Ecto.Query

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.Accounts.User
  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.Repo
  alias ActionPoints.Sinks.SinkConnection

  @doc """
  The configured Task Sink adapter module.
  """
  def task_sink, do: Application.fetch_env!(:action_points, :task_sink)

  @doc """
  Returns the scoped user's sink connection, or nil when not connected.

  The decrypted API key is deliberately blanked — display needs only the
  masked tail, and nothing should hold the plaintext longer than a Push call.
  """
  def get_connection(%Scope{user: %User{id: user_id}}) do
    case Repo.get_by(SinkConnection, user_id: user_id) do
      nil -> nil
      connection -> %{connection | api_key: nil}
    end
  end

  @doc """
  Validates a pasted API key against the sink and, when it holds, returns the
  teams the user can push to — so a bad key fails here, not mid-Push.
  """
  def validate_key(api_key) when is_binary(api_key) do
    credentials = %{api_key: api_key}

    with :ok <- task_sink().validate_credentials(credentials) do
      task_sink().list_teams(credentials)
    end
  end

  @doc """
  Stores the scoped user's connection: the validated key (encrypted at rest)
  plus the chosen team. Replaces any existing connection in place.
  """
  def connect(%Scope{user: %User{id: user_id}}, attrs) do
    %SinkConnection{user_id: user_id}
    |> SinkConnection.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:api_key, :api_key_last4, :team_id, :team_name, :updated_at]},
      conflict_target: :user_id
    )
  end

  @doc """
  Pushes the Review's accepted Action Points into the scoped user's connected
  Task Sink, one task at a time, recording each created-issue reference as it
  lands. Only unpushed Action Points are attempted, so calling again after a
  partial failure creates exactly the missing ones.

  Returns:

    * `{:ok, pushed}` — every pushable Action Point was created
    * `{:error, :not_connected}` — the user has no sink connection
    * `{:error, :push_in_progress}` — another Push of this Extraction is
      already running (a second click or second tab must never double-create)
    * `{:error, {reason, pushed, remaining}}` — the Push stopped at a sink
      failure: `pushed` were created this call, `remaining` counts the
      Action Points not created

  A Push never touches the Credit ledger — the Credit belongs to the
  successful Extraction.
  """
  def push(%Scope{user: %User{id: user_id}}, %Extraction{} = extraction) do
    case Repo.get_by(SinkConnection, user_id: user_id) do
      nil ->
        {:error, :not_connected}

      connection ->
        # One Push per Extraction at a time: the unpushed set is read before
        # any issue is created, so two overlapping Pushes would both push it.
        lock = {{:push_extraction, extraction.id}, self()}

        case :global.trans(
               lock,
               fn -> do_push(connection, extraction) end,
               [node() | Node.list()],
               0
             ) do
          :aborted -> {:error, :push_in_progress}
          result -> result
        end
    end
  end

  defp do_push(connection, extraction) do
    credentials = %{api_key: connection.api_key}

    extraction.id
    |> Meetings.list_pushable_action_points()
    |> push_each(connection, sink_users(credentials), [])
  end

  # Assignee matching is best-effort: an unreachable user list degrades to
  # unassigned tasks rather than failing the whole Push.
  defp sink_users(credentials) do
    case task_sink().list_users(credentials) do
      {:ok, users} -> users
      {:error, _reason} -> []
    end
  end

  defp push_each([], _connection, _users, pushed), do: {:ok, Enum.reverse(pushed)}

  defp push_each([action_point | rest], connection, users, pushed) do
    task = %{
      title: action_point.title,
      description: action_point.description,
      assignee_id: match_assignee(action_point.assignee_guess, users),
      due_date: action_point.due_date
    }

    case task_sink().push_task(%{api_key: connection.api_key}, connection.team_id, task) do
      {:ok, created_task} ->
        action_point = Meetings.record_push!(action_point, created_task)
        push_each(rest, connection, users, [action_point | pushed])

      {:error, reason} ->
        {:error, {reason, Enum.reverse(pushed), length(rest) + 1}}
    end
  end

  # A guess assigns only on an unambiguous match — exactly one sink user with
  # that full name, or failing that exactly one whose first name is the guess.
  # Anything else is left unassigned: a bad guess must never mis-assign.
  defp match_assignee(nil, _users), do: nil

  defp match_assignee(guess, users) do
    guess = guess |> String.trim() |> String.downcase()

    full_name_matches = Enum.filter(users, &(String.downcase(&1.name) == guess))

    first_name_matches =
      Enum.filter(users, fn user ->
        user.name |> String.downcase() |> String.split() |> List.first() == guess
      end)

    case {full_name_matches, first_name_matches} do
      {[user], _} -> user.id
      {[], [user]} -> user.id
      _ -> nil
    end
  end

  @doc """
  Removes the scoped user's connection, revoking this app's use of the key.
  """
  def disconnect(%Scope{user: %User{id: user_id}}) do
    Repo.delete_all(from c in SinkConnection, where: c.user_id == ^user_id)
    :ok
  end
end
