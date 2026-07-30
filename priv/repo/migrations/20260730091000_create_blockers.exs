defmodule ActionPoints.Repo.Migrations.CreateBlockers do
  use Ecto.Migration

  def change do
    create table(:blockers) do
      add :action_point_id, references(:action_points, on_delete: :delete_all), null: false
      add :blocked_by_id, references(:action_points, on_delete: :delete_all), null: false
      add :sink_relation_id, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:blockers, [:action_point_id, :blocked_by_id])
    create index(:blockers, [:blocked_by_id])
  end
end
