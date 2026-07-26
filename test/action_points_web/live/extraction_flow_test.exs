defmodule ActionPointsWeb.ExtractionFlowTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  test "visitor pastes a transcript and sees Action Points on the Review screen", %{conn: conn} do
    stub_extractor(
      {:ok,
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
    )

    # Dispatch a plain GET first so `conn` carries the anonymous session
    # cookie into the Review request.
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    assert {:error, {:live_redirect, %{to: review_path}}} = result
    assert review_path =~ "/review/"

    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "#action-points li", "Send the Q3 report to finance")
      assert has_element?(review, "#action-points li", "Priya committed to sending the Q3 report")
      assert has_element?(review, "#action-points li", "31 Jul 2026")
      assert has_element?(review, "#action-points li", "Book the offsite venue")
      assert has_element?(review, "#action-points li", "Tom")
    end)
  end

  test "a failed Extraction shows an error and can be retried", %{conn: conn} do
    stub_extractor({:error, :api_unavailable})

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "#extraction-failed")
      assert has_element?(review, "#retry-extraction")
      refute has_element?(review, "#action-points")
    end)

    # The failure has to say what it cost, which is nothing.
    assert has_element?(review, "#extraction-failed", "No Credit was spent")

    # The retry runs a fresh Extraction attempt — this time it succeeds.
    stub_extractor(
      {:ok,
       [
         %{
           title: "Send the Q3 report to finance",
           description: "Priya committed to sending the Q3 report.",
           assignee_guess: "Priya",
           due_date: nil
         }
       ]}
    )

    review |> element("#retry-extraction") |> render_click()

    eventually(fn ->
      assert has_element?(review, "#action-points li", "Send the Q3 report to finance")
      refute has_element?(review, "#extraction-failed")
    end)
  end

  @tag capture_log: true
  test "a crash inside the Extractor still lands on the error-with-retry state", %{conn: conn} do
    stub_extractor(:crash)

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "#extraction-failed")
      assert has_element?(review, "#retry-extraction")
    end)
  end

  test "visitor uploads a .vtt export and it feeds the same pipeline as paste", %{conn: conn} do
    stub_extractor(
      {:ok,
       [
         %{
           title: "Send the Q3 report to finance",
           description: "Priya committed to sending the Q3 report.",
           assignee_guess: "Priya",
           due_date: nil
         }
       ]}
    )

    vtt = """
    WEBVTT

    1
    00:00:03.600 --> 00:00:06.240
    Priya Sharma: I'll send the Q3 report to finance by Friday.

    2
    00:00:06.900 --> 00:00:10.170
    Tom Baker: Great. I'll book the venue for the offsite.
    """

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    home
    |> file_input("#transcript-form", :transcript, [
      %{name: "zoom-meeting.vtt", content: vtt, type: "text/vtt"}
    ])
    |> render_upload("zoom-meeting.vtt")

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: ""})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "#action-points li", "Send the Q3 report to finance")
    end)

    # The stored Transcript is the normalised text, not the raw cue file.
    extraction = ActionPoints.Repo.one!(ActionPoints.Meetings.Extraction)
    refute extraction.transcript_text =~ "WEBVTT"
    refute extraction.transcript_text =~ "-->"
    assert extraction.transcript_text =~ "Priya Sharma: I'll send the Q3 report"
  end

  test "an over-cap transcript is rejected with a clear message, pre-Extraction", %{conn: conn} do
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    home
    |> form("#transcript-form",
      extraction: %{transcript_text: String.duplicate("word ", 25_001)}
    )
    |> render_submit()

    assert has_element?(home, "#transcript-form", "25,000-word cap")
    assert ActionPoints.Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 0
  end

  test "a trivially short input is rejected helpfully", %{conn: conn} do
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    home
    |> form("#transcript-form", extraction: %{transcript_text: "buy milk"})
    |> render_submit()

    assert has_element?(home, "#transcript-form", "is too short to be a meeting transcript")
    assert ActionPoints.Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 0
  end

  test "a blank transcript is rejected without creating an Extraction", %{conn: conn} do
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    home
    |> form("#transcript-form", extraction: %{transcript_text: ""})
    |> render_submit()

    assert has_element?(home, "#transcript-form", "can't be blank")
    assert ActionPoints.Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 0
  end

  test "an Extraction is not visible to a different anonymous session", %{conn: conn} do
    {:ok, extraction} =
      ActionPoints.Meetings.create_extraction(nil, "someone-elses-session", %{
        "transcript_text" => @transcript
      })

    conn = get(conn, ~p"/")

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/review/#{extraction}")
    end
  end
end
