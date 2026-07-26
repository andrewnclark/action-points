defmodule ActionPoints.Repo.Migrations.AddSinkIssueRefsToActionPoints do
  use Ecto.Migration

  def change do
    alter table(:action_points) do
      add :sink_issue_id, :string
      add :sink_issue_identifier, :string
      add :sink_issue_url, :string
    end
  end
end
