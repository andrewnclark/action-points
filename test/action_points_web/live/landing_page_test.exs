defmodule ActionPointsWeb.LandingPageTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.Repo

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  test "one click lands on the sample Review, with no model call behind it", %{conn: conn} do
    # Any Extractor call would raise, so a live run cannot pass silently here.
    stub_extractor(:crash)

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result = home |> element("#load-sample") |> render_click()

    assert {:error, {:live_redirect, %{to: review_path}}} = result
    assert review_path =~ "/review/"

    {:ok, review, _html} = follow_redirect(result, conn)

    # No spinner on the way: the Review is finished when the visitor arrives.
    refute has_element?(review, "#extraction-progress")
    # The walk opens on the sample's first Action Point in Dependency Order —
    # legal's answer, which the landing page waits on — not on the meeting's
    # own first line.
    assert has_element?(
             review,
             "[data-role=step]",
             "Get legal's yes or no on the updated terms"
           )

    assert has_element?(review, "#review-toolbar", "8 not yet decided")

    # And it says what it is — the meeting is fiction, the screen is not.
    assert has_element?(review, "#sample-notice", "sample meeting")

    extraction = Repo.one!(Extraction)
    assert extraction.status == :succeeded
    assert extraction.sample
  end

  test "sample clicks cost nothing, so they don't count against the Demo's cap",
       %{conn: conn} do
    override_anon_limits(session: {1, :timer.hours(1)}, ip: {1, :timer.hours(1)})
    stub_extractor(:crash)

    conn = get(conn, ~p"/")

    for _click <- 1..3 do
      {:ok, home, _html} = live(conn)
      assert {:error, {:live_redirect, _to}} = home |> element("#load-sample") |> render_click()
    end

    assert Repo.aggregate(Extraction, :count) == 3

    # The allowance is untouched: a real Transcript still gets its one run.
    stub_extractor(
      {:ok,
       [
         %{
           title: "Send the Q3 report to finance",
           description: "Priya committed to sending it.",
           assignee_guess: "Priya",
           timing: nil
         }
       ]}
    )

    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    # Redirected to a Review rather than turned away: the allowance was there.
    assert {:error, {:live_redirect, _to}} = result
    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "[data-role=step]", "Send the Q3 report to finance")
    end)
  end

  test "the landing page explains the product: how it works, pricing, privacy", %{conn: conn} do
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    assert has_element?(home, "#how-it-works", "Transcript")
    assert has_element?(home, "#how-it-works", "Action Points")
    assert has_element?(home, "#how-it-works", "Review")
    assert has_element?(home, "#how-it-works", "Push")
    assert has_element?(home, "#pricing", "£5")
    assert has_element?(home, "#pricing", "15 meetings")
    assert has_element?(home, "#privacy-note", "only")

    # The page sells a Pack in meetings but still counts entitlement in Credits.
    assert has_element?(home, "#pricing", "Free Meeting")
    assert has_element?(home, "#pricing", "Pack")
    assert has_element?(home, "#pricing", "Credit")
  end

  test "the Demo states what it costs before the visitor spends it", %{conn: conn} do
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    # Anonymous: the Demo is rate-limited rather than charged, and says so.
    assert has_element?(home, "#transcript-form", "no account needed")
    refute has_element?(home, "#transcript-form", "1 Credit")
  end

  test "a rate-limited Demo says so on the page and offers the way through", %{conn: conn} do
    override_anon_limits(session: {1, :timer.hours(1)}, ip: {1_000, :timer.hours(1)})

    stub_extractor(
      {:ok,
       [
         %{
           title: "Send the Q3 report to finance",
           description: "Priya committed to sending it.",
           assignee_guess: "Priya",
           timing: nil
         }
       ]}
    )

    # The first Demo spends this session's whole allowance.
    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    # Let that Extraction finish before moving on, so its background task can't
    # outlive the test and die against a rolled-back sandbox.
    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "[data-role=step]", "Send the Q3 report to finance")
    end)

    # The same visitor comes back for a second run and is turned away.
    {:ok, home, _html} = live(conn)

    home
    |> form("#transcript-form", extraction: %{transcript_text: @transcript})
    |> render_submit()

    assert has_element?(home, "#rate-limit-notice", "Demo")
    assert has_element?(home, "#rate-limit-notice", "Free Meeting")
    assert has_element?(home, "#rate-limit-notice a[href='/users/register']")

    # Turned away means turned away: no second Extraction exists.
    assert Repo.aggregate(Extraction, :count) == 1

    # The notice belongs to the attempt that earned it — editing the Transcript
    # must not leave a stale "you've used up the Demo" standing over a live form.
    home
    |> form("#transcript-form", extraction: %{transcript_text: @transcript <> " More."})
    |> render_change()

    refute has_element?(home, "#rate-limit-notice")
  end

  # A visitor is quoted a price on the way in and charged one at the till. ADR-0003
  # makes the Pack a config value that changes freely, so the quote has to be read
  # from it rather than restated in the markup.
  describe "the Pack quoted in Pricing" do
    test "states the configured price and Credit count, non-round prices included",
         %{conn: conn} do
      repriced_pack(credits: 40, price_pence: 1250, currency: "gbp")

      {:ok, home, _html} = live(conn, ~p"/")

      assert has_element?(home, "#pricing-pack", "£12.50")
      assert has_element?(home, "#pricing-pack", "/ 40 meetings")
    end

    # The Free Meeting costs nothing in whatever the Pack is priced in — a zero
    # still carries a currency, so it cannot be a literal either.
    test "the Free Meeting is free in the Pack's currency", %{conn: conn} do
      repriced_pack(credits: 40, price_pence: 1250, currency: "usd")

      {:ok, home, _html} = live(conn, ~p"/")

      assert has_element?(home, "#pricing-free", "USD 0")
      assert has_element?(home, "#pricing-pack", "USD 12.50")
    end
  end

  defp repriced_pack(pack) do
    original = Application.fetch_env!(:action_points, :pack)
    Application.put_env(:action_points, :pack, pack)
    on_exit(fn -> Application.put_env(:action_points, :pack, original) end)
  end
end
