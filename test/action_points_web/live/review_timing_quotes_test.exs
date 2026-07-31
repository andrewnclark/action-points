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

  defp open_review(conn, opts \\ []) do
    stub_extractor(@extractor_result)

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    action_points = Meetings.get_extraction!(extraction.id, session_token).action_points

    case Keyword.get(opts, :walk_to) do
      nil -> :ok
      index -> walk_to(extraction.id, Enum.at(action_points, index))
    end

    {:ok, review, _html} = live(conn, ~p"/review/#{extraction}")
    %{review: review, action_points: action_points}
  end

  defp step_id(action_point), do: "step-#{action_point.id}"

  # The Timing Quote is what the meeting said, so it stands in the left column
  # with the rest of the record — and the due date it was resolved to stands
  # opposite it, in the issue we would create. Set against each other, a
  # misattribution is visible without reopening the Transcript.
  test "the Timing Quote is the meeting's words, the due date the resolution", %{conn: conn} do
    %{review: review, action_points: [dated, _vague, _silent]} = open_review(conn)

    step = "##{step_id(dated)}"

    assert has_element?(
             review,
             "#{step} [data-role=meeting-column] [data-role=timing-quote]",
             "by Friday the 20th of March"
           )

    assert has_element?(
             review,
             "#{step} [data-role=issue-column] [data-role=due-date]",
             "20 Mar 2026"
           )

    refute has_element?(review, "#{step} [data-role=meeting-column] [data-role=due-date]")
  end

  test "the Timing Quote stands alone when no due date could be resolved", %{conn: conn} do
    %{review: review, action_points: [_dated, vague, _silent]} = open_review(conn, walk_to: 1)

    assert has_element?(review, "##{step_id(vague)} [data-role=no-due-date]")
    assert has_element?(review, "##{step_id(vague)} [data-role=timing-quote]", "in a few weeks")
  end

  test "an Action Point the meeting said nothing timely about says so", %{conn: conn} do
    %{review: review, action_points: [_dated, _vague, silent]} = open_review(conn, walk_to: 2)

    refute has_element?(review, "##{step_id(silent)} [data-role=timing-quote]")

    assert has_element?(
             review,
             "##{step_id(silent)} [data-role=meeting-column]",
             "Nothing was said about when"
           )
  end
end
