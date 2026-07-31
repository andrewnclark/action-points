defmodule ActionPointsWeb.ReviewAssigneeTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.ActionPoint
  alias ActionPoints.Repo
  alias ActionPoints.Sinks

  @api_key "lin_api_secret_key_abcd"

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  setup :register_and_log_in_user

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_extractor_result)
    end)
  end

  defp connect_sink(scope) do
    {:ok, _connection} =
      Sinks.connect(scope, %{
        "api_key" => @api_key,
        "team_id" => "team-1",
        "team_name" => "Engineering"
      })

    :ok
  end

  # Opens a succeeded Extraction's Review for the logged-in conn. The
  # Extraction itself runs anonymously (matching ActionPoints.Sinks.PushTest's
  # pattern) — Push and Review both key off the session token, not ownership.
  defp open_review(conn, action_points) do
    stub_extractor({:ok, action_points})

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)

    path = ~p"/review/#{extraction}"
    {:ok, review, _html} = live(conn, path)

    %{
      review: review,
      conn: conn,
      path: path,
      action_points: Meetings.get_extraction!(extraction.id, session_token).action_points
    }
  end

  defp dom_id(action_point), do: "action_points-#{action_point.id}"
  defp picker_id(action_point), do: "action-point-#{action_point.id}-assignee"
  defp picker_form_id(action_point), do: "action-point-#{action_point.id}-assignee-form"

  test "a mapping hit shows the resolved member with no click needed", %{conn: conn, scope: scope} do
    connect_sink(scope)
    {:ok, _} = Sinks.put_assignee_mapping(scope, "Priya", %{id: "u-priya", name: "Priya Sharma"})

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Send the report", assignee_guess: "Priya"}])

    assert has_element?(
             review,
             "##{dom_id(first)} option[value=u-priya][selected]",
             "Priya Sharma (@priya)"
           )

    refute has_element?(review, "##{dom_id(first)} [data-role=assignee-suggested]")
  end

  test "an unambiguous name match pre-selects a suggestion, visibly marked", %{
    conn: conn,
    scope: scope
  } do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Send the report", assignee_guess: "Priya Sharma"}])

    assert has_element?(review, "##{dom_id(first)} option[value=u-priya][selected]")
    assert has_element?(review, "##{dom_id(first)} [data-role=assignee-suggested]", "Suggested")
  end

  test "an ambiguous guess shows unassigned, with an open picker to fix it", %{
    conn: conn,
    scope: scope
  } do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users:
        {:ok,
         [
           %{id: "u-tom-n", name: "Tom Nook", handle: "tomn"},
           %{id: "u-tom-c", name: "Tom Chen", handle: "tomc"}
         ]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Book the venue", assignee_guess: "Tom"}])

    assert has_element?(
             review,
             "##{picker_id(first)} option[value=''][selected]",
             "Unassigned — pick a member"
           )
  end

  test "picking a member from the picker persists immediately", %{conn: conn, scope: scope} do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Send the report", assignee_guess: "Bogdan"}])

    assert has_element?(review, "##{picker_id(first)} option[value=''][selected]")

    review
    |> element("##{picker_form_id(first)}")
    |> render_change(%{"sink_user_id" => "u-priya"})

    assert has_element?(review, "##{dom_id(first)} option[value=u-priya][selected]")
    refute has_element?(review, "##{dom_id(first)} [data-role=assignee-suggested]")

    # The user's own pick writes the handle down too — it is the path taken
    # after a wrong suggestion, and the row must not come out of it knowing
    # less than one resolved automatically.
    picked = Repo.get!(ActionPoint, first.id)
    assert picked.sink_member_id == "u-priya"
    assert picked.sink_member_handle == "priya"
  end

  test "clearing an assignee through the picker deliberately unassigns it", %{
    conn: conn,
    scope: scope
  } do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Send the report", assignee_guess: "Priya Sharma"}])

    assert has_element?(review, "##{picker_id(first)} option[value=u-priya][selected]")

    review
    |> element("##{picker_form_id(first)}")
    |> render_change(%{"sink_user_id" => ""})

    assert has_element?(review, "##{picker_id(first)} option[value=''][selected]")
    refute has_element?(review, "##{dom_id(first)} [data-role=assignee-suggested]")
  end

  test "a failed member fetch shows a notice and the raw guess as plain text", %{
    conn: conn,
    scope: scope
  } do
    connect_sink(scope)
    Application.put_env(:action_points, :fake_task_sink, users: {:error, :unavailable})

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Send the report", assignee_guess: "Priya"}])

    assert has_element?(review, "#assignee-degraded-notice")
    refute has_element?(review, "##{picker_id(first)}")
    assert has_element?(review, "##{dom_id(first)} [data-role=named-person]", "Priya")
  end

  # The Named Person is a record of what the meeting said, so it survives every
  # state the Sink Member side can be in — most of all the picker, where it is
  # the only thing that answers the question the picker is asking.
  test "the Named Person stays on screen beside the picker", %{conn: conn, scope: scope} do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Send the report", assignee_guess: "Priya"}])

    assert has_element?(review, "##{picker_id(first)}")
    assert has_element?(review, "##{dom_id(first)} [data-role=named-person]", "Priya")
  end

  test "the Named Person stays on screen beside an unmatched picker", %{conn: conn, scope: scope} do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Book the venue", assignee_guess: "Bogdan"}])

    assert has_element?(review, "##{picker_id(first)} option[value=''][selected]")
    assert has_element?(review, "##{dom_id(first)} [data-role=named-person]", "Bogdan")
  end

  # Once the member list is unavailable there is no picker, but both facts are
  # still on the row — and the handle is there because it was written down when
  # it was known, not re-fetched from a list that is gone.
  test "a resolved Sink Member survives a later visit with no member list, handle and all",
       %{conn: conn, scope: scope} do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{conn: conn, path: path, action_points: [first]} =
      open_review(conn, [%{title: "Send the report", assignee_guess: "Priya Sharma"}])

    resolved = Repo.get!(ActionPoint, first.id)
    assert resolved.sink_member_id == "u-priya"
    assert resolved.sink_member_name == "Priya Sharma"
    assert resolved.sink_member_handle == "priya"

    Application.put_env(:action_points, :fake_task_sink, users: {:error, :unavailable})
    {:ok, revisit, _html} = live(conn, path)

    refute has_element?(revisit, "##{picker_id(first)}")
    assert has_element?(revisit, "##{dom_id(first)} [data-role=named-person]", "Priya Sharma")
    assert has_element?(revisit, "##{dom_id(first)} [data-role=sink-member]", "@priya")
  end

  # An Action Point nobody was named for has no Named Person to render; the
  # Sink Member side still says what it knows.
  test "an Action Point with no Named Person renders only the Sink Member side", %{
    conn: conn,
    scope: scope
  } do
    connect_sink(scope)

    Application.put_env(:action_points, :fake_task_sink,
      users: {:ok, [%{id: "u-priya", name: "Priya Sharma", handle: "priya"}]}
    )

    %{review: review, action_points: [first]} =
      open_review(conn, [%{title: "Circulate the notes", assignee_guess: nil}])

    refute has_element?(review, "##{dom_id(first)} [data-role=named-person]")
    assert has_element?(review, "##{picker_id(first)}")
  end
end
