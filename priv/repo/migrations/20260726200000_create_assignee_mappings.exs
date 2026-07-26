defmodule ActionPoints.Repo.Migrations.CreateAssigneeMappings do
  use Ecto.Migration

  def change do
    create table(:assignee_mappings) do
      add :sink_connection_id, references(:sink_connections, on_delete: :delete_all), null: false
      add :normalized_guess, :string, null: false
      add :sink_user_id, :string, null: false
      add :display_name, :string, null: false
      add :handle, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assignee_mappings, [:sink_connection_id, :normalized_guess])
  end
end
