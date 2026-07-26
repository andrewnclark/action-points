defmodule ActionPointsWeb.ReviewCurationTest do
  use ActionPointsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  @extractor_result {:ok,
                     [
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
                     ]}

  # Creates a succeeded Extraction owned by the conn's anonymous session and
  # opens its Review screen. The Extraction runs synchronously here so the
  # curation tests start from a settled Review, not a spinner.
  defp open_review(conn) do
    Application.put_env(:action_points, :fake_extractor_result, @extractor_result)
    on_exit(fn -> Application.delete_env(:action_points, :fake_extractor_result) end)

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    action_points = Meetings.get_extraction!(extraction.id, session_token).action_points

    path = ~p"/review/#{extraction}"
    {:ok, review, _html} = live(conn, path)
    %{review: review, conn: conn, path: path, action_points: action_points}
  end

  # The DOM id the Review's stream gives an Action Point's card.
  defp dom_id(action_point), do: "action_points-#{action_point.id}"

  defp open_editor(review, action_point) do
    review |> element("##{dom_id(action_point)}-edit") |> render_click()
  end

  test "Action Points default to accepted and the Push button shows the count", %{conn: conn} do
    %{review: review} = open_review(conn)

    assert has_element?(
             review,
             "#action-points li[data-status=accepted]",
             "Send the Q3 report to finance"
           )

    assert has_element?(
             review,
             "#action-points li[data-status=accepted]",
             "Book the offsite venue"
           )

    assert has_element?(review, "#push-button", "Push 2")
  end

  test "an Action Point can be rejected and un-rejected", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    review |> element("##{dom_id(first)}-reject") |> render_click()

    assert has_element?(
             review,
             "#action-points li[data-status=rejected]",
             "Send the Q3 report to finance"
           )

    assert has_element?(review, "#push-button", "Push 1")

    review |> element("##{dom_id(first)}-accept") |> render_click()

    refute has_element?(review, "#action-points li[data-status=rejected]")
    assert has_element?(review, "#push-button", "Push 2")
  end

  test "title and description can be edited inline", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}",
      action_point: %{title: "Send the Q3 report", description: "Now with the final numbers."}
    )
    |> render_submit()

    refute has_element?(review, "#edit-#{dom_id(first)}")
    assert has_element?(review, "#action-points li", "Send the Q3 report")
    assert has_element?(review, "#action-points li", "Now with the final numbers.")
  end

  test "assignee guess and due date can be changed", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}",
      action_point: %{
        title: "Send the Q3 report to finance",
        assignee_guess: "Sam",
        due_date: "2026-08-14"
      }
    )
    |> render_submit()

    assert has_element?(review, "#action-points li [data-role=assignee]", "Sam")
    assert has_element?(review, "#action-points li [data-role=due-date]", "2026-08-14")
  end

  test "assignee guess and due date can be cleared", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}",
      action_point: %{
        title: "Send the Q3 report to finance",
        assignee_guess: "",
        due_date: ""
      }
    )
    |> render_submit()

    refute has_element?(review, "##{dom_id(first)} [data-role=assignee]")
    refute has_element?(review, "##{dom_id(first)} [data-role=due-date]")
  end

  test "clearing the title keeps the edit open with an error", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}", action_point: %{title: ""})
    |> render_submit()

    assert has_element?(review, "#edit-#{dom_id(first)}", "can't be blank")
    assert has_element?(review, "#push-button", "Push 2")
  end

  test "reloading the Review preserves all curation state", %{conn: conn} do
    %{review: review, conn: conn, path: path, action_points: [first, second]} = open_review(conn)

    review |> element("##{dom_id(second)}-reject") |> render_click()

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}",
      action_point: %{title: "Send the final Q3 numbers", assignee_guess: "Sam"}
    )
    |> render_submit()

    {:ok, reloaded, _html} = live(conn, path)

    assert has_element?(
             reloaded,
             "#action-points li[data-status=accepted]",
             "Send the final Q3 numbers"
           )

    assert has_element?(reloaded, "#action-points li [data-role=assignee]", "Sam")

    assert has_element?(
             reloaded,
             "#action-points li[data-status=rejected]",
             "Book the offsite venue"
           )

    assert has_element?(reloaded, "#push-button", "Push 1")
  end
end
