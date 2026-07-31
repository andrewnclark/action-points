defmodule ActionPointsWeb.CreditGatingTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ActionPoints.Billing.CreditTransaction
  alias ActionPoints.Repo

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  defp submit_transcript(home) do
    home
    |> form("#transcript-form", extraction: %{transcript_text: @transcript})
    |> render_submit()
  end

  defp zero_out_balance(user) do
    Repo.insert!(%CreditTransaction{
      user_id: user.id,
      amount: -1,
      kind: :extraction_consumption
    })
  end

  describe "signed-in Extraction and the Credit" do
    setup :register_and_log_in_user

    test "the composer quotes a Credit while there is one, and says so when there isn't",
         %{conn: conn, user: user} do
      {:ok, home, _html} = live(conn, ~p"/")
      assert has_element?(home, "#transcript-form", "1 Credit")

      # An empty balance must not quote a price the account can't pay: submitting
      # would only bounce the reader to the Credits gate.
      zero_out_balance(user)

      {:ok, home, _html} = live(conn, ~p"/")
      assert has_element?(home, "#transcript-form", "No Credits left")
      refute has_element?(home, "#transcript-form", "1 Credit")
    end

    test "a successful Extraction drops the visible balance from 1 Credit to 0, live",
         %{conn: conn} do
      conn = get(conn, ~p"/")
      {:ok, home, _html} = live(conn)

      assert has_element?(home, "#credit-balance", "1 Credit")

      {:ok, review, _html} = follow_redirect(submit_transcript(home), conn)

      eventually(fn ->
        assert has_element?(review, "[data-role=step]")
        assert has_element?(review, "#credit-balance", "0 Credits")
      end)
    end

    test "a failed Extraction leaves the balance untouched", %{conn: conn, user: user} do
      stub_extractor({:error, :api_unavailable})

      conn = get(conn, ~p"/")
      {:ok, home, _html} = live(conn)

      {:ok, review, _html} = follow_redirect(submit_transcript(home), conn)

      eventually(fn ->
        assert has_element?(review, "#extraction-failed")
        assert has_element?(review, "#credit-balance", "1 Credit")
      end)

      assert Repo.all(
               from t in CreditTransaction,
                 where: t.user_id == ^user.id and t.kind == :extraction_consumption
             ) == []
    end

    test "a zero-Credit user's Extraction attempt routes to the buy page", %{
      conn: conn,
      user: user
    } do
      zero_out_balance(user)

      conn = get(conn, ~p"/")
      {:ok, home, _html} = live(conn)

      # A refused Extraction lands on the gate, not a bare price list: the reason
      # they were moved is on the page they were moved to, with the Pack under it.
      {:ok, buy, _html} = follow_redirect(submit_transcript(home), conn)
      assert has_element?(buy, "#credits-gate", "out of Credits")
      assert has_element?(buy, "#pack")

      # Nothing was created for the refused attempt.
      assert Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 0
    end

    test "a zero-Credit retry of a failed Extraction routes to the buy page too", %{
      conn: conn,
      user: user
    } do
      stub_extractor({:error, :api_unavailable})

      conn = get(conn, ~p"/")
      {:ok, home, _html} = live(conn)

      {:ok, review, _html} = follow_redirect(submit_transcript(home), conn)

      eventually(fn -> assert has_element?(review, "#retry-extraction") end)

      # Their last Credit goes elsewhere before they hit retry.
      zero_out_balance(user)

      result = review |> element("#retry-extraction") |> render_click()
      assert {:error, {:live_redirect, %{to: "/buy"}}} = result
    end
  end

  describe "the anonymous preview" do
    setup do
      override_anon_limits(session: {2, :timer.hours(1)}, ip: {1_000, :timer.hours(1)})
      :ok
    end

    test "charges nothing and is rate-limited per session", %{conn: conn} do
      conn = get(conn, ~p"/")

      # The first two Extractions of the window go through.
      for _ <- 1..2 do
        {:ok, home, _html} = live(conn, ~p"/")
        assert {:error, {:live_redirect, %{to: "/review/" <> _}}} = submit_transcript(home)
      end

      # The third is refused on the landing page, with no Extraction created.
      {:ok, home, _html} = live(conn, ~p"/")
      submit_transcript(home)
      assert has_element?(home, "#rate-limit-notice", "Demo")

      assert Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 2

      # Free means free: the ledger records nothing for anonymous Extractions.
      eventually(fn ->
        assert Repo.aggregate(CreditTransaction, :count) == 0
      end)
    end
  end
end
