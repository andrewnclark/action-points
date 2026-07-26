defmodule ActionPoints.Sinks.SinkConnection do
  @moduledoc """
  A user's connection to their Task Sink: which sink (Linear only at launch),
  the API key encrypted at rest, and the team pushed issues land in.
  One connection per user.

  `api_key_last4` exists so the UI can show a masked key without ever
  rendering the full one.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "sink_connections" do
    field :sink, :string, default: "linear"
    field :api_key, ActionPoints.Vault.EncryptedBinary, redact: true
    field :api_key_last4, :string
    field :team_id, :string
    field :team_name, :string

    belongs_to :user, ActionPoints.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:api_key, :team_id, :team_name])
    |> validate_required([:api_key, :team_id, :team_name])
    |> put_api_key_last4()
    |> unique_constraint(:user_id)
  end

  defp put_api_key_last4(changeset) do
    case get_change(changeset, :api_key) do
      nil -> changeset
      api_key -> put_change(changeset, :api_key_last4, String.slice(api_key, -4, 4))
    end
  end
end
