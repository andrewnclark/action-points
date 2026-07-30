defmodule ActionPoints.Repo.Migrations.AddParentToActionPoints do
  use Ecto.Migration

  def change do
    alter table(:action_points) do
      # A Subtask's parent: another Action Point of the same Extraction,
      # exactly one level deep. Nilify so deleting a parent can never take
      # its children's rows with it.
      add :parent_id, references(:action_points, on_delete: :nilify_all)
    end

    create index(:action_points, [:parent_id])
  end
end
