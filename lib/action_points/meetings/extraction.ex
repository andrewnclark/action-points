defmodule ActionPoints.Meetings.Extraction do
  @moduledoc """
  A single run of the model over one Transcript. It either succeeds — producing
  Action Points — or fails as a whole (see CONTEXT.md).

  Keyed to the anonymous visitor's session token; `user_id` is claimed at
  signup so the visitor's Extraction survives registration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "extractions" do
    field :session_token, :string
    field :transcript_text, :string
    field :status, Ecto.Enum, values: [:pending, :running, :succeeded, :failed], default: :pending
    field :failure_reason, :string

    belongs_to :user, ActionPoints.Accounts.User
    has_many :action_points, ActionPoints.Meetings.ActionPoint, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  def changeset(extraction, attrs) do
    extraction
    |> cast(attrs, [:transcript_text])
    |> validate_required([:transcript_text])
  end
end
