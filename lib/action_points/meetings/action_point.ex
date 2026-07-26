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
    field :status, Ecto.Enum, values: [:accepted, :rejected], default: :accepted

    belongs_to :extraction, ActionPoints.Meetings.Extraction

    timestamps(type: :utc_datetime)
  end

  def changeset(action_point, attrs) do
    action_point
    |> cast(attrs, [:title, :description, :assignee_guess, :due_date])
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
