defmodule ActionPointsWeb.ExtractionFlowTest do
  use ActionPointsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  defp stub_extractor(result) do
    Application.put_env(:action_points, :fake_extractor_result, result)
    on_exit(fn -> Application.delete_env(:action_points, :fake_extractor_result) end)
  end

  # The Extraction runs in a background task, so the Review screen settles
  # asynchronously — retry the assertion until it passes or time runs out.
  defp eventually(fun, tries \\ 100) do
    fun.()
  rescue
    e in [ExUnit.AssertionError] ->
      if tries == 0 do
        reraise(e, __STACKTRACE__)
      else
        Process.sleep(20)
        eventually(fun, tries - 1)
      end
  end

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
      assert has_element?(review, "#action-points li", "2026-07-31")
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
      ActionPoints.Meetings.create_extraction("someone-elses-session", %{
        "transcript_text" => @transcript
      })

    conn = get(conn, ~p"/")

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/review/#{extraction}")
    end
  end
end
