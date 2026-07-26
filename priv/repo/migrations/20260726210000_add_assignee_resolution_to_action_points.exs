defmodule ActionPoints.Repo.Migrations.AddAssigneeResolutionToActionPoints do
  use Ecto.Migration

  def change do
    alter table(:action_points) do
      add :assignee_sink_user_id, :string
      add :assignee_display_name, :string
      add :assignee_resolution, :string
    end
  end
end
