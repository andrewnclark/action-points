defmodule ActionPoints.Sinks.ResolveAssigneesTest do
  use ActionPoints.DataCase, async: false

  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.AccountsFixtures
  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @session_token "resolve-test-session"

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_extractor_result)
    end)

    user = AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)

    {:ok, _connection} =
      Sinks.connect(scope, %{
        "api_key" => "lin_api_secret",
        "team_id" => "team-1",
        "team_name" => "Engineering"
      })

    %{scope: scope}
  end

  defp action_points(attrs_list) do
    stub_extractor({:ok, attrs_list})

    {:ok, extraction} =
      Meetings.create_extraction(nil, @session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    Meetings.get_extraction!(extraction.id, @session_token).action_points
  end

  test "a mapping hit resolves without consulting the sink's names", %{scope: scope} do
    {:ok, _} =
      Sinks.put_assignee_mapping(scope, "Bob", %{
        id: "u-mapped",
        name: "Bob Stored",
        handle: "bstored"
      })

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-other", name: "Bob", handle: "bob"}]}
    )

    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Bob"}])

    assert {:ok, _users} = Sinks.resolve_assignees(scope, [action_point])

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == :mapped
    assert resolved.sink_member_id == "u-mapped"
    assert resolved.sink_member_name == "Bob Stored"

    # The handle comes from the mapping's own cache, not from the live list —
    # the mapping is what a later visit still has.
    assert resolved.sink_member_handle == "bstored"
  end

  test "an unambiguous full-name match resolves as a suggestion", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-1", name: "Bob Smith", handle: "bsmith"}]}
    )

    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Bob Smith"}])

    {:ok, _users} = Sinks.resolve_assignees(scope, [action_point])

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == :suggested
    assert resolved.sink_member_id == "u-1"
    assert resolved.sink_member_name == "Bob Smith"
    assert resolved.sink_member_handle == "bsmith"
  end

  test "an unambiguous first-name match resolves as a suggestion, never a handle match", %{
    scope: scope
  } do
    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-1", name: "Bob Smith", handle: "andrewclark12"}]}
    )

    [andrew, bob] =
      action_points([
        %{title: "Ship it", assignee_guess: "Andrew"},
        %{title: "Review it", assignee_guess: "Bob"}
      ])

    {:ok, _users} = Sinks.resolve_assignees(scope, [andrew, bob])

    # "Andrew" never resolves off the handle, even though it matches exactly.
    resolved_andrew = Meetings.get_action_point!(andrew.id, @session_token)
    assert resolved_andrew.assignee_resolution == :unassigned
    assert resolved_andrew.sink_member_id == nil

    resolved_bob = Meetings.get_action_point!(bob.id, @session_token)
    assert resolved_bob.assignee_resolution == :suggested
    assert resolved_bob.sink_member_id == "u-1"
  end

  # The fold applies to both sides of the comparison, not just the guess: a
  # Task Sink member's own name goes through AssigneeMapping.normalize/1 too,
  # so growing the fold can never leave the two sides disagreeing.
  test "a Task Sink member's own name is folded by the same helper", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-1", name: "  Bob SMITH  ", handle: "bsmith"}]}
    )

    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Bob Smith"}])

    {:ok, _users} = Sinks.resolve_assignees(scope, [action_point])

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == :suggested
    assert resolved.sink_member_id == "u-1"
  end

  test "an ambiguous first name resolves as unassigned, never guessed", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink,
      users:
        {:ok,
         [
           %{id: "u-1", name: "Tom Nook", handle: "tomn"},
           %{id: "u-2", name: "Tom Chen", handle: "tomc"}
         ]}
    )

    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Tom"}])

    {:ok, _users} = Sinks.resolve_assignees(scope, [action_point])

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == :unassigned
    assert resolved.sink_member_id == nil
  end

  test "an Action Point with no guess resolves as unassigned", %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, users: {:ok, []})

    [action_point] = action_points([%{title: "Ship it", assignee_guess: nil}])

    {:ok, _users} = Sinks.resolve_assignees(scope, [action_point])

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == :unassigned
  end

  test "an already-resolved Action Point is left untouched, including an explicit clear", %{
    scope: scope
  } do
    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-1", name: "Bob Smith", handle: "bsmith"}]}
    )

    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Bob Smith"}])
    Meetings.set_action_point_assignee(action_point, nil)

    # Even though "Bob Smith" now unambiguously matches, a prior resolution
    # (here, the user's own clear) must never be silently overwritten.
    {:ok, _users} =
      Sinks.resolve_assignees(scope, [Meetings.get_action_point!(action_point.id, @session_token)])

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == :unassigned
    assert resolved.sink_member_id == nil
  end

  test "returns :not_connected when the user has no Sink Connection" do
    scope = Scope.for_user(AccountsFixtures.user_fixture())
    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Bob"}])

    assert Sinks.resolve_assignees(scope, [action_point]) == {:error, :not_connected}

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == nil
  end

  test "returns :not_connected for an anonymous Demo session (no scope)" do
    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Bob"}])

    assert Sinks.resolve_assignees(nil, [action_point]) == {:error, :not_connected}
  end

  test "returns :unavailable when the sink's member list can't be reached and touches nothing",
       %{scope: scope} do
    Application.put_env(:action_points, :fake_task_sink, users: {:error, :unavailable})

    [action_point] = action_points([%{title: "Ship it", assignee_guess: "Bob"}])

    assert Sinks.resolve_assignees(scope, [action_point]) == {:error, :unavailable}

    resolved = Meetings.get_action_point!(action_point.id, @session_token)
    assert resolved.assignee_resolution == nil
  end
end
