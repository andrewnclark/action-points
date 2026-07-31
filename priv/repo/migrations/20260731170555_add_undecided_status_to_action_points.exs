defmodule ActionPoints.Repo.Migrations.AddUndecidedStatusToActionPoints do
  use Ecto.Migration

  # `:undecided` becomes the default, so Review can tell "I accepted this"
  # from "I have not looked at it" (ADR-0010).
  #
  # No backfill statement appears here and none was forgotten: the column has
  # been `null: false, default: "accepted"` since it was added, so every row
  # already written holds "accepted" — which is exactly what those rows meant
  # under the old semantics. Only the default moves.
  def change do
    alter table(:action_points) do
      modify :status, :string,
        null: false,
        default: "undecided",
        from: {:string, null: false, default: "accepted"}
    end
  end
end
