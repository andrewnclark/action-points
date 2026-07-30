defmodule ActionPoints.Sinks.AssigneeMapping do
  @moduledoc """
  A remembered link from a guessed name to one Task Sink member, scoped to a
  Sink Connection (see CONTEXT.md, ADR-0007). `display_name` and `handle` are
  cached at the moment the mapping is written so the Sink Settings screen can
  list mappings without a round-trip to the sink.

  Many guessed names may map to the same member; one name maps to at most one
  member per connection — enforced by the unique index on
  `(sink_connection_id, normalized_guess)`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "assignee_mappings" do
    field :normalized_guess, :string
    field :sink_user_id, :string
    field :display_name, :string
    field :handle, :string

    belongs_to :sink_connection, ActionPoints.Sinks.SinkConnection

    timestamps(type: :utc_datetime)
  end

  @doc """
  Folds a name for comparison: trimmed and lower-cased. The one fold, wherever
  a name is compared — the mapping's lookup key, and both sides of the Task
  Sink member name match.

  Growing it (collapsing internal whitespace, folding accents) moves those
  paths together, which is the point of it living here. Resolution is one
  decision, and half of it folding differently would just make a guess match
  on one path and silently never on the other.
  """
  def normalize(name) when is_binary(name), do: name |> String.trim() |> String.downcase()

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:normalized_guess, :sink_user_id, :display_name, :handle])
    |> validate_required([:normalized_guess, :sink_user_id, :display_name])
    |> unique_constraint([:sink_connection_id, :normalized_guess])
  end
end
