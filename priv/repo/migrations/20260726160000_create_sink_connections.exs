defmodule ActionPoints.Repo.Migrations.CreateSinkConnections do
  use Ecto.Migration

  def change do
    create table(:sink_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sink, :string, null: false, default: "linear"
      add :api_key, :binary, null: false
      add :api_key_last4, :string
      add :team_id, :string, null: false
      add :team_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sink_connections, [:user_id])
  end
end
