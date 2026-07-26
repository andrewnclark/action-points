defmodule ActionPoints.Repo.Migrations.AddStatusToActionPoints do
  use Ecto.Migration

  def change do
    alter table(:action_points) do
      add :status, :string, null: false, default: "accepted"
    end
  end
end
