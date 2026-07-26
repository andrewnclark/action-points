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
  Removes the scoped user's connection, revoking this app's use of the key.
  """
  def disconnect(%Scope{user: %User{id: user_id}}) do
    Repo.delete_all(from c in SinkConnection, where: c.user_id == ^user_id)
    :ok
  end
end
