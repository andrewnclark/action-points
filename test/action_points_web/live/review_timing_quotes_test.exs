defmodule ActionPointsWeb.ReviewTimingQuotesTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday the 20th of March.
  Tom: I'll book the offsite venue in a few weeks, no rush on that one.
  Priya: And I'll circulate the notes.
  """

  # One Action Point whose timing resolves to a date, one whose timing was
  # voiced but pins none, and one the meeting said nothing timely about.
  @extractor_result {:ok,
                     [
                       %{
                         title: "Send the Q3 report to finance",
                         description: "Priya committed to sending the Q3 report to finance.",
                         assignee_guess: "Priya",
                         timing: %{kind: :absolute, year: 2026, month: 3, day: 20},
                         timing_quote: "by Friday the 20th of March",
                         quotes: []
                       },
                       %{
                         title: "Book the offsite venue",
                         description: "Tom will book the venue for the offsite.",
                         assignee_guess: "Tom",
                         timing: %{kind: :vague},
                         timing_quote: "in a few weeks",
                         quotes: []
                       },
                       %{
                         title: "Circulate the meeting notes",
                         description: nil,
                         assignee_guess: "Priya",
                         timing: nil,
                         timing_quote: nil,
                         quotes: []
                       }
                     ]}

  defp open_review(conn) do
    stub_extractor(@extractor_result)

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    action_points = Meetings.get_extraction!(extraction.id, session_token).action_points

    {:ok, review, _html} = live(conn, ~p"/review/#{extraction}")
    %{review: review, action_points: action_points}
  end

  defp dom_id(action_point), do: "action_points-#{action_point.id}"

  test "the Timing Quote renders beneath the due date it was resolved from", %{conn: conn} do
    %{review: review, action_points: [dated, _vague, _silent]} = open_review(conn)

    assert has_element?(review, "##{dom_id(dated)} [data-role=due-date]", "20 Mar 2026")

    assert has_element?(
             review,
             "##{dom_id(dated)}-timing-quote",
             "by Friday the 20th of March"
           )

    # Beneath, not above: the date is the claim and the words are the check.
    card = review |> element("##{dom_id(dated)}") |> render()

    assert :binary.match(card, "data-role=\"due-date\"") <
             :binary.match(card, "data-role=\"timing-quote\"")
  end

  test "the Timing Quote renders standalone when no due date could be resolved", %{conn: conn} do
    %{review: review, action_points: [_dated, vague, _silent]} = open_review(conn)

    assert has_element?(review, "##{dom_id(vague)} [data-role=no-due-date]")
    assert has_element?(review, "##{dom_id(vague)}-timing-quote", "in a few weeks")
  end

  test "an Action Point the meeting said nothing timely about shows no quote", %{conn: conn} do
    %{review: review, action_points: [_dated, _vague, silent]} = open_review(conn)

    refute has_element?(review, "##{dom_id(silent)}-timing-quote")
  end
end
