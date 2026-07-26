defmodule ActionPointsWeb.LandingPageTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.Repo

  test "one click loads the sample transcript and starts an Extraction", %{conn: conn} do
    stub_extractor(
      {:ok,
       [
         %{
           title: "Send the launch checklist",
           description: "From the sample meeting.",
           assignee_guess: nil,
           due_date: nil
         }
       ]}
    )

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result = home |> element("#load-sample") |> render_click()

    assert {:error, {:live_redirect, %{to: review_path}}} = result
    assert review_path =~ "/review/"

    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "#action-points li", "Send the launch checklist")
    end)

    # The sample is a real Transcript run through the real pipeline.
    extraction = Repo.one!(Extraction)
    assert extraction.transcript_text =~ ":"
    assert extraction.status == :succeeded
  end

  test "the landing page explains the product: how it works, pricing, privacy", %{conn: conn} do
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    assert has_element?(home, "#how-it-works", "Review")
    assert has_element?(home, "#how-it-works", "Push")
    assert has_element?(home, "#pricing", "£5")
    assert has_element?(home, "#pricing", "15 meetings")
    assert has_element?(home, "#pricing", "first meeting")
    assert has_element?(home, "#privacy-note", "only")
  end
end
