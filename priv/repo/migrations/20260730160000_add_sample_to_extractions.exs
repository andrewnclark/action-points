defmodule ActionPoints.Repo.Migrations.AddSampleToExtractions do
  use Ecto.Migration

  def change do
    alter table(:extractions) do
      add :sample, :boolean, null: false, default: false
    end
  end
end
