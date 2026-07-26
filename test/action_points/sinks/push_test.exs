defmodule ActionPoints.Sinks.PushTest do
  use ActionPoints.DataCase, async: false

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.AccountsFixtures
  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @api_key "lin_api_secret_key_abcd"
  @session_token "push-test-session"

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  @two_action_points [
    %{
      title: "Send the Q3 report to finance",
      description: "Priya committed to sending the Q3 report to finance.",
      assignee_guess: "Priya",
      due_date: ~D[2026-07-31]
    },
    %{
      title: "Book the offsite venue",
      description: "Tom will book the venue for the offsite.",
      assignee_guess: "Tom",
      due_date: nil
    }
  ]

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
        "team_id" => "team-2",
        "team_name" => "Design"
      })

    %{scope: scope}
  end

  # Creates a succeeded Extraction whose Review the tests push from.
  defp create_review(action_points) do
    Application.put_env(:action_points, :fake_extractor_result, {:ok, action_points})

    {:ok, extraction} =
      Meetings.create_extraction(nil, @session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    Meetings.get_extraction!(extraction.id, @session_token)
  end

  defp reload_action_points(extraction) do
    Meetings.get_extraction!(extraction.id, @session_token).action_points
  end

  defp sink_pushes, do: Application.get_env(:action_points, :fake_task_sink_pushes, [])

  test "creates one sink task per accepted Action Point in the connected team", %{scope: scope} do
    extraction = create_review(@two_action_points)

    assert {:ok, pushed} = Sinks.push(scope, extraction)
    assert length(pushed) == 2

    assert [
             {"team-2", %{title: "Send the Q3 report to finance", due_date: ~D[2026-07-31]}},
             {"team-2", %{title: "Book the offsite venue", due_date: nil}}
           ] = sink_pushes()
  end

  test "matches assignee guesses to sink users by full name or unique first name", %{
    scope: scope
  } do
    Application.put_env(:action_points, :fake_task_sink,
      users:
        {:ok,
         [
           %{id: "u-priya", name: "Priya Sharma"},
           %{id: "u-tom", name: "Tom Nook"},
           %{id: "u-tomas", name: "Tomas Riley"}
         ]}
    )

    extraction = create_review(@two_action_points)

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [
             {_team1, %{title: "Send the Q3 report to finance", assignee_id: "u-priya"}},
             {_team2, %{title: "Book the offsite venue", assignee_id: "u-tom"}}
           ] = sink_pushes()
  end

  test "an ambiguous or unmatched guess is left unassigned, never mis-assigned", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-tom-n", name: "Tom Nook"}, %{id: "u-tom-c", name: "Tom Chen"}]}
    )

    extraction =
      create_review([
        %{title: "Book the offsite venue", assignee_guess: "Tom"},
        %{title: "Send the Q3 report to finance", assignee_guess: "Priya"},
        %{title: "Circulate the meeting notes", assignee_guess: nil}
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [
             {_, %{assignee_id: nil}},
             {_, %{assignee_id: nil}},
             {_, %{assignee_id: nil}}
           ] = sink_pushes()
  end

  test "when the sink's user list is unavailable, everything pushes unassigned", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, users: {:error, :unavailable})

    extraction = create_review(@two_action_points)

    assert {:ok, pushed} = Sinks.push(scope, extraction)
    assert length(pushed) == 2
    assert [{_, %{assignee_id: nil}}, {_, %{assignee_id: nil}}] = sink_pushes()
  end

  test "rejected Action Points are never pushed", %{scope: scope} do
    extraction = create_review(@two_action_points)
    [first, _second] = extraction.action_points
    Meetings.set_action_point_status(first, :rejected)

    assert {:ok, [_pushed]} = Sinks.push(scope, extraction)

    assert [{_, %{title: "Book the offsite venue"}}] = sink_pushes()
    [rejected, _] = reload_action_points(extraction)
    assert rejected.sink_issue_id == nil
  end

  test "a mid-Push failure reports what was and wasn't created; retry creates only the missing ones",
       %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, push: [:ok, {:error, :unavailable}])

    extraction =
      create_review([
        %{title: "Send the Q3 report to finance"},
        %{title: "Book the offsite venue"},
        %{title: "Circulate the meeting notes"}
      ])

    assert {:error, {:unavailable, [created], 2}} = Sinks.push(scope, extraction)
    assert created.title == "Send the Q3 report to finance"
    assert [{_, %{title: "Send the Q3 report to finance"}}] = sink_pushes()

    assert {:ok, retried} = Sinks.push(scope, extraction)

    assert Enum.map(retried, & &1.title) == [
             "Book the offsite venue",
             "Circulate the meeting notes"
           ]

    # Three sink tasks in total — the already-created one was not re-pushed.
    assert [
             {_, %{title: "Send the Q3 report to finance"}},
             {_, %{title: "Book the offsite venue"}},
             {_, %{title: "Circulate the meeting notes"}}
           ] = sink_pushes()
  end

  test "a concurrent Push of the same Review is refused, never duplicated", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, push_gate: self())

    extraction = create_review(@two_action_points)

    first_push = Task.async(fn -> Sinks.push(scope, extraction) end)
    assert_receive {:push_task_called, worker}

    # The first Push is mid-flight inside the sink call; a second Push of the
    # same Review must refuse rather than create the same issues again.
    assert {:error, :push_in_progress} =
             Task.async(fn -> Sinks.push(scope, extraction) end) |> Task.await()

    send(worker, :proceed)
    assert_receive {:push_task_called, worker}
    send(worker, :proceed)

    assert {:ok, [_first, _second]} = Task.await(first_push)
    assert [_task1, _task2] = sink_pushes()
  end

  test "a user with no sink connection cannot push", %{scope: scope} do
    extraction = create_review(@two_action_points)
    :ok = Sinks.disconnect(scope)

    assert {:error, :not_connected} = Sinks.push(scope, extraction)
    assert sink_pushes() == []
  end

  test "a Push and its retries consume no Credit", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, push: [:ok, {:error, :unavailable}])

    extraction = create_review(@two_action_points)
    balance_before = ActionPoints.Billing.balance(scope)

    {:error, _partial} = Sinks.push(scope, extraction)
    {:ok, _retried} = Sinks.push(scope, extraction)

    assert ActionPoints.Billing.balance(scope) == balance_before
  end

  test "records each Action Point's created-issue reference", %{scope: scope} do
    extraction = create_review(@two_action_points)

    {:ok, _pushed} = Sinks.push(scope, extraction)

    [first, second] = reload_action_points(extraction)
    assert first.sink_issue_identifier == "ENG-1"
    assert first.sink_issue_url == "https://linear.app/fake/issue/ENG-1"
    assert second.sink_issue_identifier == "ENG-2"
  end
end
