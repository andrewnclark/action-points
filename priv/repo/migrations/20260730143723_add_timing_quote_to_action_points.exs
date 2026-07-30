defmodule ActionPoints.Repo.Migrations.AddTimingQuoteToActionPoints do
  use Ecto.Migration

  def change do
    alter table(:action_points) do
      add :timing_quote, :text
    end
  end
end
