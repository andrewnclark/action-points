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
    assert has_element?(lv, "#flash-error", "Checkout is unavailable")
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
end
