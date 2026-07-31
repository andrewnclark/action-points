defmodule ActionPoints.Meetings.WalkTest do
  @moduledoc """
  What Review's walk stands on: the undecided starting state, and the walk
  position as a query over rows rather than progress anybody kept (ADR-0010).
  """

  use ActionPoints.DataCase, async: false

  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.ActionPoint

  @session_token "walk-session"

  @transcript """
  Priya: I'll migrate the database this week.
  Tom: Then I can deploy the new service once that's done.
  Sam: And the runbook — Alice writes the rollback section.
  """

  # Runs an Extraction over the given Action Point attrs (each may carry
  # :parent and :blocked_by references by 1-based position) and returns the
  # Extraction id.
  defp extract(attrs_list) do
    stub_extractor({:ok, attrs_list})

    {:ok, extraction} =
      Meetings.create_extraction(nil, @session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    extraction.id
  end

  defp action_points(extraction_id) do
    Meetings.get_extraction!(extraction_id, @session_token).action_points
  end

  defp titles_in_walk_order(extraction_id) do
    extraction_id
    |> Meetings.list_action_points_in_dependency_order()
    |> Enum.map(& &1.title)
  end

  defp find(extraction_id, title) do
    Enum.find(action_points(extraction_id), &(&1.title == title))
  end

  describe "a new Extraction" do
    test "leaves every Action Point undecided" do
      extraction_id = extract([%{title: "Migrate the database"}, %{title: "Deploy the service"}])

      assert Enum.map(action_points(extraction_id), & &1.status) == [:undecided, :undecided]
    end

    test "has nothing to Push, because nobody has decided anything" do
      extraction_id = extract([%{title: "Migrate the database"}, %{title: "Deploy the service"}])

      assert Meetings.count_pushable_action_points(extraction_id) == 0
      refute Enum.any?(action_points(extraction_id), &ActionPoint.pushable?/1)
    end

    test "counts an undecided Action Point as neither accepted nor rejected" do
      extraction_id = extract([%{title: "Migrate the database"}])

      assert Meetings.count_rejected_action_points(extraction_id) == 0
      assert Meetings.count_pushable_action_points(extraction_id) == 0
    end
  end

  describe "an accepted Action Point" do
    test "becomes pushable, and an undecided sibling does not" do
      extraction_id = extract([%{title: "Migrate the database"}, %{title: "Deploy the service"}])

      accepted =
        extraction_id
        |> find("Migrate the database")
        |> Meetings.set_action_point_status(:accepted)

      assert ActionPoint.pushable?(accepted)
      assert Meetings.count_pushable_action_points(extraction_id) == 1
    end
  end

  describe "the walk order" do
    test "is position order when the Extraction proposed no relations" do
      extraction_id =
        extract([
          %{title: "Migrate the database"},
          %{title: "Deploy the service"},
          %{title: "Write the runbook"}
        ])

      assert titles_in_walk_order(extraction_id) == [
               "Migrate the database",
               "Deploy the service",
               "Write the runbook"
             ]
    end

    test "puts what an Action Point is blocked by before it" do
      extraction_id =
        extract([
          %{title: "Deploy the service", blocked_by: [2]},
          %{title: "Migrate the database"}
        ])

      assert titles_in_walk_order(extraction_id) == [
               "Migrate the database",
               "Deploy the service"
             ]
    end

    test "exists for a nesting and a Blocker that between them would close a loop" do
      # The model proposing both "the notes are part of the release" and "the
      # notes wait on the release" describes a circle. The finalise-time
      # hygiene drops the Blocker (see BlockersTest), and what reaches the walk
      # is orderable — this is the end-to-end guard on that.
      extraction_id =
        extract([
          %{title: "Ship the release"},
          %{title: "Write the release notes", parent: 1, blocked_by: [1]}
        ])

      assert titles_in_walk_order(extraction_id) == [
               "Write the release notes",
               "Ship the release"
             ]
    end

    test "puts a Subtask before its parent" do
      extraction_id =
        extract([
          %{title: "Write the runbook"},
          %{title: "Write the rollback section", parent: 1}
        ])

      assert titles_in_walk_order(extraction_id) == [
               "Write the rollback section",
               "Write the runbook"
             ]
    end
  end

  describe "the walk position" do
    setup do
      extraction_id =
        extract([
          %{title: "Deploy the service", blocked_by: [2]},
          %{title: "Migrate the database"},
          %{title: "Write the runbook"}
        ])

      %{extraction_id: extraction_id}
    end

    test "starts on the first Action Point in dependency order", %{extraction_id: id} do
      assert Meetings.next_undecided_action_point(id).title == "Migrate the database"
    end

    test "moves on as decisions are written, whichever way they went", %{extraction_id: id} do
      id |> find("Migrate the database") |> Meetings.set_action_point_status(:accepted)
      assert Meetings.next_undecided_action_point(id).title == "Deploy the service"

      id |> find("Deploy the service") |> Meetings.set_action_point_status(:rejected)
      assert Meetings.next_undecided_action_point(id).title == "Write the runbook"
    end

    test "is nil once every Action Point has been decided", %{extraction_id: id} do
      for action_point <- action_points(id) do
        Meetings.set_action_point_status(action_point, :accepted)
      end

      assert Meetings.next_undecided_action_point(id) == nil
    end

    test "is derived from the rows, so nothing has to be remembered", %{extraction_id: id} do
      id |> find("Migrate the database") |> Meetings.set_action_point_status(:accepted)

      # Nothing here carries over from the call above but the database — which
      # is exactly what a closed tab, a crash, or a deploy leaves behind.
      assert Meetings.next_undecided_action_point(id).title == "Deploy the service"
      assert Meetings.next_undecided_action_point(id).title == "Deploy the service"
    end
  end
end
