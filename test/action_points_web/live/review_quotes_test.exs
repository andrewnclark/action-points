defmodule ActionPointsWeb.ReviewQuotesTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
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
                         timing: nil,
                         quotes: [
                           "I'll send the Q3 report to finance by Friday.",
                           "no rush on that one."
                         ]
                       },
                       %{
                         title: "Book the offsite venue",
                         description: "Tom will book the venue for the offsite.",
                         assignee_guess: "Tom",
                         timing: nil,
                         quotes: []
                       }
                     ]}

  # Creates a succeeded Extraction owned by the conn's anonymous session and
  # opens its Review screen (same shape as ReviewCurationTest).
  defp open_review(conn) do
    stub_extractor(@extractor_result)

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

  defp dom_id(action_point), do: "action_points-#{action_point.id}"

  test "quotes render collapsed inside the card", %{conn: conn} do
    %{review: review, action_points: [quoted, _plain]} = open_review(conn)

    assert has_element?(review, "##{dom_id(quoted)}-quotes summary", "From the meeting")

    assert has_element?(
             review,
             "##{dom_id(quoted)}-quotes blockquote",
             "I'll send the Q3 report to finance by Friday."
           )

    assert has_element?(review, "##{dom_id(quoted)}-quotes blockquote", "no rush on that one.")

    # Collapsed by default: the server never renders the details open.
    refute has_element?(review, "details[open]")
  end

  test "a card with no quotes shows no From the meeting section", %{conn: conn} do
    %{review: review, action_points: [_quoted, plain]} = open_review(conn)

    refute has_element?(review, "##{dom_id(plain)}-quotes")
  end

  test "a quote can be removed, and stays removed on reload", %{conn: conn} do
    %{review: review, conn: conn, path: path, action_points: [quoted, _plain]} = open_review(conn)

    review |> element("##{dom_id(quoted)}-quote-0-remove") |> render_click()

    refute has_element?(
             review,
             "##{dom_id(quoted)}-quotes blockquote",
             "I'll send the Q3 report to finance by Friday."
           )

    assert has_element?(review, "##{dom_id(quoted)}-quotes blockquote", "no rush on that one.")

    {:ok, reloaded, _html} = live(conn, path)

    refute has_element?(
             reloaded,
             "##{dom_id(quoted)}-quotes blockquote",
             "I'll send the Q3 report to finance by Friday."
           )

    assert has_element?(reloaded, "##{dom_id(quoted)}-quotes blockquote", "no rush on that one.")
  end

  test "removing the last quote removes the whole section", %{conn: conn} do
    %{review: review, action_points: [quoted, _plain]} = open_review(conn)

    review |> element("##{dom_id(quoted)}-quote-1-remove") |> render_click()
    review |> element("##{dom_id(quoted)}-quote-0-remove") |> render_click()

    refute has_element?(review, "##{dom_id(quoted)}-quotes")
  end
end
