defmodule ActionPoints.Sinks do
  @moduledoc """
  Task Sink connections and everything that depends on one: validating a
  pasted API key and storing it encrypted alongside the chosen team,
  disconnecting, Pushing a Review's Action Points, and — per ADR-0007 —
  resolving their assignees against the connection's remembered Assignee
  Mappings and live member list.

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
  alias ActionPoints.Sinks.AssigneeMapping
  alias ActionPoints.Sinks.SinkConnection

  @doc """
  The configured Task Sink adapter module.
  """
  def task_sink, do: Application.fetch_env!(:action_points, :task_sink)

  @doc """
  Whether the sink declares the optional relation capability — exporting
  `create_relation/2`. Push drops a Review's Blockers when it doesn't, and
  Review says so out loud rather than letting the Push silently lose them.
  """
  def supports_relations?(sink \\ task_sink()) do
    Code.ensure_loaded?(sink) and function_exported?(sink, :create_relation, 2)
  end

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

  Issues come first, then the Review's Blockers as real blocked-by relations
  — so a relation failure leaves every issue intact, and a retry creates only
  what is missing, per edge, exactly like the issues themselves. A sink that
  doesn't declare the relation capability (`supports_relations?/1`) gets the
  issues and drops the relations.

  Returns:

    * `{:ok, pushed}` — every pushable Action Point was created and every
      pushable relation too (`pushed` lists only the issues created this
      call, so a retry that only completed relations returns `{:ok, []}`)
    * `{:error, :not_connected}` — the user has no sink connection
    * `{:error, :push_in_progress}` — another Push of this Extraction is
      already running (a second click or second tab must never double-create)
    * `{:error, {reason, pushed, remaining}}` — the Push stopped at a sink
      failure while creating issues: `pushed` were created this call,
      `remaining` counts the Action Points not created; no relations were
      attempted
    * `{:error, {:relations, reason, created, remaining}}` — every issue
      exists, but the Push stopped partway through the relations: `created`
      were created this call, `remaining` counts the edges not created

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
    case extraction.id |> Meetings.list_pushable_action_points() |> push_each(connection, []) do
      {:ok, pushed} -> push_relations(connection, extraction, pushed)
      {:error, _issue_failure} = error -> error
    end
  end

  # Every issue exists by now, so each pushable Blocker has both its sink
  # issue ids. A sink without the relation capability drops them here —
  # Review already said so visibly, and the issues still land.
  defp push_relations(connection, extraction, pushed) do
    if supports_relations?() do
      case extraction.id
           |> Meetings.list_pushable_blockers()
           |> push_each_relation(connection, 0) do
        :ok -> {:ok, pushed}
        {:error, relation_failure} -> {:error, relation_failure}
      end
    else
      {:ok, pushed}
    end
  end

  defp push_each_relation([], _connection, _created), do: :ok

  defp push_each_relation([blocker | rest], connection, created) do
    relation = %{
      blocked_issue_id: blocker.action_point.sink_issue_id,
      blocking_issue_id: blocker.blocked_by.sink_issue_id
    }

    case task_sink().create_relation(%{api_key: connection.api_key}, relation) do
      {:ok, created_relation} ->
        Meetings.record_relation_push!(blocker, created_relation)
        push_each_relation(rest, connection, created + 1)

      {:error, reason} ->
        {:error, {:relations, reason, created, length(rest) + 1}}
    end
  end

  defp push_each([], _connection, pushed), do: {:ok, Enum.reverse(pushed)}

  defp push_each([action_point | rest], connection, pushed) do
    # Push does no matching of its own (ADR-0007): whatever Review resolved
    # onto the Action Point — or nothing — is exactly what Linear gets.
    task = %{
      title: action_point.title,
      description: compose_description(action_point),
      assignee_id: action_point.assignee_sink_user_id,
      due_date: action_point.due_date
    }

    case task_sink().push_task(%{api_key: connection.api_key}, connection.team_id, task) do
      {:ok, created_task} ->
        action_point = Meetings.record_push!(action_point, created_task)
        remember_assignee_pick(connection, action_point)
        push_each(rest, connection, [action_point | pushed])

      {:error, reason} ->
        {:error, {reason, Enum.reverse(pushed), length(rest) + 1}}
    end
  end

  # The pushed description is the model's prose plus a "From the meeting"
  # section of the surviving Grounding Quotes — composed here, at Push, and
  # never stored, so the format (or the whole feature) can change without a
  # data migration (issue #24). Each quote is its own blockquote: human
  # speech visibly set apart from model prose. No quotes, no section.
  defp compose_description(%{quotes: [], description: description}), do: description

  defp compose_description(%{quotes: quotes, description: description}) do
    section =
      "### From the meeting\n\n" <> Enum.map_join(quotes, "\n\n", &("> " <> &1))

    case description do
      nil -> section
      "" -> section
      prose -> prose <> "\n\n" <> section
    end
  end

  # The pick Review showed becomes the mapping, born the moment it is first
  # Pushed — a suggestion the user never looked at is saved just the same as
  # one they picked by hand (ADR-0007). Nothing is saved for a deliberately
  # unassigned Action Point: that must never harden into "this name means
  # nobody," and an unguessed Action Point has no name to key a mapping on.
  defp remember_assignee_pick(_connection, %{assignee_guess: nil}), do: :ok
  defp remember_assignee_pick(_connection, %{assignee_sink_user_id: nil}), do: :ok

  defp remember_assignee_pick(connection, action_point) do
    key = AssigneeMapping.normalize(action_point.assignee_guess)

    current =
      Repo.get_by(AssigneeMapping, sink_connection_id: connection.id, normalized_guess: key)

    unless current && current.sink_user_id == action_point.assignee_sink_user_id do
      put_assignee_mapping(connection, action_point.assignee_guess, %{
        id: action_point.assignee_sink_user_id,
        name: action_point.assignee_display_name
      })
    end
  end

  ## Assignee resolution (ADR-0007)

  @doc """
  Resolves each of the given Action Points' assignee guesses against the
  scoped user's Task Sink members and remembered Assignee Mappings: a mapping
  hit resolves outright, an unambiguous match against a member's real name
  (full name, then first name — never a handle) resolves as a visible
  suggestion, anything else is left for the user to pick. Only Action Points
  not already resolved are touched, so reopening Review never overwrites a
  pick or an explicit clear.

  Returns `{:ok, sink_users}` — the live, never-stored active members, for
  building a picker — or `{:error, :not_connected | :unavailable}` when there
  is nothing to resolve against. Review then shows the raw guesses as text:
  nothing is ever guessed silently.
  """
  def resolve_assignees(scope, action_points) do
    case get_connection_with_key(scope) do
      nil ->
        {:error, :not_connected}

      connection ->
        case task_sink().list_users(%{api_key: connection.api_key}) do
          {:ok, users} ->
            mappings = mappings_by_guess(connection.id)

            action_points
            |> Enum.filter(&is_nil(&1.assignee_resolution))
            |> Enum.each(&resolve_one(&1, mappings, users))

            {:ok, users}

          {:error, _reason} ->
            {:error, :unavailable}
        end
    end
  end

  defp mappings_by_guess(connection_id) do
    AssigneeMapping
    |> where([m], m.sink_connection_id == ^connection_id)
    |> Repo.all()
    |> Map.new(&{&1.normalized_guess, &1})
  end

  defp resolve_one(%{assignee_guess: nil} = action_point, _mappings, _users) do
    Meetings.resolve_action_point_assignee(action_point, :unassigned, nil)
  end

  defp resolve_one(action_point, mappings, users) do
    key = AssigneeMapping.normalize(action_point.assignee_guess)

    case {Map.get(mappings, key), match_by_name(action_point.assignee_guess, users)} do
      {%AssigneeMapping{} = mapping, _} ->
        sink_user = %{id: mapping.sink_user_id, name: mapping.display_name}
        Meetings.resolve_action_point_assignee(action_point, :mapped, sink_user)

      {nil, %{} = sink_user} ->
        Meetings.resolve_action_point_assignee(action_point, :suggested, sink_user)

      {nil, nil} ->
        Meetings.resolve_action_point_assignee(action_point, :unassigned, nil)
    end
  end

  # An unambiguous match against real names only — never handles, so a
  # guessed "Andrew" can never land on a handle like `@andrewclark12` (the
  # bug this whole feature exists to fix). Exactly one full-name match wins;
  # failing that, exactly one first-name match wins; anything else is left
  # for the user to pick.
  defp match_by_name(guess, users) do
    guess = guess |> String.trim() |> String.downcase()

    full_name_matches = Enum.filter(users, &(String.downcase(&1.name) == guess))

    first_name_matches =
      Enum.filter(users, fn user ->
        user.name |> String.downcase() |> String.split() |> List.first() == guess
      end)

    case {full_name_matches, first_name_matches} do
      {[user], _} -> user
      {[], [user]} -> user
      _ -> nil
    end
  end

  @doc """
  The scoped user's live, active Task Sink members — for the Assignee
  Mapping picker in Sink Settings. Never stored (ADR-0007).
  """
  def list_sink_users(scope) do
    case get_connection_with_key(scope) do
      nil -> {:error, :not_connected}
      connection -> task_sink().list_users(%{api_key: connection.api_key})
    end
  end

  defp get_connection_with_key(nil), do: nil

  defp get_connection_with_key(%Scope{user: %User{id: user_id}}) do
    Repo.get_by(SinkConnection, user_id: user_id)
  end

  ## Assignee Mappings

  @doc """
  Lists the scoped user's Assignee Mappings, alphabetically by the guessed
  name they fire on. Empty (not an error) when there is no connection.
  """
  def list_assignee_mappings(%Scope{} = scope) do
    case get_connection(scope) do
      nil ->
        []

      connection ->
        Repo.all(
          from m in AssigneeMapping,
            where: m.sink_connection_id == ^connection.id,
            order_by: [asc: m.normalized_guess]
        )
    end
  end

  @doc """
  Fetches an Assignee Mapping only if it belongs to the scoped user's
  connection. Raises `Ecto.NoResultsError` otherwise, so a user can never
  reach another account's mapping.
  """
  def get_assignee_mapping!(%Scope{} = scope, id) do
    connection = get_connection(scope) || raise(Ecto.NoResultsError, queryable: AssigneeMapping)
    Repo.get_by!(AssigneeMapping, id: id, sink_connection_id: connection.id)
  end

  @doc """
  Creates or replaces (by guessed name) an Assignee Mapping for the scoped
  user's connection — how a mapping is pre-seeded ahead of Review, or how a
  Push saves the pick it made (ADR-0007). `sink_user` is `%{id:, name:}`,
  optionally `handle:`, from a live `list_sink_users/1` fetch.
  """
  def put_assignee_mapping(%SinkConnection{} = connection, guess, sink_user) do
    %AssigneeMapping{sink_connection_id: connection.id}
    |> AssigneeMapping.changeset(%{
      normalized_guess: AssigneeMapping.normalize(guess),
      sink_user_id: sink_user.id,
      display_name: sink_user.name,
      handle: Map.get(sink_user, :handle)
    })
    |> Repo.insert(
      on_conflict: {:replace, [:sink_user_id, :display_name, :handle, :updated_at]},
      conflict_target: [:sink_connection_id, :normalized_guess]
    )
  end

  def put_assignee_mapping(%Scope{} = scope, guess, sink_user) do
    connection = get_connection(scope) || raise(Ecto.NoResultsError, queryable: AssigneeMapping)
    put_assignee_mapping(connection, guess, sink_user)
  end

  @doc """
  Repoints an existing Assignee Mapping at a different Task Sink member. The
  guessed name it fires on is unchanged.
  """
  def update_assignee_mapping(%AssigneeMapping{} = mapping, sink_user) do
    mapping
    |> AssigneeMapping.changeset(%{
      sink_user_id: sink_user.id,
      display_name: sink_user.name,
      handle: Map.get(sink_user, :handle)
    })
    |> Repo.update()
  end

  @doc """
  Deletes an Assignee Mapping — that guessed name goes back to resolving by
  suggestion (or nothing) until it is mapped again.
  """
  def delete_assignee_mapping(%AssigneeMapping{} = mapping) do
    Repo.delete(mapping)
  end

  @doc """
  Removes the scoped user's connection, revoking this app's use of the key.
  Its Assignee Mappings cascade-delete with it (ADR-0007): a sink user id is
  meaningless outside the workspace it named a member in.
  """
  def disconnect(%Scope{user: %User{id: user_id}}) do
    Repo.delete_all(from c in SinkConnection, where: c.user_id == ^user_id)
    :ok
  end
end
