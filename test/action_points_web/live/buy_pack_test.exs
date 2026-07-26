defmodule ActionPointsWeb.BuyPackTest do
  use ActionPointsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias ActionPoints.Billing.CreditTransaction
  alias ActionPoints.Repo

  setup :register_and_log_in_user

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_payment_provider)
      Application.delete_env(:action_points, :fake_payment_provider_sessions)
    end)

    :ok
  end

  test "Buy sends the user to Stripe Checkout for the Pack", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/buy")

    lv |> element("#buy-pack") |> render_click()
    assert_redirect(lv, "https://checkout.stripe.test/pay/cs_fake_1")

    assert [{user_id, urls}] =
             Application.get_env(:action_points, :fake_payment_provider_sessions)

    assert user_id == user.id
    assert urls.success_url =~ "/buy?checkout=success"
    assert urls.cancel_url =~ "/buy?checkout=cancelled"
  end

  test "a checkout that cannot be created keeps the user here with an error", %{conn: conn} do
    Application.put_env(:action_points, :fake_payment_provider, checkout: {:error, :unavailable})

    {:ok, lv, _html} = live(conn, ~p"/buy")

    lv |> element("#buy-pack") |> render_click()

    # The failure states its case beside the button that caused it, and repeats
    # the promise that matters at the payment moment.
    assert has_element?(lv, "#checkout-unavailable", "Nothing was charged")
    assert has_element?(lv, "#buy-pack")
  end

  test "the return page reflects the webhook's grant without writing one", %{
    conn: conn,
    user: user
  } do
    # The webhook has already landed: the grant exists before the user returns.
    Repo.insert!(%CreditTransaction{
      user_id: user.id,
      amount: 15,
      kind: :pack_purchase,
      provider_ref: "cs_1"
    })

    {:ok, lv, _html} = live(conn, ~p"/buy?checkout=success")

    assert has_element?(lv, "#checkout-success", "Payment received")
    assert has_element?(lv, "#credit-balance", "16")

    # The loop closes on the next move, not on the same pitch again.
    assert has_element?(lv, "#checkout-success a", "Extract a Transcript")
    refute has_element?(lv, "#buy-pack")

    # signup grant + the webhook's grant — the return page added nothing
    assert Repo.aggregate(CreditTransaction, :count) == 2
  end

  test "the return page catches a webhook that lands after it loaded", %{
    conn: conn,
    user: user
  } do
    {:ok, lv, _html} = live(conn, ~p"/buy?checkout=success")
    assert has_element?(lv, "#credit-balance", "1")

    Repo.insert!(%CreditTransaction{
      user_id: user.id,
      amount: 15,
      kind: :pack_purchase,
      provider_ref: "cs_1"
    })

    send(lv.pid, :refresh_balance)
    assert has_element?(lv, "#credit-balance", "16")
  end

  test "an abandoned checkout changes no balance", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/buy?checkout=cancelled")

    assert has_element?(lv, "#checkout-cancelled")
    assert has_element?(lv, "#credit-balance", "1")

    assert Repo.aggregate(
             from(t in CreditTransaction, where: t.user_id == ^user.id),
             :count
           ) == 1
  end

  describe "the Credits gate" do
    test "an empty balance meets the gate, with the Pack under it", %{conn: conn, user: user} do
      zero_out_balance(user)

      {:ok, lv, _html} = live(conn, ~p"/buy")

      assert has_element?(lv, "#credits-gate", "out of Credits")
      assert has_element?(lv, "#pack")
      assert has_element?(lv, "#buy-pack")
    end

    test "an account that still has Credits is never told it is out", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/buy")

      refute has_element?(lv, "#credits-gate")
      assert has_element?(lv, "#pack")
    end

    # A Pack is priced in Credits and sized in meetings — the one place the
    # glossary sanctions meetings as a unit.
    test "the Pack is named in Credits and sized in meetings", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/buy")

      assert has_element?(lv, "#pack", "15 Credits — 15 meetings")
    end
  end

  defp zero_out_balance(user) do
    Repo.insert!(%CreditTransaction{
      user_id: user.id,
      amount: -1,
      kind: :extraction_consumption
    })
  end
end
