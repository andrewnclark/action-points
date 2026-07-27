defmodule ActionPointsWeb.ReviewAssigneeTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings
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

    {:ok, review, _html} = live(conn, ~p"/review/#{extraction}")

    %{
      review: review,
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
    assert has_element?(review, "##{dom_id(first)} [data-role=assignee]", "Priya")
  end
end
