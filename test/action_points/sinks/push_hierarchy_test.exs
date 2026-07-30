defmodule ActionPoints.Sinks.PushHierarchyTest do
  use ActionPoints.DataCase, async: false

  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.AccountsFixtures
  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @api_key "lin_api_secret_key_abcd"
  @session_token "push-hierarchy-session"

  @transcript """
  Priya: The onboarding revamp — Alice takes the copy, Bob the new flow.
  Tom: I'll book the venue for the offsite too.
  """

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_task_sink_pushes)
      Application.delete_env(:action_points, :fake_extractor_result)
    end)

    user = AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)

    {:ok, _connection} =
      Sinks.connect(scope, %{
        "api_key" => @api_key,
        "team_id" => "team-1",
        "team_name" => "Engineering"
      })

    %{scope: scope}
  end

  defp create_review(action_points) do
    stub_extractor({:ok, action_points})

    {:ok, extraction} =
      Meetings.create_extraction(nil, @session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    Meetings.get_extraction!(extraction.id, @session_token)
  end

  defp sink_pushes, do: Application.get_env(:action_points, :fake_task_sink_pushes, [])

  test "parents are created first and each Subtask carries its parent's sink issue id",
       %{scope: scope} do
    # The child is listed — and positioned — before its parent, so ordering
    # by position alone would push it first.
    extraction =
      create_review([
        %{title: "Rewrite the onboarding copy", parent: 2},
        %{title: "Revamp onboarding"}
      ])

    assert {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [
             {_, %{title: "Revamp onboarding", parent_id: nil}},
             {_, %{title: "Rewrite the onboarding copy", parent_id: "issue-1"}}
           ] = sink_pushes()
  end

  test "a top-level Action Point pushes with no parent id", %{scope: scope} do
    extraction = create_review([%{title: "Book the offsite venue"}])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{parent_id: nil}}] = sink_pushes()
  end

  test "retry attaches a late Subtask to the parent created in the first attempt",
       %{scope: scope} do
    # First attempt: the parent is created, then the sink goes down before
    # the child.
    Application.put_env(:action_points, :fake_task_sink, push: [:ok, {:error, :unavailable}])

    extraction =
      create_review([
        %{title: "Revamp onboarding"},
        %{title: "Rewrite the onboarding copy", parent: 1}
      ])

    assert {:error, {:unavailable, [parent], 1}} = Sinks.push(scope, extraction)
    assert parent.title == "Revamp onboarding"

    # Retry: only the child is left, and it attaches to the recorded parent —
    # never a detached duplicate.
    assert {:ok, [child]} = Sinks.push(scope, extraction)
    assert child.title == "Rewrite the onboarding copy"

    assert [
             {_, %{title: "Revamp onboarding"}},
             {_, %{title: "Rewrite the onboarding copy", parent_id: "issue-1"}}
           ] = sink_pushes()
  end

  test "a sink without the hierarchy capability gets ordinary top-level tasks",
       %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, supports_hierarchy: false)

    extraction =
      create_review([
        %{title: "Revamp onboarding"},
        %{title: "Rewrite the onboarding copy", parent: 1}
      ])

    assert {:ok, pushed} = Sinks.push(scope, extraction)
    assert length(pushed) == 2

    assert [
             {_, %{title: "Revamp onboarding", parent_id: nil}},
             {_, %{title: "Rewrite the onboarding copy", parent_id: nil}}
           ] = sink_pushes()
  end

  test "a Subtask keeps its own assignee and due date in the pushed task", %{scope: scope} do
    extraction =
      create_review([
        %{title: "Revamp onboarding"},
        %{
          title: "Rewrite the onboarding copy",
          parent: 1,
          due_date: ~D[2026-08-14]
        }
      ])

    [_parent, child] = extraction.action_points
    Meetings.set_action_point_assignee(child, %{id: "u-alice", name: "Alice Wong"})

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [
             _parent_task,
             {_, %{parent_id: "issue-1", assignee_id: "u-alice", due_date: ~D[2026-08-14]}}
           ] = sink_pushes()
  end
end
