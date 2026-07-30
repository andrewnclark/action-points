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
  alias ActionPoints.Meetings.Blocker
  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.Meetings.GroundingQuote
  alias ActionPoints.Meetings.Timing
  alias ActionPoints.Meetings.TimingQuote
  alias ActionPoints.Meetings.Transcript
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

  The meeting date is settled here, best evidence first: an unambiguous date in
  `opts[:filename]` (the uploaded file's own name), then `opts[:local_date]` —
  the visitor's own local date as their browser reported it — and finally the
  server's date when neither arrived.
  """
  def create_extraction(scope, session_token, attrs, opts \\ [])
      when is_binary(session_token) do
    {meeting_date, meeting_date_source} = settle_meeting_date(opts)

    changeset =
      %Extraction{
        session_token: session_token,
        user_id: scope_user_id(scope),
        meeting_date: meeting_date,
        meeting_date_source: meeting_date_source
      }
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
  How many Action Points are waiting to Push on the Demo Review an anonymous
  session is carrying — or `nil` when there is no Demo behind the visitor at
  all. Zero is a real answer: a Review whose Action Points were all rejected
  still carries over.

  Read-only counterpart to `claim_session_extractions/2`: the signup screens use
  it to state what is being kept, so the carry-over is said by the page the
  visitor is looking at rather than by a flash that evaporates behind them.
  """
  def session_review_pushable_count(session_token) do
    case session_review(session_token) do
      nil -> nil
      extraction -> count_pushable_action_points(extraction.id)
    end
  end

  # The Review a session is carrying: its most recent succeeded, unclaimed
  # Extraction. A running or failed one is not a Review to carry.
  defp session_review(nil), do: nil

  defp session_review(session_token) when is_binary(session_token) do
    Repo.one(
      from e in Extraction,
        where: e.session_token == ^session_token and is_nil(e.user_id) and e.status == :succeeded,
        order_by: [desc: e.id],
        limit: 1
    )
  end

  @doc """
  Fetches an Extraction (with its Action Points) only if it belongs to the
  given session token. Raises `Ecto.NoResultsError` otherwise, so a visitor
  can never read another session's Review.
  """
  def get_extraction!(id, session_token) when is_binary(session_token) do
    Extraction
    |> Repo.get_by!(id: id, session_token: session_token)
    |> Repo.preload(action_points: [blockers: :blocked_by])
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

  A retry is a fresh run, so an *assumed* meeting date is recomputed from
  `opts[:local_date]` (the retrying visitor's own local date) rather than kept
  stale. A date derived from evidence — filename or Transcript — stays.
  """
  def retry_extraction(%Extraction{id: id} = extraction, opts \\ []) do
    with :ok <- gate_retry(extraction) do
      reset =
        [
          status: :pending,
          failure_reason: nil,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ] ++
          case extraction.meeting_date_source do
            :assumed -> [meeting_date: assumed_meeting_date(opts)]
            _derived -> []
          end

      {reset_count, _} =
        Repo.update_all(
          from(e in Extraction, where: e.id == ^id and e.status == :failed),
          set: reset
        )

      if reset_count == 1 do
        extraction = Repo.get!(Extraction, id)
        broadcast(extraction)
        start_extraction(extraction)
      end

      :ok
    end
  end

  # The anchor and where it came from, in one place. A filename date is
  # evidence about the meeting itself, so it outranks the date the visitor
  # happens to be uploading on.
  defp settle_meeting_date(opts) do
    case opts[:filename] && Transcript.date_from_filename(opts[:filename]) do
      %Date{} = date -> {date, :filename}
      _none -> {assumed_meeting_date(opts), :assumed}
    end
  end

  # The assumed anchor: the visitor's own local date when their browser
  # supplied it, the server's date when it didn't.
  defp assumed_meeting_date(opts), do: opts[:local_date] || Date.utc_today()

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
    extraction = update_extraction!(extraction, %{status: :running})
    broadcast(extraction)

    case extractor().extract(extraction.transcript_text) do
      {:ok, result} -> finalize_success(extraction, result)
      {:error, reason} -> finalize_failure(extraction, reason)
    end
  rescue
    exception ->
      finalize_failure(extraction, :crashed)
      reraise(exception, __STACKTRACE__)
  end

  defp finalize_success(extraction, %{action_points: action_points} = result) do
    # Every relative deadline resolves against the Meeting Date, and the
    # strongest anchor arrives with this very result: a date the Transcript
    # itself states (`stated_meeting_date/1`) beats whatever was settled at
    # creation.
    anchor = stated_meeting_date(result)[:meeting_date] || extraction.meeting_date

    {:ok, extraction} =
      Repo.transaction(fn ->
        # Idempotence: a re-run replaces, never appends. Blockers ride along —
        # they cascade-delete with the Action Points they relate.
        Repo.delete_all(from ap in ActionPoint, where: ap.extraction_id == ^extraction.id)

        inserted =
          action_points
          |> sanitize_parent_refs()
          |> Enum.with_index(1)
          |> Enum.map(fn {attrs, position} ->
            parent = attrs.parent

            attrs =
              attrs
              |> verify_quotes(extraction)
              |> verify_timing_quote(extraction)
              |> resolve_due_date(anchor)

            action_point =
              %ActionPoint{extraction_id: extraction.id, position: position}
              |> ActionPoint.changeset(attrs)
              |> Repo.insert!()

            {position, action_point, parent}
          end)

        # Second pass: parent references arrive by position, and a child may
        # be listed before its parent, so ids only exist once every row does.
        ids_by_position =
          Map.new(inserted, fn {position, action_point, _parent} ->
            {position, action_point.id}
          end)

        Enum.each(inserted, fn
          {_position, _action_point, nil} ->
            :ok

          {_position, action_point, parent} ->
            action_point
            |> Ecto.Changeset.change(parent_id: Map.fetch!(ids_by_position, parent))
            |> Repo.update!()
        end)

        persist_blockers(action_points, ids_by_position)

        # The Credit is consumed atomically with success — a crash here can't
        # charge without delivering. Anonymous Extractions have no one to
        # charge and stay free.
        if extraction.user_id do
          Billing.consume_extraction_credit!(extraction.user_id, extraction.id)
        end

        update_extraction!(
          extraction,
          Map.merge(%{status: :succeeded}, stated_meeting_date(result))
        )
      end)

    broadcast(extraction)
    extraction
  end

  # The model classifies, the application resolves: the due date an Action
  # Point is born with is Timing's calendar arithmetic over the model's
  # classification, anchored on the Meeting Date. From here on it is an
  # ordinary due date — edited or cleared at Review, pushed like a
  # hand-entered one.
  defp resolve_due_date(attrs, anchor) do
    Map.put(attrs, :due_date, Timing.resolve(Map.get(attrs, :timing), anchor))
  end

  # The last link in the anchor chain, and the strongest: a date the Transcript
  # itself states beats both the filename and the visitor's local date. It can
  # only be applied here, because only the model can read it — which is why the
  # anchor set at creation is provisional until the Extraction finalises.
  defp stated_meeting_date(%{meeting_date: %Date{} = date}) do
    %{meeting_date: date, meeting_date_source: :transcript}
  end

  defp stated_meeting_date(_no_date), do: %{}

  # Mechanical hygiene on the model's Subtask nesting, applied the moment the
  # Extraction finalises and never able to fail it: a self or dangling
  # reference is dropped, and a chain deeper than one level is flattened by
  # dropping the deeper parent reference — a node keeps its parent only when
  # that parent proposed none of its own (which also promotes both ends of a
  # cycle). The bias is deliberately against nesting: invented hierarchy is
  # this feature's failure mode, not missed hierarchy.
  defp sanitize_parent_refs(action_points) do
    count = length(action_points)
    indexed = Enum.with_index(action_points, 1)

    refs =
      Map.new(indexed, fn {attrs, position} ->
        {position, valid_parent_ref(Map.get(attrs, :parent), position, count)}
      end)

    Enum.map(indexed, fn {attrs, position} ->
      parent =
        case Map.fetch!(refs, position) do
          nil -> nil
          parent -> if Map.fetch!(refs, parent), do: nil, else: parent
        end

      Map.put(attrs, :parent, parent)
    end)
  end

  defp valid_parent_ref(parent, position, count)
       when is_integer(parent) and parent >= 1 and parent <= count and parent != position,
       do: parent

  defp valid_parent_ref(_parent, _position, _count), do: nil

  # Grounding Quotes are verified the moment the Extraction finalises: only
  # quotes that really appear in the normalised Transcript are stored, so a
  # hallucinated one never exists anywhere downstream (issue #24).
  defp verify_quotes(attrs, extraction) do
    quotes = GroundingQuote.verify(Map.get(attrs, :quotes, []), extraction.transcript_text)
    Map.put(attrs, :quotes, quotes)
  end

  # The Timing Quote gets the same mechanical check (issue #37), and dropping
  # it is deliberately independent of `resolve_due_date/2`: verification
  # governs the words, never the date, so a paraphrased quote costs the user
  # the words and nothing else.
  defp verify_timing_quote(attrs, extraction) do
    quote = TimingQuote.verify(Map.get(attrs, :timing_quote), extraction.transcript_text)
    Map.put(attrs, :timing_quote, quote)
  end

  # The Extraction's proposed Blockers, persisted as rows between the Action
  # Points just inserted. `Blocker.sanitise/1` has already made every surviving
  # edge insertable — nonsense proposals are dropped, never a failed Extraction.
  defp persist_blockers(action_points, ids_by_position) do
    action_points
    |> Enum.with_index(1)
    |> Enum.map(fn {attrs, position} -> {position, Map.get(attrs, :blocked_by, [])} end)
    |> Blocker.sanitise()
    |> Enum.each(fn {blocked, blocking} ->
      Repo.insert!(%Blocker{
        action_point_id: ids_by_position[blocked],
        blocked_by_id: ids_by_position[blocking]
      })
    end)
  end

  defp finalize_failure(extraction, reason) do
    extraction =
      update_extraction!(extraction, %{status: :failed, failure_reason: to_string(reason)})

    broadcast(extraction)
    extraction
  end

  defp update_extraction!(extraction, attrs) do
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
        where: ap.id == ^id and e.session_token == ^session_token,
        preload: [blockers: :blocked_by]
    )
  end

  @doc """
  Marks an Action Point accepted or rejected. Rejection is reversible — the
  row keeps everything except its standing in the Review — with one exception:
  its Blockers (in both directions) are removed outright, so no pushed issue
  can ever point at something that was never created. Accepting again does not
  resurrect them.

  Rejecting a parent also promotes its Subtasks to top level — a rule, not an
  option: curating the parent never orphans or discards the children's work.
  The promotion is not undone by re-accepting the parent, and since ADR-0009
  Review cannot re-nest by hand either. That costs the nesting, not the work:
  the children stay accepted and pushable with everything else intact, and the
  nesting is restored where nesting belongs — in the sink. Structure is never
  silently rebuilt.
  """
  def set_action_point_status(%ActionPoint{} = action_point, status)
      when status in [:accepted, :rejected] do
    {:ok, updated} =
      Repo.transaction(fn ->
        if status == :rejected do
          Repo.delete_all(
            from b in Blocker,
              where: b.action_point_id == ^action_point.id or b.blocked_by_id == ^action_point.id
          )

          promote_subtasks_of(action_point)
        end

        action_point
        |> Ecto.Changeset.change(status: status)
        |> Repo.update!()
      end)

    updated
  end

  defp promote_subtasks_of(%ActionPoint{id: id}) do
    Repo.update_all(
      from(ap in ActionPoint, where: ap.parent_id == ^id),
      set: [parent_id: nil, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )
  end

  @doc """
  Lifts a Subtask out of its parent to top level — undoing a nesting the
  Extraction proposed. The only direction Review moves an Action Point in:
  ADR-0009 leaves nesting to the meeting, so there is no inverse of this.

  A pushed Action Point is refused (`{:error, :pushed}`): its place in the
  Task Sink's hierarchy was created with it, so restructuring here would only
  make the Review lie about what Push did. One already at top level is left as
  it is — the card offers no such button, so only a stale screen asks.
  """
  def promote_action_point(%ActionPoint{sink_issue_id: id}) when not is_nil(id) do
    {:error, :pushed}
  end

  def promote_action_point(%ActionPoint{} = action_point) do
    {:ok,
     action_point
     |> Ecto.Changeset.change(parent_id: nil)
     |> Repo.update!()}
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
  Removes one Grounding Quote (by its position in the list) from an Action
  Point during Review — how an off-record remark is kept out of the Task
  Sink. Removal is the only curation quotes allow: an edited quote would no
  longer be evidence.
  """
  def remove_action_point_quote(%ActionPoint{} = action_point, index)
      when is_integer(index) and index >= 0 do
    action_point
    |> Ecto.Changeset.change(quotes: List.delete_at(action_point.quotes, index))
    |> Repo.update!()
  end

  @doc """
  Persists a resolved assignee onto an Action Point — from an Assignee
  Mapping hit, an unambiguous name-match suggestion, or the user's own pick
  or clear (ADR-0007). `sink_user` is `%{id:, name:}` from the live Task Sink
  member list, or `nil` for a deliberately unassigned pick. Never touches
  `assignee_guess`: it stays the model's raw output and the mapping key.

  Sets the fields directly rather than through a cast changeset — they are
  never user input, only ever this module's own resolved values.
  """
  def resolve_action_point_assignee(%ActionPoint{} = action_point, resolution, sink_user)
      when resolution in [:mapped, :suggested, :manual, :unassigned] do
    action_point
    |> Ecto.Changeset.change(
      assignee_resolution: resolution,
      assignee_sink_user_id: sink_user && sink_user.id,
      assignee_display_name: sink_user && sink_user.name
    )
    |> Repo.update!()
  end

  @doc """
  Applies the user's own assignee pick during Review — `sink_user` is
  `%{id:, name:}` from the live Task Sink member list, or `nil` to
  deliberately push this Action Point unassigned.
  """
  def set_action_point_assignee(%ActionPoint{} = action_point, nil) do
    resolve_action_point_assignee(action_point, :unassigned, nil)
  end

  def set_action_point_assignee(%ActionPoint{} = action_point, %{} = sink_user) do
    resolve_action_point_assignee(action_point, :manual, sink_user)
  end

  ## Blocker curation

  @doc """
  Fetches a Blocker only if its blocked Action Point's Extraction belongs to
  the given session token. Raises `Ecto.NoResultsError` otherwise, so a
  visitor can never curate another session's Review.
  """
  def get_blocker!(id, session_token) when is_binary(session_token) do
    Repo.one!(
      from b in Blocker,
        join: ap in assoc(b, :action_point),
        join: e in assoc(ap, :extraction),
        where: b.id == ^id and e.session_token == ^session_token
    )
  end

  @doc """
  Removes one Blocker during Review — one click, and a wrong guess costs
  nothing. The only curation Review does to relations: ADR-0009 leaves the
  drawing of edges to the meeting, so there is no inverse of this.
  """
  def remove_action_point_blocker(%Blocker{} = blocker) do
    Repo.delete!(blocker)
    :ok
  end

  @doc """
  Counts the Action Points a Push would create right now — accepted in the
  Review and not yet pushed. This is the number the Push button promises.
  """
  def count_pushable_action_points(extraction_id) do
    Repo.aggregate(pushable_query(extraction_id), :count)
  end

  @doc """
  Counts the Action Points rejected in this Review. Together with the total it
  gives the accepted tally the Review screen shows while curating; a pushed
  Action Point still counts as accepted.
  """
  def count_rejected_action_points(extraction_id) do
    Repo.aggregate(
      from(ap in ActionPoint,
        where: ap.extraction_id == ^extraction_id and ap.status == :rejected
      ),
      :count
    )
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

  Parents come before Subtasks, whatever their positions: a child is created
  carrying its parent's sink issue id, so the parent's must exist first.
  """
  def list_pushable_action_points(extraction_id) do
    Repo.all(
      from ap in pushable_query(extraction_id),
        order_by: [asc: fragment("? IS NOT NULL", ap.parent_id), asc: ap.position]
    )
  end

  @doc """
  The sink issue id recorded on an Action Point — nil while unpushed, or for
  an id that no longer exists. How a Push finds the parent issue a Subtask
  attaches to, including a parent created by an earlier, partially-failed
  attempt: retry reads the recorded id rather than re-deriving anything.
  """
  def get_action_point_sink_issue_id(action_point_id) do
    Repo.one(from ap in ActionPoint, where: ap.id == ^action_point_id, select: ap.sink_issue_id)
  end

  @doc """
  Orders a Review's Action Points for its indented one-level list: top-level
  Action Points by position, each followed immediately by its Subtasks in
  position order. Pure — feed it the preloaded, position-ordered list.
  """
  def order_for_review(action_points) do
    subtasks =
      action_points
      |> Enum.filter(& &1.parent_id)
      |> Enum.group_by(& &1.parent_id)

    action_points
    |> Enum.filter(&is_nil(&1.parent_id))
    |> Enum.flat_map(fn parent -> [parent | Map.get(subtasks, parent.id, [])] end)
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

  @doc """
  Lists the Blockers a Push still has to realise in the Task Sink: not yet
  created there, and with both ends already existing as sink issues. A retry
  after a partial Push therefore picks up exactly the missing edges — never a
  duplicate. Both Action Points come preloaded, carrying the sink issue ids
  the relation is created between.
  """
  def list_pushable_blockers(extraction_id) do
    Repo.all(
      from b in Blocker,
        join: blocked in assoc(b, :action_point),
        join: blocking in assoc(b, :blocked_by),
        where: blocked.extraction_id == ^extraction_id,
        where: is_nil(b.sink_relation_id),
        where: not is_nil(blocked.sink_issue_id) and not is_nil(blocking.sink_issue_id),
        order_by: [asc: b.id],
        preload: [action_point: blocked, blocked_by: blocking]
    )
  end

  @doc """
  Records the created-relation reference on a pushed Blocker — the moment the
  ordering the meeting stated becomes real in the Task Sink.
  """
  def record_relation_push!(%Blocker{} = blocker, %{id: id}) do
    blocker
    |> Ecto.Changeset.change(sink_relation_id: id)
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
