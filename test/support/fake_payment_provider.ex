defmodule ActionPoints.Billing.FakePaymentProvider do
  @moduledoc """
  Test double for the payment port. Tests script results per callback with:

      Application.put_env(:action_points, :fake_payment_provider,
        checkout: {:error, :unavailable},
        webhook: {:pack_purchased, %{session_id: "cs_1", user_id: user.id}}
      )

  Unscripted, `create_checkout_session/2` succeeds with a canned Checkout URL,
  and `interpret_webhook/2` answers `{:error, :invalid_signature}` — the safe
  default, mirroring the real adapter's stance on anything unverified. Created
  sessions accumulate in the `:fake_payment_provider_sessions` env so tests can
  assert who was sent to Checkout and with which return URLs.
  """

  @behaviour ActionPoints.Billing.PaymentProvider

  @impl true
  def create_checkout_session(user_id, urls) do
    default = {:ok, %{id: "cs_fake_1", url: "https://checkout.stripe.test/pay/cs_fake_1"}}

    case scripted(:checkout, default) do
      {:ok, session} ->
        sessions = Application.get_env(:action_points, :fake_payment_provider_sessions, [])

        Application.put_env(
          :action_points,
          :fake_payment_provider_sessions,
          sessions ++ [{user_id, urls}]
        )

        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def interpret_webhook(_payload, _signature_header) do
    scripted(:webhook, {:error, :invalid_signature})
  end

  defp scripted(key, default) do
    script = Application.get_env(:action_points, :fake_payment_provider, [])

    case Keyword.get(script, key, default) do
      [] ->
        default

      [next | rest] ->
        Application.put_env(
          :action_points,
          :fake_payment_provider,
          Keyword.put(script, key, rest)
        )

        next

      value ->
        value
    end
  end
end
