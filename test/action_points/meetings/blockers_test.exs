defmodule ActionPoints.Meetings.BlockersTest do
  use ActionPoints.DataCase, async: false

  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.Blocker

  @transcript """
  Priya: I'll migrate the database this week.
  Tom: Then I can deploy the new service once that's done.
  Sam: And I'll write up the runbook, separately.
  """

  @titles ["Migrate the database", "Deploy the new service", "Write the runbook"]

  # Runs an Extraction whose three Action Points carry the given blocked_by
  # proposals (one list per position) and returns them as stored, in position
  # order, with their Blockers preloaded.
  defp extract_with_blockers(blocked_by_lists, session \\ "session") do
    action_points =
      @titles
      |> Enum.zip(blocked_by_lists)
      |> Enum.map(fn {title, blocked_by} -> %{title: title, blocked_by: blocked_by} end)

    stub_extractor({:ok, action_points})

    {:ok, extraction} =
      Meetings.create_extraction(nil, session, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    Meetings.get_extraction!(extraction.id, session).action_points
  end

  defp reload(action_point) do
    Meetings.get_extraction!(action_point.extraction_id, "session").action_points
    |> Enum.find(&(&1.id == action_point.id))
  end

  defp blocker_titles(action_point), do: Enum.map(action_point.blockers, & &1.blocked_by.title)

  describe "Blocker ingest at Extraction finalise" do
    test "a stated ordering is persisted as a blocked-by relation between siblings" do
      [first, second, third] = extract_with_blockers([[], [1], []])

      assert blocker_titles(first) == []
      assert blocker_titles(second) == ["Migrate the database"]
      assert blocker_titles(third) == []
    end

    test "an Action Point can be blocked by several siblings" do
      [_first, second, _third] = extract_with_blockers([[], [1, 3], []])

      assert blocker_titles(second) == ["Migrate the database", "Write the runbook"]
    end

    test "a self-reference is dropped and the Extraction still succeeds" do
      [first, _second, _third] = extract_with_blockers([[1], [], []])

      assert blocker_titles(first) == []
      assert Meetings.get_extraction!(first.extraction_id, "session").status == :succeeded
    end

    test "a reference to a position that does not exist is dropped" do
      [first, second, _third] = extract_with_blockers([[0], [4], []])

      assert blocker_titles(first) == []
      assert blocker_titles(second) == []
    end

    test "duplicate edges collapse to one relation" do
      [_first, second, _third] = extract_with_blockers([[], [1, 1], []])

      assert blocker_titles(second) == ["Migrate the database"]
    end

    test "a two-Action-Point cycle keeps the first edge and drops the one closing it" do
      [first, second, _third] = extract_with_blockers([[2], [1], []])

      assert blocker_titles(first) == ["Deploy the new service"]
      assert blocker_titles(second) == []
    end

    test "a longer cycle is broken at the edge that closes it" do
      # Proposed: 1 waits on 3, 2 waits on 1, 3 waits on 2 — the last edge
      # would close the circle, so only it is dropped.
      [first, second, third] = extract_with_blockers([[3], [1], [2]])

      assert blocker_titles(first) == ["Write the runbook"]
      assert blocker_titles(second) == ["Migrate the database"]
      assert blocker_titles(third) == []
    end

    test "a re-run Extraction replaces its relations rather than appending" do
      [_first, second, _third] = extract_with_blockers([[], [1], []])

      extraction = Meetings.get_extraction!(second.extraction_id, "session")
      Meetings.run_extraction(extraction)

      assert Repo.aggregate(Blocker, :count) == 1
    end
  end

  describe "rejecting an Action Point" do
    test "removes the relations pointing at it" do
      [first, second, _third] = extract_with_blockers([[], [1], []])

      Meetings.set_action_point_status(first, :rejected)

      assert blocker_titles(reload(second)) == []
      assert Repo.aggregate(Blocker, :count) == 0
    end

    test "removes its own relations" do
      [_first, second, _third] = extract_with_blockers([[], [1], []])

      Meetings.set_action_point_status(second, :rejected)

      assert Repo.aggregate(Blocker, :count) == 0
    end

    test "accepting again does not resurrect the removed relations" do
      [first, second, _third] = extract_with_blockers([[], [1], []])

      Meetings.set_action_point_status(first, :rejected)
      Meetings.set_action_point_status(first, :accepted)

      assert blocker_titles(reload(second)) == []
    end
  end

  describe "Review curation of Blockers" do
    test "add_action_point_blocker links two of the Extraction's Action Points" do
      [first, _second, third] = extract_with_blockers([[], [], []])

      assert {:ok, %Blocker{}} = Meetings.add_action_point_blocker(third, first)
      assert blocker_titles(reload(third)) == ["Migrate the database"]
    end

    test "refuses a self-reference" do
      [first, _second, _third] = extract_with_blockers([[], [], []])

      assert {:error, :self_reference} = Meetings.add_action_point_blocker(first, first)
    end

    test "refuses a duplicate relation" do
      [first, second, _third] = extract_with_blockers([[], [1], []])

      assert {:error, :duplicate} = Meetings.add_action_point_blocker(second, first)
    end

    test "refuses an edge that would close a cycle" do
      [first, _second, third] = extract_with_blockers([[], [1], [2]])

      assert {:error, :cycle} = Meetings.add_action_point_blocker(first, third)
    end

    test "refuses to link Action Points of different Extractions" do
      [first, _second, _third] = extract_with_blockers([[], [], []])
      [other, _, _] = extract_with_blockers([[], [], []], "other-session")

      assert {:error, :cross_extraction} = Meetings.add_action_point_blocker(first, other)
    end

    test "refuses a relation touching a rejected Action Point" do
      [first, second, third] = extract_with_blockers([[], [], []])
      Meetings.set_action_point_status(first, :rejected)

      assert {:error, :rejected} = Meetings.add_action_point_blocker(second, first)
      assert {:error, :rejected} = Meetings.add_action_point_blocker(reload(first), third)
    end

    test "remove_action_point_blocker deletes exactly that relation" do
      [_first, second, _third] = extract_with_blockers([[], [1, 3], []])
      [blocker, keeper] = reload(second).blockers

      Meetings.remove_action_point_blocker(blocker)

      assert Enum.map(reload(second).blockers, & &1.id) == [keeper.id]
    end

    test "get_blocker!/2 raises for another session, so no one curates another visitor's Review" do
      [_first, second, _third] = extract_with_blockers([[], [1], []])
      [blocker] = second.blockers

      assert Meetings.get_blocker!(blocker.id, "session").id == blocker.id

      assert_raise Ecto.NoResultsError, fn ->
        Meetings.get_blocker!(blocker.id, "other-session")
      end
    end
  end
end
