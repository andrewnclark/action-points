defmodule ActionPoints.Repo.Migrations.NameTheSinkMemberOnActionPoints do
  use Ecto.Migration

  # An assignee is two facts: the Named Person the meeting said, and the Sink
  # Member they are in the Task Sink (CONTEXT.md, ADR-0010). The columns now
  # name the second one. `assignee_display_name` read as "the name to display
  # in the assignee slot" — singular, and that is what let the Named Person be
  # dropped from the picker branch without anyone noticing.
  #
  # `sink_member_handle` is new: the step shows the handle, and the live member
  # list it would otherwise be read from is unavailable on a later visit —
  # which for a pushed Action Point is the only visit left.
  #
  # Deliberately not backfilled. The handle is only knowable from the member
  # list at the moment of resolution, and resolution never reruns on a row
  # that has one (Sinks.resolve_assignees/2 skips it), so rows resolved before
  # today keep a nil handle for good and render their Sink Member by name.
  def change do
    rename table(:action_points), :assignee_sink_user_id, to: :sink_member_id
    rename table(:action_points), :assignee_display_name, to: :sink_member_name

    alter table(:action_points) do
      add :sink_member_handle, :string
    end
  end
end
