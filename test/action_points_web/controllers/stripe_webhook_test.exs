defmodule ActionPointsWeb.StripeWebhookTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.AccountsFixtures
  import Ecto.Query

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.Billing
  alias ActionPoints.Billing.CreditTransaction
  alias ActionPoints.Repo

  setup do
    on_exit(fn -> Application.delete_env(:action_points, :fake_payment_provider) end)
    %{user: user_fixture()}
  end

  defp post_webhook(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", "t=1,v1=irrelevant-the-fake-decides")
    |> post(~p"/webhooks/stripe", ~s({"id": "evt_1"}))
  end

  defp pack_purchase_count do
    Repo.aggregate(from(t in CreditTransaction, where: t.kind == :pack_purchase), :count)
  end

  test "a verified checkout completion grants 15 Credits, exactly once", %{
    conn: conn,
    user: user
  } do
    Application.put_env(:action_points, :fake_payment_provider,
      webhook: {:pack_purchased, %{session_id: "cs_1", user_id: user.id}}
    )

    assert post_webhook(conn).status == 200
    assert Billing.balance(Scope.for_user(user)) == 16

    # Stripe redelivers webhooks; a replay must be a no-op.
    assert post_webhook(build_conn()).status == 200
    assert Billing.balance(Scope.for_user(user)) == 16
    assert pack_purchase_count() == 1
  end

  test "an unverifiable webhook grants nothing", %{conn: conn, user: user} do
    # The fake's default webhook verdict is {:error, :invalid_signature}.
    assert post_webhook(conn).status == 400
    assert Billing.balance(Scope.for_user(user)) == 1
    assert pack_purchase_count() == 0
  end

  test "verified events that are not a completed checkout grant nothing", %{
    conn: conn,
    user: user
  } do
    Application.put_env(:action_points, :fake_payment_provider, webhook: :ignored)

    assert post_webhook(conn).status == 200
    assert Billing.balance(Scope.for_user(user)) == 1
    assert pack_purchase_count() == 0
  end

  test "a completion for an unknown user grants nothing and still succeeds", %{conn: conn} do
    Application.put_env(:action_points, :fake_payment_provider,
      webhook: {:pack_purchased, %{session_id: "cs_1", user_id: -1}}
    )

    assert post_webhook(conn).status == 200
    assert pack_purchase_count() == 0
  end
end
