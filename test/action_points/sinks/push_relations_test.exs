defmodule ActionPoints.Sinks.PushRelationsTest do
  use ActionPoints.DataCase, async: false

  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.AccountsFixtures
  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.Blocker
  alias ActionPoints.Sinks
  alias ActionPoints.Sinks.FakeFlatTaskSink

  @api_key "lin_api_secret_key_abcd"
  @session_token "push-relations-session"

  @transcript """
  Priya: I'll migrate the database this week.
  Tom: Then I can deploy the new service once that's done.
  Sam: And I'll write the runbook after Tom deploys.
  """

  # A chain: deploy waits on migrate, runbook waits on deploy.
  @chained_action_points [
    %{title: "Migrate the database"},
    %{title: "Deploy the new service", blocked_by: [1]},
    %{title: "Write the runbook", blocked_by: [2]}
  ]

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_task_sink_pushes)
      Application.delete_env(:action_points, :fake_task_sink_relations)
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
  defp sink_relations, do: Application.get_env(:action_points, :fake_task_sink_relations, [])

  defp reload_blockers(extraction) do
    Meetings.get_extraction!(extraction.id, @session_token).action_points
    |> Enum.flat_map(& &1.blockers)
  end

  test "Push realises each Blocker as a blocked-by relation between the created issues", %{
    scope: scope
  } do
    extraction = create_review(@chained_action_points)

    assert {:ok, pushed} = Sinks.push(scope, extraction)
    assert length(pushed) == 3

    # Issue N is created for Action Point N in position order, so the edges
    # land exactly as the meeting stated them: 2 waits on 1, 3 waits on 2.
    assert sink_relations() == [
             %{blocked_issue_id: "issue-2", blocking_issue_id: "issue-1"},
             %{blocked_issue_id: "issue-3", blocking_issue_id: "issue-2"}
           ]

    assert reload_blockers(extraction) |> Enum.map(& &1.sink_relation_id) ==
             ["relation-1", "relation-2"]
  end

  test "a relation failure leaves every issue intact and is reported like a partial Push", %{
    scope: scope
  } do
    Application.put_env(:action_points, :fake_task_sink, relation: [:ok, {:error, :unavailable}])

    extraction = create_review(@chained_action_points)

    assert {:error, {:relations, :unavailable, 1, 1}} = Sinks.push(scope, extraction)

    # Issues are created before any relation is attempted, so all three exist.
    assert length(sink_pushes()) == 3
    assert [%{blocked_issue_id: "issue-2"}] = sink_relations()
  end

  test "a retry after a relation failure creates only the missing relations", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, relation: [:ok, {:error, :unavailable}])

    extraction = create_review(@chained_action_points)
    {:error, {:relations, :unavailable, 1, 1}} = Sinks.push(scope, extraction)

    assert {:ok, []} = Sinks.push(scope, extraction)

    # No issue and no relation was pushed twice.
    assert length(sink_pushes()) == 3

    assert [
             %{blocked_issue_id: "issue-2", blocking_issue_id: "issue-1"},
             %{blocked_issue_id: "issue-3", blocking_issue_id: "issue-2"}
           ] = sink_relations()

    assert reload_blockers(extraction) |> Enum.map(& &1.sink_relation_id) ==
             ["relation-1", "relation-2"]
  end

  test "an issue-phase failure attempts no relations; the retry completes both phases", %{
    scope: scope
  } do
    Application.put_env(:action_points, :fake_task_sink, push: [:ok, {:error, :unavailable}])

    extraction =
      create_review([
        %{title: "Migrate the database"},
        %{title: "Deploy the new service", blocked_by: [1]}
      ])

    assert {:error, {:unavailable, [_created], 1}} = Sinks.push(scope, extraction)
    assert sink_relations() == []

    assert {:ok, [retried]} = Sinks.push(scope, extraction)
    assert retried.title == "Deploy the new service"

    assert [%{blocked_issue_id: "issue-2", blocking_issue_id: "issue-1"}] = sink_relations()
  end

  test "relations removed by rejecting an Action Point are never pushed", %{scope: scope} do
    extraction =
      create_review([
        %{title: "Migrate the database"},
        %{title: "Deploy the new service", blocked_by: [1]}
      ])

    [first, _second] = extraction.action_points
    Meetings.set_action_point_status(first, :rejected)

    assert {:ok, [_pushed]} = Sinks.push(scope, extraction)
    assert sink_relations() == []
  end

  test "a sink that does not declare the relation capability drops them", %{scope: scope} do
    Application.put_env(:action_points, :task_sink, FakeFlatTaskSink)
    on_exit(fn -> Application.put_env(:action_points, :task_sink, Sinks.FakeTaskSink) end)

    refute Sinks.supports_relations?()

    extraction = create_review(@chained_action_points)

    assert {:ok, pushed} = Sinks.push(scope, extraction)
    assert length(pushed) == 3

    assert sink_relations() == []
    assert Repo.all(Blocker) |> Enum.map(& &1.sink_relation_id) == [nil, nil]
  end

  test "the shipped Task Sink fakes declare the capability" do
    assert Sinks.supports_relations?(Sinks.FakeTaskSink)
    assert Sinks.supports_relations?(Sinks.Linear)
  end
end
