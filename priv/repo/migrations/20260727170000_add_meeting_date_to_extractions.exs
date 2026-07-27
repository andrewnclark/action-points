defmodule ActionPoints.Repo.Migrations.AddMeetingDateToExtractions do
  use Ecto.Migration

  def up do
    alter table(:extractions) do
      add :meeting_date, :date
      add :meeting_date_source, :string
    end

    # Pre-existing Extractions never knew their meeting date; the day they ran
    # is exactly what the `assumed` source means.
    execute """
    UPDATE extractions
    SET meeting_date = inserted_at::date, meeting_date_source = 'assumed'
    """

    alter table(:extractions) do
      modify :meeting_date, :date, null: false
      modify :meeting_date_source, :string, null: false
    end
  end

  def down do
    alter table(:extractions) do
      remove :meeting_date
      remove :meeting_date_source
    end
  end
end
