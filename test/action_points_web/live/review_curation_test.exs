defmodule ActionPointsWeb.ReviewCurationTest do
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
                         timing: %{kind: :absolute, year: 2026, month: 7, day: 31}
                       },
                       %{
                         title: "Book the offsite venue",
                         description: "Tom will book the venue for the offsite.",
                         assignee_guess: "Tom",
                         timing: nil
                       }
                     ]}

  # Creates a succeeded Extraction owned by the conn's anonymous session and
  # opens its Review screen. The Extraction runs synchronously here so the
  # curation tests start from a settled Review, not a spinner.
  defp open_review(conn, result \\ @extractor_result, opts \\ []) do
    stub_extractor(result)

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    extraction = Meetings.get_extraction!(extraction.id, session_token)

    # The Review these tests drive is one that has been walked: since ADR-0010
    # nothing arrives accepted, and this screen is about what follows. Pass
    # `decided: false` for the state a visitor actually lands on.
    action_points =
      if Keyword.get(opts, :decided, true),
        do: accept_action_points(extraction.action_points),
        else: extraction.action_points

    path = ~p"/review/#{extraction}"
    {:ok, review, _html} = live(conn, path)
    %{review: review, conn: conn, path: path, action_points: action_points}
  end

  # The DOM id the Review's stream gives an Action Point's card.
  defp dom_id(action_point), do: "action_points-#{action_point.id}"

  defp open_editor(review, action_point) do
    review |> element("##{dom_id(action_point)}-edit") |> render_click()
  end

  test "accepted Action Points show as accepted and the Push button counts them", %{conn: conn} do
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

  test "the toolbar tallies the curation and promises nothing is created yet", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    assert has_element?(review, "h1", "Review your Action Points")
    assert has_element?(review, "#review-toolbar", "2 accepted")

    assert has_element?(
             review,
             "#review-toolbar",
             "Nothing is created in Linear until you Push"
           )

    review |> element("##{dom_id(first)}-reject") |> render_click()

    assert has_element?(review, "#review-toolbar", "1 accepted")
    assert has_element?(review, "#review-toolbar", "1 rejected")
  end

  # What a visitor now lands on, pinned deliberately. Since ADR-0010 nothing
  # arrives accepted, so this list screen opens with nothing to Push and an
  # Accept on every card. The walk that makes that state navigable is #106's;
  # until it lands this test is what stops the intermediate state being
  # silently wrong rather than merely unfinished.
  test "a Review nobody has walked yet tallies nothing accepted and offers no Push",
       %{conn: conn} do
    %{review: review} = open_review(conn, @extractor_result, decided: false)

    assert has_element?(review, "#action-points li[data-status=undecided]")
    assert has_element?(review, "#review-toolbar", "0 accepted")
    assert has_element?(review, "#review-toolbar", "2 not yet decided")
    refute has_element?(review, "#review-toolbar", "rejected")

    # The promise still shows: it is what a first-time visitor most needs.
    assert has_element?(
             review,
             "#review-toolbar",
             "Nothing is created in Linear until you Push"
           )

    assert has_element?(review, "#push-button[disabled]")
  end

  test "an Extraction that finds nothing lands on a designed empty Review", %{conn: conn} do
    %{review: review} = open_review(conn, {:ok, []})

    assert has_element?(review, "#review-empty", "No Action Points")
    assert has_element?(review, "#review-empty a", "Extract another Transcript")
    refute has_element?(review, "#push-button")
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

  test "the due date can be changed", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}",
      action_point: %{
        title: "Send the Q3 report to finance",
        due_date: "2026-08-14"
      }
    )
    |> render_submit()

    assert has_element?(review, "#action-points li [data-role=due-date]", "14 Aug 2026")
  end

  test "the due date can be cleared", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}",
      action_point: %{
        title: "Send the Q3 report to finance",
        due_date: ""
      }
    )
    |> render_submit()

    refute has_element?(review, "##{dom_id(first)} [data-role=due-date]")
  end

  # The Named Person is what the meeting said, so nothing in Review may rewrite
  # it — and it is also the Assignee Mapping key, so a rewrite would silently
  # re-key any mapping born from it. There is no field for it any more, and a
  # crafted submit that names it anyway changes nothing.
  test "the edit form offers no way to rewrite the Named Person", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    refute has_element?(review, "#edit-#{dom_id(first)} [name='action_point[assignee_guess]']")
  end

  test "a crafted submit cannot rewrite the Named Person", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    open_editor(review, first)

    review
    |> form("#edit-#{dom_id(first)}", action_point: %{title: "Send the Q3 report to finance"})
    |> render_submit(%{"action_point" => %{"assignee_guess" => "Sam"}})

    assert ActionPoints.Repo.get!(ActionPoints.Meetings.ActionPoint, first.id).assignee_guess ==
             "Priya"
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
    |> form("#edit-#{dom_id(first)}", action_point: %{title: "Send the final Q3 numbers"})
    |> render_submit()

    {:ok, reloaded, _html} = live(conn, path)

    assert has_element?(
             reloaded,
             "#action-points li[data-status=accepted]",
             "Send the final Q3 numbers"
           )

    assert has_element?(reloaded, "#action-points li [data-role=named-person]", "Priya")

    assert has_element?(
             reloaded,
             "#action-points li[data-status=rejected]",
             "Book the offsite venue"
           )

    assert has_element?(reloaded, "#push-button", "Push 1")
  end
end
