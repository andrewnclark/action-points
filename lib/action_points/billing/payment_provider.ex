defmodule ActionPoints.Billing.PaymentProvider do
  @moduledoc """
  The payment port: create a Checkout session for the Pack, and verify and
  interpret the webhook that reports its outcome. Stripe is the only launch
  implementation (`ActionPoints.Billing.Stripe`); tests replace it with
  `ActionPoints.Billing.FakePaymentProvider` via the `:payment_provider`
  application env.

  Only the webhook grants Credits — the redirect back from Checkout is
  untrusted — so `interpret_webhook/2` refuses any payload whose signature it
  cannot verify.
  """

  @type checkout_session :: %{required(:id) => String.t(), required(:url) => String.t()}

  @type return_urls :: %{
          required(:success_url) => String.t(),
          required(:cancel_url) => String.t()
        }

  @type pack_purchase :: %{
          required(:session_id) => String.t(),
          required(:user_id) => integer()
        }

  @callback create_checkout_session(user_id :: pos_integer(), return_urls()) ::
              {:ok, checkout_session()} | {:error, :unavailable | :api_error}

  @callback interpret_webhook(payload :: binary(), signature_header :: String.t() | nil) ::
              {:pack_purchased, pack_purchase()} | :ignored | {:error, :invalid_signature}
end
