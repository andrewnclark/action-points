defmodule ActionPoints.Meetings.ActionPoint do
  @moduledoc """
  A task candidate produced by an Extraction — a proposal, not yet real; it
  becomes a task only when pushed to a Task Sink (see CONTEXT.md).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "action_points" do
    field :position, :integer
    field :title, :string
    field :description, :string
    field :assignee_guess, :string
    field :due_date, :date
    # The Review decision. `:undecided` is where every Action Point starts and
    # it is the reason strict decision means anything: without it, "I accepted
    # this" cannot be told from "I have not looked at it" (ADR-0010). It is a
    # starting state and not a destination — Review moves out of it and never
    # back, so `Meetings.set_action_point_status/2` accepts only the other two.
    field :status, Ecto.Enum, values: [:undecided, :accepted, :rejected], default: :undecided

    # Grounding Quotes: verbatim Transcript excerpts, verified when the
    # Extraction finalised. Removable at Review but never editable — an
    # edited quote is no longer evidence — so no curation cast touches this.
    field :quotes, {:array, :string}, default: []

    # The Timing Quote: the verbatim words the meeting used about when this is
    # due, verified the same way and kept as its own field — never folded into
    # the description, so Review can set it beside the due date and Push can
    # compose it without parsing prose. Independent of `due_date`: the quote
    # can survive with no date resolved, and a date survives a dropped quote.
    field :timing_quote, :string

    # The assignee guess resolved to a real Task Sink member (ADR-0007):
    # `assignee_resolution` is nil until Review has looked at this row once,
    # and stays whatever it settled on after that — a later Review reopening
    # never overwrites an explicit pick or an explicit clear. `:mapped` and
    # `:suggested` are set automatically from a mapping or an unambiguous
    # name match; `:manual` and `:unassigned` come from the user.
    field :assignee_sink_user_id, :string
    field :assignee_display_name, :string
    field :assignee_resolution, Ecto.Enum, values: [:mapped, :suggested, :manual, :unassigned]

    # The created-issue reference, set when this Action Point is pushed to the
    # Task Sink. Its presence is what makes a Push retry skip this row.
    field :sink_issue_id, :string
    field :sink_issue_identifier, :string
    field :sink_issue_url, :string

    belongs_to :extraction, ActionPoints.Meetings.Extraction

    # Blockers: the blocked-by relations this Action Point waits on, each
    # pointing at a sibling of the same Extraction and only ever a sibling.
    has_many :blockers, ActionPoints.Meetings.Blocker, preload_order: [asc: :id]

    # A Subtask's parent (see CONTEXT.md): another Action Point of the same
    # Extraction, exactly one level deep — set only when the meeting itself
    # broke the deliverable down aloud, and freely restructured at Review.
    # Orthogonal to Blockers by fiat: nesting carries no other semantics.
    belongs_to :parent, __MODULE__, foreign_key: :parent_id
    has_many :subtasks, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Whether a Push would create this Action Point right now: accepted in the
  Review and not yet pushed. Mirrors the query in `ActionPoints.Meetings`.

  Unchanged by `:undecided`, and that is the point: because it tests for
  `:accepted` rather than against `:rejected`, an Action Point nobody has
  looked at is not pushable and a half-finished walk Pushes nothing. The
  safety property arrives with the enum rather than with a new guard.
  """
  def pushable?(%__MODULE__{} = action_point) do
    action_point.status == :accepted and is_nil(action_point.sink_issue_id)
  end

  def changeset(action_point, attrs) do
    action_point
    |> cast(attrs, [:title, :description, :assignee_guess, :due_date, :quotes, :timing_quote])
    |> validate_required([:title])
  end

  @doc """
  Changeset for the user's edits during Review. Title stays required;
  description, assignee guess, and due date may all be cleared.
  """
  def curation_changeset(action_point, attrs) do
    action_point
    |> cast(attrs, [:title, :description, :assignee_guess, :due_date], force_changes: true)
    |> validate_required([:title])
  end
end
