defmodule ActionPointsWeb.StripeWebhookController do
  @moduledoc """
  The payment webhook: the only writer of Pack grants — the redirect back from
  Checkout is untrusted. Replays and unknown users answer 200, because their
  outcome is settled and a Stripe retry cannot improve it; only an unverifiable
  signature is refused.
  """

  use ActionPointsWeb, :controller

  alias ActionPoints.Billing

  def create(conn, _params) do
    payload = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    case Billing.payment_provider().interpret_webhook(payload, signature) do
      {:pack_purchased, %{session_id: session_id, user_id: user_id}} ->
        case Billing.grant_pack_credits(user_id, session_id) do
          :granted -> send_resp(conn, 200, "granted")
          :already_granted -> send_resp(conn, 200, "already granted")
          {:error, :unknown_user} -> send_resp(conn, 200, "no such user")
        end

      :ignored ->
        send_resp(conn, 200, "ignored")

      {:error, :invalid_signature} ->
        send_resp(conn, 400, "invalid signature")
    end
  end
end
