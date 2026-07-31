defmodule ActionPointsWeb.ReviewQuotesTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

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
  # opens its Review screen (same shape as ReviewCurationTest). `walk_to:`
  # names the Action Point whose step the Review should open on, since the
  # walk shows one at a time.
  defp open_review(conn, opts \\ []) do
    stub_extractor(@extractor_result)

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    extraction = Meetings.get_extraction!(extraction.id, session_token)
    action_points = extraction.action_points

    case Keyword.get(opts, :walk_to) do
      nil -> :ok
      index -> walk_to(extraction.id, Enum.at(action_points, index))
    end

    path = ~p"/review/#{extraction}"
    {:ok, review, _html} = live(conn, path)

    %{review: review, conn: conn, path: path, action_points: action_points}
  end

  defp step_id(action_point), do: "step-#{action_point.id}"

  defp reload(action_point) do
    ActionPoints.Repo.get!(ActionPoints.Meetings.ActionPoint, action_point.id)
  end

  # The text of the payload block, read off the bytes the LiveView actually
  # renders rather than a parsed-and-reserialised copy of them: the claim under
  # test is byte-identity, so a normaliser in the middle would be the one thing
  # that could quietly make it true.
  defp payload_text(review, action_point) do
    [_, inner] =
      Regex.run(
        ~r|<div id="#{step_id(action_point)}".*?<div data-role="payload-description"[^>]*>(.*?)</div>|s,
        render(review)
      )

    inner
    |> String.replace(~r|<button.*?</button>|s, "")
    |> String.replace(~r|</?span[^>]*>|, "")
    |> unescape()
  end

  defp unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  test "the description on screen is byte-identical to the one Push sends", %{conn: conn} do
    %{review: review, action_points: [quoted, _plain]} = open_review(conn)

    assert payload_text(review, quoted) == Sinks.compose_description(reload(quoted))
  end

  test "the payload carries the prose, the section heading and every quote", %{conn: conn} do
    %{review: review, action_points: [quoted, _plain]} = open_review(conn)

    payload = payload_text(review, quoted)

    assert payload =~ "Priya committed to sending the Q3 report to finance."
    assert payload =~ "### From the meeting"
    assert payload =~ "> I'll send the Q3 report to finance by Friday."
    assert payload =~ "> no rush on that one."
  end

  # Verbatim on the left too, so the quote we send can be checked against the
  # quote that was said without leaving the screen.
  test "the same quotes stand verbatim in the meeting column", %{conn: conn} do
    %{review: review, action_points: [quoted, _plain]} = open_review(conn)

    column = "##{step_id(quoted)} [data-role=meeting-column]"

    assert has_element?(
             review,
             "#{column} [data-role=grounding-quote]",
             "I'll send the Q3 report to finance by Friday."
           )

    assert has_element?(review, "#{column} [data-role=grounding-quote]", "no rush on that one.")
  end

  test "an Action Point with no quotes carries no From the meeting section", %{conn: conn} do
    %{review: review, action_points: [_quoted, plain]} = open_review(conn, walk_to: 1)

    refute payload_text(review, plain) =~ "### From the meeting"
    refute has_element?(review, "##{step_id(plain)} [data-role=grounding-quotes]")
  end

  # Quotes are removable and never editable: an edited quote is no longer
  # evidence. The control hangs off the payload, because removing a quote
  # changes what we send — the record on the left is not ours to amend.
  test "a quote can be removed from the payload, and stays removed on reload", %{conn: conn} do
    %{review: review, conn: conn, path: path, action_points: [quoted, _plain]} = open_review(conn)

    refute has_element?(review, "##{step_id(quoted)} [data-role=meeting-column] button")

    review |> element("#quote-#{quoted.id}-0-remove") |> render_click()

    refute payload_text(review, quoted) =~ "I'll send the Q3 report to finance by Friday."
    assert payload_text(review, quoted) =~ "no rush on that one."

    {:ok, reloaded, _html} = live(conn, path)

    refute payload_text(reloaded, quoted) =~ "I'll send the Q3 report to finance by Friday."
    assert payload_text(reloaded, quoted) =~ "no rush on that one."
    assert payload_text(reloaded, quoted) == Sinks.compose_description(reload(quoted))
  end

  test "removing the last quote removes the whole section", %{conn: conn} do
    %{review: review, action_points: [quoted, _plain]} = open_review(conn)

    review |> element("#quote-#{quoted.id}-1-remove") |> render_click()
    review |> element("#quote-#{quoted.id}-0-remove") |> render_click()

    refute payload_text(review, quoted) =~ "### From the meeting"
    refute has_element?(review, "##{step_id(quoted)} [data-role=grounding-quotes]")
    assert payload_text(review, quoted) == Sinks.compose_description(reload(quoted))
  end
end
