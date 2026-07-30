defmodule ActionPoints.Meetings.SubtasksTest do
  use ActionPoints.DataCase, async: false

  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Meetings

  @session_token "subtasks-session"

  @transcript """
  Priya: The onboarding revamp — Alice takes the copy, Bob the new flow.
  Tom: I'll book the venue for the offsite too.
  """

  # Runs an Extraction over the given Action Point attrs (each may carry a
  # :parent reference by 1-based position) and returns the stored Action
  # Points in position order.
  defp extract(attrs_list) do
    stub_extractor({:ok, attrs_list})

    {:ok, extraction} =
      Meetings.create_extraction(nil, @session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    Meetings.get_extraction!(extraction.id, @session_token).action_points
  end

  defp ap(title, extra \\ %{}), do: Map.merge(%{title: title}, extra)

  describe "nesting ingest at Extraction finalise" do
    test "a parent reference by position becomes the sibling's parent_id" do
      [parent, child, other] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{parent: 1}),
          ap("Book the offsite venue")
        ])

      assert child.parent_id == parent.id
      assert parent.parent_id == nil
      assert other.parent_id == nil
    end

    test "a child listed before its parent still resolves" do
      [child, parent] =
        extract([
          ap("Rewrite the onboarding copy", %{parent: 2}),
          ap("Revamp onboarding")
        ])

      assert child.parent_id == parent.id
    end

    test "a Subtask keeps its own assignee, due date, and quotes" do
      [_parent, child] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{
            parent: 1,
            assignee_guess: "Alice",
            due_date: ~D[2026-08-14],
            quotes: ["Alice takes the copy, Bob the new flow."]
          })
        ])

      assert child.assignee_guess == "Alice"
      assert child.due_date == ~D[2026-08-14]
      assert child.quotes == ["Alice takes the copy, Bob the new flow."]
    end
  end

  describe "reference hygiene at Extraction finalise" do
    test "a self reference is dropped" do
      [only] = extract([ap("Revamp onboarding", %{parent: 1})])

      assert only.parent_id == nil
    end

    test "a dangling reference is dropped" do
      [first, second] =
        extract([
          ap("Revamp onboarding", %{parent: 99}),
          ap("Rewrite the onboarding copy", %{parent: 0})
        ])

      assert first.parent_id == nil
      assert second.parent_id == nil
    end

    test "a chain deeper than one level is flattened by dropping the deeper reference" do
      [top, middle, deep] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{parent: 1}),
          ap("Draft the welcome email", %{parent: 2})
        ])

      assert middle.parent_id == top.id
      assert deep.parent_id == nil
    end

    test "a two-node cycle promotes both" do
      [first, second] =
        extract([
          ap("Revamp onboarding", %{parent: 2}),
          ap("Rewrite the onboarding copy", %{parent: 1})
        ])

      assert first.parent_id == nil
      assert second.parent_id == nil
    end

    test "hygiene never fails the Extraction" do
      [_bad_refs] = extract([ap("Revamp onboarding", %{parent: 1})])

      extraction =
        ActionPoints.Repo.get_by!(ActionPoints.Meetings.Extraction,
          session_token: @session_token
        )

      assert extraction.status == :succeeded
    end
  end

  describe "rejecting a parent" do
    test "promotes its Subtasks rather than orphaning them" do
      [parent, _child_one, _child_two] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{parent: 1}),
          ap("Build the new flow", %{parent: 1})
        ])

      Meetings.set_action_point_status(parent, :rejected)

      [parent, child_one, child_two] =
        Meetings.get_extraction!(parent.extraction_id, @session_token).action_points

      assert parent.status == :rejected
      assert child_one.parent_id == nil
      assert child_two.parent_id == nil
      assert child_one.status == :accepted
      assert child_two.status == :accepted
    end

    test "un-rejecting the parent does not re-nest the promoted children" do
      [parent, _child] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{parent: 1})
        ])

      parent = Meetings.set_action_point_status(parent, :rejected)
      Meetings.set_action_point_status(parent, :accepted)

      [_parent, child] =
        Meetings.get_extraction!(parent.extraction_id, @session_token).action_points

      assert child.parent_id == nil
    end

    test "rejecting a childless Action Point stays a plain status change" do
      [first, second] = extract([ap("Revamp onboarding"), ap("Book the offsite venue")])

      rejected = Meetings.set_action_point_status(second, :rejected)

      assert rejected.status == :rejected
      assert Meetings.get_action_point!(first.id, @session_token).status == :accepted
    end
  end

  describe "set_action_point_parent/2" do
    test "nests a top-level Action Point under another of the meeting's Action Points" do
      [parent, loose] = extract([ap("Revamp onboarding"), ap("Rewrite the onboarding copy")])

      assert {:ok, nested} = Meetings.set_action_point_parent(loose, parent)
      assert nested.parent_id == parent.id
    end

    test "promotes a Subtask when the parent is cleared" do
      [_parent, child] =
        extract([ap("Revamp onboarding"), ap("Rewrite the onboarding copy", %{parent: 1})])

      assert {:ok, promoted} = Meetings.set_action_point_parent(child, nil)
      assert promoted.parent_id == nil
    end

    test "nesting an Action Point that has children promotes them — never deeper than one level" do
      [parent, child, new_top] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{parent: 1}),
          ap("Ship the Q3 launch")
        ])

      assert {:ok, nested} = Meetings.set_action_point_parent(parent, new_top)
      assert nested.parent_id == new_top.id

      assert Meetings.get_action_point!(child.id, @session_token).parent_id == nil
    end

    test "refuses itself as parent" do
      [only] = extract([ap("Revamp onboarding")])

      assert {:error, :invalid_parent} = Meetings.set_action_point_parent(only, only)
    end

    test "refuses a parent that is itself a Subtask" do
      [_top, child, loose] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{parent: 1}),
          ap("Book the offsite venue")
        ])

      assert {:error, :invalid_parent} = Meetings.set_action_point_parent(loose, child)
    end

    test "refuses restructuring a pushed Action Point — its sink hierarchy already exists" do
      [parent, child] =
        extract([ap("Revamp onboarding"), ap("Rewrite the onboarding copy", %{parent: 1})])

      pushed =
        Meetings.record_push!(child, %{
          id: "issue-1",
          identifier: "ENG-1",
          url: "https://linear.app/fake/issue/ENG-1"
        })

      assert {:error, :pushed} = Meetings.set_action_point_parent(pushed, nil)
      assert {:error, :pushed} = Meetings.set_action_point_parent(pushed, parent)
      assert Meetings.get_action_point!(child.id, @session_token).parent_id == parent.id
    end

    test "refuses a parent from another Extraction" do
      [foreign] = extract([ap("Book the offsite venue")])

      stub_extractor({:ok, [ap("Revamp onboarding")]})

      {:ok, extraction} =
        Meetings.create_extraction(nil, "other-session", %{"transcript_text" => @transcript})

      Meetings.run_extraction(extraction)
      [own] = Meetings.get_extraction!(extraction.id, "other-session").action_points

      assert {:error, :invalid_parent} = Meetings.set_action_point_parent(own, foreign)
    end
  end

  describe "Blockers-orthogonality guardrail" do
    # Subtasks add no hidden semantics: nesting must not change what a
    # Review counts as pushable.
    test "nesting leaves the pushable count untouched" do
      [parent | _] =
        extract([
          ap("Revamp onboarding"),
          ap("Rewrite the onboarding copy", %{parent: 1})
        ])

      assert Meetings.count_pushable_action_points(parent.extraction_id) == 2
    end
  end
end
