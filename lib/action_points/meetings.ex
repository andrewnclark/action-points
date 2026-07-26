defmodule ActionPoints.Meetings do
  @moduledoc """
  The meetings pipeline: Transcript → Extraction → Action Points → Review state.

  An Extraction is persisted server-side and keyed to the visitor's anonymous
  session token, so their Review survives signup. The Extraction itself runs as a
  background task; progress reaches LiveViews via PubSub (`subscribe/1`).
  """

  import Ecto.Query

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.Accounts.User
  alias ActionPoints.Billing
  alias ActionPoints.Meetings.ActionPoint
  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.RateLimiter
  alias ActionPoints.Repo

  ## Extractions

  @doc """
  Returns a changeset for the paste-a-transcript form.
  """
  def change_extraction(%Extraction{} = extraction, attrs \\ %{}) do
    Extraction.changeset(extraction, attrs)
  end

  @doc """
  Creates a pending Extraction keyed to the anonymous session token, on behalf
  of `scope` (nil for an anonymous visitor).

  The gates live here so no create path can skip them: a signed-in user must
  hold at least one Credit (`{:error, :out_of_credits}` — the caller routes
  them to the buy page), and anonymous creation is rate-limited per session
  and per IP (`{:error, :rate_limited}`, IP passed as `opts[:ip]`). Invalid
  input is reported first, so a fumbled form never burns the rate limit.
  """
  def create_extraction(scope, session_token, attrs, opts \\ [])
      when is_binary(session_token) do
    changeset =
      %Extraction{session_token: session_token, user_id: scope_user_id(scope)}
      |> Extraction.changeset(attrs)

    with true <- changeset.valid?,
         :ok <- gate_new_extraction(scope, session_token, opts) do
      Repo.insert(changeset)
    else
      false -> {:error, %{changeset | action: :insert}}
      {:error, _reason} = error -> error
    end
  end

  defp scope_user_id(%Scope{user: %User{id: id}}), do: id
  defp scope_user_id(nil), do: nil

  defp gate_new_extraction(%Scope{user: %User{}} = scope, _session_token, _opts) do
    ensure_credit_available(scope)
  end

  # The anonymous Demo is free, so it is rate-limited instead. Both keys
  # must allow; the check short-circuits, so a denied session key doesn't
  # count against the IP.
  defp gate_new_extraction(nil, session_token, opts) do
    limits = Application.fetch_env!(:action_points, :anon_extraction_rate_limits)

    keys =
      [{{:anon_session, session_token}, limits[:session]}] ++
        case opts[:ip] do
          nil -> []
          ip -> [{{:anon_ip, ip}, limits[:ip]}]
        end

    allowed? =
      Enum.all?(keys, fn {key, {limit, window_ms}} ->
        RateLimiter.allow?(key, limit, window_ms)
      end)

    if allowed?, do: :ok, else: {:error, :rate_limited}
  end

  # Checked at attempt time, consumed at success time — two concurrent
  # successes on a one-Credit balance can briefly overdraw. Accepted for the
  # MVP: the ledger stays truthful and the next attempt is gated.
  defp ensure_credit_available(scope) do
    if Billing.balance(scope) >= 1, do: :ok, else: {:error, :out_of_credits}
  end

  @doc """
  Claims the anonymous session's Extractions for a user who just signed in —
  the moment the Demo's Review starts belonging to an account instead of a
  browser. Only unowned Extractions are touched, so a shared browser can never
  reassign another account's work. The ledger is untouched: the Extraction ran
  anonymously, and anonymous Extractions are free.

  Returns the claimed Extractions, most recently created first (by id — the
  insertion order).
  """
  def claim_session_extractions(%User{}, nil), do: []

  def claim_session_extractions(%User{id: user_id}, session_token)
      when is_binary(session_token) do
    {_count, extractions} =
      Repo.update_all(
        from(e in Extraction,
          where: e.session_token == ^session_token and is_nil(e.user_id),
          select: e
        ),
        set: [
          user_id: user_id,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      )

    Enum.sort_by(extractions, & &1.id, :desc)
  end

  @doc """
  Fetches an Extraction (with its Action Points) only if it belongs to the
  given session token. Raises `Ecto.NoResultsError` otherwise, so a visitor
  can never read another session's Review.
  """
  def get_extraction!(id, session_token) when is_binary(session_token) do
    Extraction
    |> Repo.get_by!(id: id, session_token: session_token)
    |> Repo.preload(:action_points)
  end

  @doc """
  Runs the Extraction as a supervised background task — LLM latency on a big
  transcript is tens of seconds, so it never runs in the request cycle.
  """
  def start_extraction(%Extraction{} = extraction) do
    {:ok, _pid} =
      Task.Supervisor.start_child(ActionPoints.TaskSupervisor, fn ->
        run_extraction(extraction)
      end)

    :ok
  end

  @doc """
  Resets a failed Extraction and runs it again. The failure itself consumed no
  Credit, but a retry is a fresh attempt: for a signed-in owner the zero-Credit
  gate applies just like on create (`{:error, :out_of_credits}`).

  The reset is a single conditional UPDATE, so two rapid retries can never
  start two concurrent runs.
  """
  def retry_extraction(%Extraction{id: id} = extraction) do
    with :ok <- gate_retry(extraction) do
      {reset_count, _} =
        Repo.update_all(
          from(e in Extraction, where: e.id == ^id and e.status == :failed),
          set: [
            status: :pending,
            failure_reason: nil,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        )

      if reset_count == 1 do
        extraction = Repo.get!(Extraction, id)
        broadcast(extraction)
        start_extraction(extraction)
      end

      :ok
    end
  end

  defp gate_retry(%Extraction{user_id: nil}), do: :ok

  defp gate_retry(%Extraction{user_id: user_id}) do
    ensure_credit_available(Scope.for_user(%User{id: user_id}))
  end

  @doc """
  The background-task body: marks the Extraction running, calls the Extractor
  port, and finalises success or failure. Each transition is broadcast.

  A crash anywhere in the attempt still marks the Extraction failed — the
  Review screen must always end up on the error-with-retry state, never a
  permanent spinner.
  """
  def run_extraction(%Extraction{} = extraction) do
    extraction = update_status!(extraction, %{status: :running})
    broadcast(extraction)

    case extractor().extract(extraction.transcript_text) do
      {:ok, action_points} -> finalize_success(extraction, action_points)
      {:error, reason} -> finalize_failure(extraction, reason)
    end
  rescue
    exception ->
      finalize_failure(extraction, :crashed)
      reraise(exception, __STACKTRACE__)
  end

  defp finalize_success(extraction, action_points) do
    {:ok, extraction} =
      Repo.transaction(fn ->
        # Idempotence: a re-run replaces, never appends
        Repo.delete_all(from ap in ActionPoint, where: ap.extraction_id == ^extraction.id)

        action_points
        |> Enum.with_index(1)
        |> Enum.each(fn {attrs, position} ->
          %ActionPoint{extraction_id: extraction.id, position: position}
          |> ActionPoint.changeset(attrs)
          |> Repo.insert!()
        end)

        # The Credit is consumed atomically with success — a crash here can't
        # charge without delivering. Anonymous Extractions have no one to
        # charge and stay free.
        if extraction.user_id do
          Billing.consume_extraction_credit!(extraction.user_id, extraction.id)
        end

        update_status!(extraction, %{status: :succeeded})
      end)

    broadcast(extraction)
    extraction
  end

  defp finalize_failure(extraction, reason) do
    extraction = update_status!(extraction, %{status: :failed, failure_reason: to_string(reason)})
    broadcast(extraction)
    extraction
  end

  defp update_status!(extraction, attrs) do
    extraction
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end

  ## Review curation

  @doc """
  Fetches an Action Point only if its Extraction belongs to the given session
  token. Raises `Ecto.NoResultsError` otherwise, so a visitor can never curate
  another session's Review.
  """
  def get_action_point!(id, session_token) when is_binary(session_token) do
    Repo.one!(
      from ap in ActionPoint,
        join: e in assoc(ap, :extraction),
        where: ap.id == ^id and e.session_token == ^session_token
    )
  end

  @doc """
  Marks an Action Point accepted or rejected. Rejection is reversible — the
  row keeps everything except its standing in the Review.
  """
  def set_action_point_status(%ActionPoint{} = action_point, status)
      when status in [:accepted, :rejected] do
    action_point
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  @doc """
  Returns a changeset for the Review's inline-edit form.
  """
  def change_action_point(%ActionPoint{} = action_point, attrs \\ %{}) do
    ActionPoint.curation_changeset(action_point, attrs)
  end

  @doc """
  Applies the user's Review edits to an Action Point.
  """
  def update_action_point(%ActionPoint{} = action_point, attrs) do
    action_point
    |> ActionPoint.curation_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Counts the Action Points a Push would create right now — accepted in the
  Review and not yet pushed. This is the number the Push button promises.
  """
  def count_pushable_action_points(extraction_id) do
    Repo.aggregate(pushable_query(extraction_id), :count)
  end

  # Pushable: accepted in the Review and not yet pushed. The single place the
  # predicate is written in SQL; `ActionPoint.pushable?/1` is its in-memory twin.
  defp pushable_query(extraction_id) do
    from ap in ActionPoint,
      where:
        ap.extraction_id == ^extraction_id and ap.status == :accepted and
          is_nil(ap.sink_issue_id)
  end

  ## Push bookkeeping

  @doc """
  Lists the Action Points a Push still has to create: accepted in the Review
  and carrying no created-issue reference yet. A retry after a partial Push
  therefore picks up exactly the missing ones — never a duplicate.
  """
  def list_pushable_action_points(extraction_id) do
    Repo.all(from ap in pushable_query(extraction_id), order_by: [asc: ap.position])
  end

  @doc """
  Records the created-issue reference on a pushed Action Point — the moment it
  stops being a proposal and becomes a real task in the Task Sink.
  """
  def record_push!(%ActionPoint{} = action_point, %{id: id, identifier: identifier, url: url}) do
    action_point
    |> Ecto.Changeset.change(
      sink_issue_id: id,
      sink_issue_identifier: identifier,
      sink_issue_url: url
    )
    |> Repo.update!()
  end

  ## PubSub

  @doc """
  Subscribes the caller to status updates for one Extraction. Messages arrive
  as `{:extraction_updated, extraction_id}`. Takes the id (not the struct) so
  a LiveView can subscribe *before* fetching — otherwise an update broadcast
  between fetch and subscribe would be lost.
  """
  def subscribe(extraction_id) do
    Phoenix.PubSub.subscribe(ActionPoints.PubSub, topic(extraction_id))
  end

  defp broadcast(%Extraction{id: id}) do
    Phoenix.PubSub.broadcast(ActionPoints.PubSub, topic(id), {:extraction_updated, id})
  end

  defp topic(id), do: "extraction:#{id}"

  defp extractor do
    Application.fetch_env!(:action_points, :extractor)
  end
end
