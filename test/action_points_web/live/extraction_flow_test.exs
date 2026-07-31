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
           timing: %{kind: :absolute, year: 2026, month: 7, day: 31}
         },
         %{
           title: "Book the offsite venue",
           description: "Tom will book the venue for the offsite.",
           assignee_guess: "Tom",
           timing: nil
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
      # The walk opens on the first Action Point in dependency order — one
      # screen, both columns, and the payload the Push would send.
      assert has_element?(review, "[data-role=step]", "Send the Q3 report to finance")
      assert has_element?(review, "[data-role=payload-description]", "Priya committed to sending")
      assert has_element?(review, "[data-role=due-date]", "31 Jul 2026")
      assert has_element?(review, "[data-role=named-person]", "Priya")
      assert has_element?(review, "#review-toolbar", "2 not yet decided")
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
      refute has_element?(review, "[data-role=step]")
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
           timing: nil
         }
       ]}
    )

    review |> element("#retry-extraction") |> render_click()

    eventually(fn ->
      assert has_element?(review, "[data-role=step]", "Send the Q3 report to finance")
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
           timing: nil
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
      assert has_element?(review, "[data-role=step]", "Send the Q3 report to finance")
    end)

    # The stored Transcript is the normalised text, not the raw cue file.
    extraction = ActionPoints.Repo.one!(ActionPoints.Meetings.Extraction)
    refute extraction.transcript_text =~ "WEBVTT"
    refute extraction.transcript_text =~ "-->"
    assert extraction.transcript_text =~ "Priya Sharma: I'll send the Q3 report"
  end

  test "a dated export filename anchors the meeting date, and Review says so", %{conn: conn} do
    stub_extractor(
      {:ok, [%{title: "Send the Q3 report to finance", description: nil, assignee_guess: nil}]}
    )

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    home
    |> file_input("#transcript-form", :transcript, [
      %{
        name: "GMT20260312-140000_Recording.transcript.txt",
        content: "Priya Sharma: I'll send the Q3 report to finance by Friday.",
        type: "text/plain"
      }
    ])
    |> render_upload("GMT20260312-140000_Recording.transcript.txt")

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: ""})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)

    assert has_element?(review, "#meeting-date", "Thu 12 Mar")
    assert has_element?(review, "#meeting-date", "from the filename")
  end

  test "a date stated in the Transcript anchors the meeting date, and Review says so",
       %{conn: conn} do
    stub_extractor(
      {:ok,
       %{
         meeting_date: ~D[2026-05-04],
         action_points: [
           %{title: "Send the Q3 report to finance", description: nil, assignee_guess: nil}
         ]
       }}
    )

    conn = conn |> get(~p"/") |> put_connect_params(%{"local_date" => "2026-07-26"})
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "#meeting-date", "Mon 4 May")
      assert has_element?(review, "#meeting-date", "stated in the Transcript")
    end)
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

  test "the Review says which date deadlines resolve against, from the browser's local date",
       %{conn: conn} do
    stub_extractor(
      {:ok,
       [
         %{
           title: "Send the Q3 report to finance",
           description: nil,
           assignee_guess: nil,
           timing: nil
         }
       ]}
    )

    conn = conn |> get(~p"/") |> put_connect_params(%{"local_date" => "2026-07-26"})
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)

    extraction = ActionPoints.Repo.one!(ActionPoints.Meetings.Extraction)
    assert extraction.meeting_date == ~D[2026-07-26]
    assert extraction.meeting_date_source == :assumed

    eventually(fn ->
      assert has_element?(review, "#meeting-date", "Deadlines resolved relative to Sun 26 Jul")
      assert has_element?(review, "#meeting-date", "(assumed)")
    end)
  end

  test "a browser date that isn't a date falls back to the server's own", %{conn: conn} do
    stub_extractor({:ok, []})

    conn = conn |> get(~p"/") |> put_connect_params(%{"local_date" => "sometime today"})
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)
    eventually(fn -> assert has_element?(review, "#review-empty") end)

    extraction = ActionPoints.Repo.one!(ActionPoints.Meetings.Extraction)
    assert extraction.meeting_date == Date.utc_today()
    assert extraction.meeting_date_source == :assumed
  end

  test "an Extraction started without connect params still records a meeting date",
       %{conn: conn} do
    stub_extractor({:ok, []})

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)
    eventually(fn -> assert has_element?(review, "#review-empty") end)

    extraction = ActionPoints.Repo.one!(ActionPoints.Meetings.Extraction)
    assert extraction.meeting_date == Date.utc_today()
    assert extraction.meeting_date_source == :assumed
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
