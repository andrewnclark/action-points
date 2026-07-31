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
  defp extract_with_blockers(blocked_by_lists) do
    extract_with_relations(Enum.map(blocked_by_lists, &%{blocked_by: &1}))
  end

  # The same, for the cases that also need the Extraction's proposed nesting:
  # one map of relation attrs (`:blocked_by`, `:parent`) per Action Point.
  defp extract_with_relations(relations) do
    action_points =
      @titles
      |> Enum.zip(relations)
      |> Enum.map(fn {title, attrs} -> Map.put(attrs, :title, title) end)

    stub_extractor({:ok, action_points})

    {:ok, extraction} =
      Meetings.create_extraction(nil, "session", %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    Meetings.get_extraction!(extraction.id, "session").action_points
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

    # Nesting is a dependency too — Review decides a Subtask before its parent
    # (ADR-0010) — so the hygiene has to look for a cycle across both kinds of
    # relation at once. Sanitising them separately leaves a loop the walk
    # cannot order.
    test "a Blocker from a parent down to its own Subtask is dropped as the cycle it closes" do
      [parent, child, _third] =
        extract_with_relations([
          %{},
          %{parent: 1, blocked_by: [1]},
          %{}
        ])

      assert blocker_titles(parent) == []
      assert blocker_titles(child) == []
      assert child.parent_id == parent.id
    end

    test "a cycle closed through the nesting by a longer Blocker chain is broken too" do
      # 1 is the parent of 3. Proposed: 2 waits on 1, 3 waits on 2. The second
      # edge closes the loop 1 → 2 → 3 → 1, because the parent already waits on
      # its own child.
      [_parent, second, child] =
        extract_with_relations([
          %{},
          %{blocked_by: [1]},
          %{parent: 1, blocked_by: [2]}
        ])

      assert blocker_titles(second) == ["Migrate the database"]
      assert blocker_titles(child) == []
    end

    test "a Blocker running the same way as the nesting survives" do
      # The parent waiting on its own child is what the nesting already says,
      # so stating it as a Blocker too closes nothing.
      [parent, _child, _third] =
        extract_with_relations([%{blocked_by: [2]}, %{parent: 1}, %{}])

      assert blocker_titles(parent) == ["Deploy the new service"]
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
