defmodule ActionPoints.Repo.Migrations.AddQuotesToActionPoints do
  use Ecto.Migration

  def change do
    alter table(:action_points) do
      add :quotes, {:array, :text}, null: false, default: []
    end
  end
end
