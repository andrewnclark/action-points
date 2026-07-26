defmodule ActionPoints.Repo.Migrations.CreateExtractionsAndActionPoints do
  use Ecto.Migration

  def change do
    create table(:extractions) do
      add :session_token, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :transcript_text, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :failure_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:extractions, [:session_token])
    create index(:extractions, [:user_id])

    create table(:action_points) do
      add :extraction_id, references(:extractions, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :title, :string, null: false
      add :description, :text
      add :assignee_guess, :string
      add :due_date, :date

      timestamps(type: :utc_datetime)
    end

    create index(:action_points, [:extraction_id])
  end
end
