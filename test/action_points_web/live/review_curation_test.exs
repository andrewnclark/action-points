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

    # Most of these tests are about the walk itself, so they open on the step a
    # visitor actually lands on. `decided: true` is for the ones about what
    # follows it.
    action_points =
      if Keyword.get(opts, :decided, false),
        do: accept_action_points(extraction.action_points),
        else: extraction.action_points

    path = ~p"/review/#{extraction}"
    {:ok, review, _html} = live(conn, path)

    %{
      review: review,
      conn: conn,
      path: path,
      extraction: extraction,
      action_points: action_points
    }
  end

  defp step_id(action_point), do: "step-#{action_point.id}"

  test "the walk opens on the first Action Point in dependency order, alone", %{conn: conn} do
    %{review: review, action_points: [first, second]} = open_review(conn)

    assert has_element?(review, "##{step_id(first)}", "Send the Q3 report to finance")
    refute has_element?(review, "##{step_id(second)}")
    assert has_element?(review, "[data-role=step]", "0 of 2 decided")
  end

  test "the step is two columns, the meeting's above the issue's on a narrow viewport", %{
    conn: conn
  } do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    step = review |> element("##{step_id(first)}") |> render()

    # One grid that is a single column until there is width for two, so the
    # left column stacks above the right rather than beside it.
    assert step =~ "md:grid-cols-2"

    {meeting, _} = :binary.match(step, ~s(data-role="meeting-column"))
    {issue, _} = :binary.match(step, ~s(data-role="issue-column"))
    assert meeting < issue
  end

  # The interaction rule ADR-0010 enforces the layout claim with: the left
  # column is a record of the meeting, so nothing in it can be touched.
  test "no control exists that can change anything in the left column", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    for control <- ~w(button input select textarea a form) do
      refute has_element?(review, "##{step_id(first)} [data-role=meeting-column] #{control}")
    end
  end

  test "Accept moves the walk on, and Reject decides just as well", %{conn: conn} do
    %{review: review, action_points: [first, second]} = open_review(conn)

    review |> element("[data-role=step] [data-role=accept]") |> render_click()

    refute has_element?(review, "##{step_id(first)}")
    assert has_element?(review, "##{step_id(second)}", "Book the offsite venue")
    assert has_element?(review, "#review-toolbar", "1 accepted")

    review |> element("[data-role=step] [data-role=reject]") |> render_click()

    refute has_element?(review, "[data-role=step]")
    assert has_element?(review, "#review-toolbar", "1 accepted")
    assert has_element?(review, "#review-toolbar", "1 rejected")
    assert has_element?(review, "#push-button", "Push 1")
  end

  test "the walk ends on the decisions, and every one of them is stated", %{conn: conn} do
    %{review: review, action_points: [first, second]} =
      open_review(conn, @extractor_result, decided: true)

    refute has_element?(review, "[data-role=step]")
    assert has_element?(review, "#decided-#{first.id}[data-status=accepted]")
    assert has_element?(review, "#decided-#{second.id}[data-status=accepted]")
    assert has_element?(review, "#push-button", "Push 2")
  end

  test "a Review nobody has walked yet tallies nothing accepted and offers no Push",
       %{conn: conn} do
    %{review: review} = open_review(conn)

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

  # Rejecting is one click, and so is a mis-click. The old card let a rejected
  # Action Point be accepted again; the walk must not lose that.
  test "a rejection can be undone after the walk has moved on", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    review |> element("[data-role=step] [data-role=reject]") |> render_click()
    review |> element("[data-role=step] [data-role=reject]") |> render_click()

    assert has_element?(review, "#decided-#{first.id}[data-status=rejected]")
    assert has_element?(review, "#push-button[disabled]")

    review |> element("#decided-#{first.id}-accept") |> render_click()

    assert has_element?(review, "#decided-#{first.id}[data-status=accepted]")
    refute has_element?(review, "#decided-#{first.id}-accept")
    assert has_element?(review, "#push-button", "Push 1")
  end

  # Edit is gone, and with it the only route to a title or a description at
  # Review. Its two survivors — the due date and the Sink Member — are pills.
  test "no Edit control, no editing card, and no editing badge survive", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    refute has_element?(review, "##{step_id(first)}-edit")
    refute has_element?(review, "#edit-#{step_id(first)}")
    refute render(review) =~ "Editing"
    refute has_element?(review, "[name='action_point[title]']")
    refute has_element?(review, "[name='action_point[description]']")
  end

  test "the due date can be changed from its pill, without Edit", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    review
    |> form("#action-point-#{first.id}-due-date-form", %{"due_date" => "2026-08-14"})
    |> render_change()

    assert has_element?(review, "##{step_id(first)} [data-role=due-date]", "14 Aug 2026")
  end

  # Edit used to be the only way to take a date the meeting got wrong back
  # off. Deleting Edit must not take that with it.
  test "the due date can be cleared without Edit", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    review |> element("#action-point-#{first.id}-due-date-clear") |> render_click()

    refute has_element?(review, "##{step_id(first)} [data-role=due-date]")
    assert has_element?(review, "##{step_id(first)} [data-role=no-due-date]")
    assert is_nil(ActionPoints.Repo.get!(ActionPoints.Meetings.ActionPoint, first.id).due_date)
  end

  # The Named Person is what the meeting said, so nothing in Review may rewrite
  # it — and it is also the Assignee Mapping key, so a rewrite would silently
  # re-key any mapping born from it. Two things stop it and this pins the outer
  # one: the handler takes the due date out of the params by name and builds
  # the update itself, so nothing else a submit carries reaches a changeset.
  # `curation_changeset/2` not casting the Named Person is the inner one, and
  # has its own test.
  test "the due-date handler passes on nothing but the due date", %{conn: conn} do
    %{review: review, action_points: [first, _second]} = open_review(conn)

    review
    |> form("#action-point-#{first.id}-due-date-form", %{"due_date" => "2026-08-14"})
    |> render_change(%{"due_date" => "2026-08-14", "assignee_guess" => "Sam", "title" => "Nope"})

    stored = ActionPoints.Repo.get!(ActionPoints.Meetings.ActionPoint, first.id)
    assert stored.assignee_guess == "Priya"
    assert stored.title == "Send the Q3 report to finance"
  end

  # A pushed Action Point is a record of something that exists, so its step
  # freezes: the chips saying what was created remain and every control that
  # could change what was sent is gone.
  test "a pushed Action Point renders with its controls frozen and its chips intact",
       %{conn: conn} do
    %{conn: conn, path: path, action_points: [first, _second]} = open_review(conn)

    Meetings.record_push!(first, %{
      id: "issue-1",
      identifier: "ENG-1",
      url: "https://linear.app/fake/issue/ENG-1"
    })

    {:ok, review, _html} = live(conn, path)

    assert has_element?(review, "##{step_id(first)} a[data-role=sink-issue]", "ENG-1")
    assert has_element?(review, "##{step_id(first)} [data-role=due-date]", "31 Jul 2026")
    assert has_element?(review, "##{step_id(first)} [data-role=named-person]", "Priya")

    refute has_element?(review, "[data-role=step] [data-role=accept]")
    refute has_element?(review, "[data-role=step] [data-role=reject]")
    refute has_element?(review, "#quote-#{first.id}-0-remove")
    refute has_element?(review, "#action-point-#{first.id}-due-date-form")
    refute has_element?(review, "#action-point-#{first.id}-due-date-clear")
  end

  test "reloading the Review lands on the same step, with its curation intact", %{conn: conn} do
    %{review: review, conn: conn, path: path, action_points: [first, second]} = open_review(conn)

    review |> element("#action-point-#{first.id}-due-date-clear") |> render_click()
    review |> element("[data-role=step] [data-role=accept]") |> render_click()

    {:ok, reloaded, _html} = live(conn, path)

    assert has_element?(reloaded, "##{step_id(second)}")
    refute has_element?(reloaded, "##{step_id(first)}")
    assert has_element?(reloaded, "#review-toolbar", "1 accepted")
    assert is_nil(ActionPoints.Repo.get!(ActionPoints.Meetings.ActionPoint, first.id).due_date)
  end
end
