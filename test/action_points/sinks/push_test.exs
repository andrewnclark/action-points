defmodule ActionPoints.Sinks.PushTest do
  use ActionPoints.DataCase, async: false

  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.AccountsFixtures
  alias ActionPoints.Meetings
  alias ActionPoints.Repo
  alias ActionPoints.Sinks
  alias ActionPoints.Sinks.AssigneeMapping

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
      timing: %{kind: :absolute, year: 2026, month: 7, day: 31}
    },
    %{
      title: "Book the offsite venue",
      description: "Tom will book the venue for the offsite.",
      assignee_guess: "Tom",
      timing: nil
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
    stub_extractor({:ok, action_points})

    {:ok, extraction} =
      Meetings.create_extraction(nil, @session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    extraction = Meetings.get_extraction!(extraction.id, @session_token)

    # A Push acts on decisions, and since ADR-0010 nothing is accepted by
    # default: these tests start from a Review that has been walked.
    %{extraction | action_points: accept_action_points(extraction.action_points)}
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

  test "Push sends exactly the assignee Review resolved and does no matching of its own", %{
    scope: scope
  } do
    # Scripted so a Push that tried to match by name would find a match and
    # get this wrong — proving Push never looks at the sink's user list.
    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    extraction = create_review(@two_action_points)
    [first, second] = extraction.action_points

    Meetings.set_action_point_assignee(first, %{id: "u-other", name: "Someone Else"})
    Meetings.set_action_point_assignee(second, nil)

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [
             {_, %{title: "Send the Q3 report to finance", assignee_id: "u-other"}},
             {_, %{title: "Book the offsite venue", assignee_id: nil}}
           ] = sink_pushes()
  end

  test "Pushing a resolved pick saves it as an Assignee Mapping, keyed by the guessed name", %{
    scope: scope
  } do
    extraction = create_review(@two_action_points)
    [first, _second] = extraction.action_points

    Meetings.set_action_point_assignee(first, %{
      id: "u-priya",
      name: "Priya Sharma",
      handle: "priya"
    })

    {:ok, _pushed} = Sinks.push(scope, extraction)

    connection = Sinks.get_connection(scope)

    # The handle rides along: the mapping is what a later Review resolves from
    # when the live member list is out of reach, so it has to carry both.
    assert %AssigneeMapping{
             sink_user_id: "u-priya",
             display_name: "Priya Sharma",
             handle: "priya"
           } =
             Repo.get_by!(AssigneeMapping,
               sink_connection_id: connection.id,
               normalized_guess: "priya"
             )
  end

  test "Pushing again with the same pick does not duplicate the mapping", %{scope: scope} do
    extraction = create_review(@two_action_points)
    [first, _second] = extraction.action_points
    Meetings.set_action_point_assignee(first, %{id: "u-priya", name: "Priya Sharma"})
    {:ok, _pushed} = Sinks.push(scope, extraction)

    connection = Sinks.get_connection(scope)
    assert Repo.aggregate(AssigneeMapping, :count) == 1

    # A second Review with the same name should resolve to the same mapping,
    # and Pushing it again must not create a second row for "priya".
    extraction2 = create_review([%{title: "Follow up with finance", assignee_guess: "Priya"}])
    [third] = extraction2.action_points
    Meetings.set_action_point_assignee(third, %{id: "u-priya", name: "Priya Sharma"})
    {:ok, _pushed} = Sinks.push(scope, extraction2)

    assert Repo.aggregate(AssigneeMapping, :count) == 1

    assert %AssigneeMapping{sink_user_id: "u-priya"} =
             Repo.get_by!(AssigneeMapping,
               sink_connection_id: connection.id,
               normalized_guess: "priya"
             )
  end

  test "Pushing a different pick for an already-mapped name repoints the mapping", %{
    scope: scope
  } do
    extraction = create_review(@two_action_points)
    [first, _second] = extraction.action_points
    Meetings.set_action_point_assignee(first, %{id: "u-priya", name: "Priya Sharma"})
    {:ok, _pushed} = Sinks.push(scope, extraction)

    extraction2 = create_review([%{title: "Follow up with finance", assignee_guess: "Priya"}])
    [third] = extraction2.action_points
    Meetings.set_action_point_assignee(third, %{id: "u-priya-two", name: "Priya Patel"})
    {:ok, _pushed} = Sinks.push(scope, extraction2)

    connection = Sinks.get_connection(scope)
    assert Repo.aggregate(AssigneeMapping, :count) == 1

    assert %AssigneeMapping{sink_user_id: "u-priya-two", display_name: "Priya Patel"} =
             Repo.get_by!(AssigneeMapping,
               sink_connection_id: connection.id,
               normalized_guess: "priya"
             )
  end

  test "Pushing a deliberately unassigned Action Point saves no mapping", %{scope: scope} do
    extraction = create_review(@two_action_points)
    [first, _second] = extraction.action_points
    Meetings.set_action_point_assignee(first, nil)

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert Repo.aggregate(AssigneeMapping, :count) == 0
  end

  test "Pushing an Action Point with no guess saves no mapping", %{scope: scope} do
    extraction =
      create_review([%{title: "Circulate the meeting notes", assignee_guess: nil}])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert Repo.aggregate(AssigneeMapping, :count) == 0
  end

  test "quotes are rendered into the pushed description as a From the meeting section", %{
    scope: scope
  } do
    extraction =
      create_review([
        %{
          title: "Send the Q3 report to finance",
          description: "Priya committed to sending the Q3 report to finance.",
          quotes: [
            "I'll send the Q3 report to finance by Friday.",
            "I'll book the venue for the offsite, no rush on that one."
          ]
        }
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: description}}] = sink_pushes()

    assert description == """
           Priya committed to sending the Q3 report to finance.

           ### From the meeting

           > I'll send the Q3 report to finance by Friday.

           > I'll book the venue for the offsite, no rush on that one.\
           """
  end

  test "an Action Point with no quotes pushes its prose untouched — no empty section", %{
    scope: scope
  } do
    extraction =
      create_review([
        %{
          title: "Send the Q3 report to finance",
          description: "Priya committed to sending the Q3 report to finance.",
          quotes: []
        }
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: "Priya committed to sending the Q3 report to finance."}}] =
             sink_pushes()
  end

  test "the Timing Quote joins the From the meeting section, last", %{scope: scope} do
    extraction =
      create_review([
        %{
          title: "Send the Q3 report to finance",
          description: "Priya committed to sending the Q3 report to finance.",
          timing: %{kind: :absolute, year: 2026, month: 7, day: 31},
          timing_quote: "no rush on that one",
          quotes: ["I'll send the Q3 report to finance by Friday."]
        }
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: description, due_date: ~D[2026-07-31]}}] = sink_pushes()

    assert description == """
           Priya committed to sending the Q3 report to finance.

           ### From the meeting

           > I'll send the Q3 report to finance by Friday.

           > no rush on that one\
           """
  end

  test "a Timing Quote a Grounding Quote already contains is not repeated", %{scope: scope} do
    extraction =
      create_review([
        %{
          title: "Send the Q3 report to finance",
          description: nil,
          timing: nil,
          timing_quote: "by Friday",
          quotes: ["I'll send the Q3 report to finance by Friday."]
        }
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: description}}] = sink_pushes()

    assert description == """
           ### From the meeting

           > I'll send the Q3 report to finance by Friday.\
           """
  end

  test "a Timing Quote with no resolved due date still reaches the pushed task", %{scope: scope} do
    extraction =
      create_review([
        %{
          title: "Book the offsite venue",
          description: nil,
          timing: %{kind: :vague},
          timing_quote: "no rush on that one",
          quotes: []
        }
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: description, due_date: nil}}] = sink_pushes()

    assert description == """
           ### From the meeting

           > no rush on that one\
           """
  end

  test "an Action Point with neither quotes nor a Timing Quote pushes with no section", %{
    scope: scope
  } do
    extraction =
      create_review([
        %{
          title: "Circulate the meeting notes",
          description: "Priya will circulate the notes.",
          timing: nil,
          timing_quote: nil,
          quotes: []
        }
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: "Priya will circulate the notes."}}] = sink_pushes()
  end

  test "quotes without prose push as just the From the meeting section", %{scope: scope} do
    extraction =
      create_review([
        %{
          title: "Send the Q3 report to finance",
          description: nil,
          quotes: ["I'll send the Q3 report to finance by Friday."]
        }
      ])

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: description}}] = sink_pushes()

    assert description == """
           ### From the meeting

           > I'll send the Q3 report to finance by Friday.\
           """
  end

  test "a quote removed at Review never reaches the sink", %{scope: scope} do
    extraction =
      create_review([
        %{
          title: "Send the Q3 report to finance",
          description: "Priya committed to sending the Q3 report to finance.",
          quotes: [
            "I'll send the Q3 report to finance by Friday.",
            "I'll book the venue for the offsite, no rush on that one."
          ]
        }
      ])

    [action_point] = extraction.action_points
    Meetings.remove_action_point_quote(action_point, 1)

    {:ok, _pushed} = Sinks.push(scope, extraction)

    assert [{_, %{description: description}}] = sink_pushes()
    assert description =~ "> I'll send the Q3 report to finance by Friday."
    refute description =~ "book the venue"
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
