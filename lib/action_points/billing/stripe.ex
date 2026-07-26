defmodule ActionPoints.Billing.Stripe do
  @moduledoc """
  Real payment adapter: Stripe Checkout in payment mode. The Pack is sent as
  inline `price_data` rather than a pre-created Stripe Product, so its price
  stays in application config (ADR-0003: pricing is config, change freely) with
  no dashboard setup to mirror. Test mode throughout at launch — flipping to
  live keys is a config change, not a code change.

  Webhook signatures follow Stripe's v1 scheme: HMAC-SHA256 of
  `"<timestamp>.<payload>"` with the endpoint secret, carried in the
  `Stripe-Signature` header. Events timestamped outside a five-minute window
  are refused, bounding replay of a captured payload.
  """

  @behaviour ActionPoints.Billing.PaymentProvider

  alias ActionPoints.Billing

  @url "https://api.stripe.com/v1/checkout/sessions"
  @signature_tolerance_seconds 300

  @impl true
  def create_checkout_session(user_id, urls) do
    pack = Billing.pack()

    form = [
      {"mode", "payment"},
      {"client_reference_id", Integer.to_string(user_id)},
      {"success_url", urls.success_url},
      {"cancel_url", urls.cancel_url},
      {"line_items[0][quantity]", "1"},
      {"line_items[0][price_data][currency]", pack.currency},
      {"line_items[0][price_data][unit_amount]", Integer.to_string(pack.price_pence)},
      {"line_items[0][price_data][product_data][name]",
       "ActionPoints Pack — #{pack.credits} meetings"}
    ]

    request_options =
      [
        form: form,
        auth: {:bearer, Keyword.fetch!(config(), :api_key)},
        receive_timeout: 30_000
      ] ++ Keyword.get(config(), :req_options, [])

    case Req.post(@url, request_options) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id, "url" => url}}} ->
        {:ok, %{id: id, url: url}}

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        {:error, :unavailable}

      {:ok, %Req.Response{}} ->
        {:error, :api_error}

      {:error, _exception} ->
        {:error, :unavailable}
    end
  end

  @impl true
  def interpret_webhook(payload, signature_header) do
    if verified?(payload, signature_header) do
      interpret(Jason.decode(payload))
    else
      {:error, :invalid_signature}
    end
  end

  defp interpret(
         {:ok, %{"type" => "checkout.session.completed", "data" => %{"object" => session}}}
       ) do
    with %{"id" => session_id, "payment_status" => "paid", "client_reference_id" => ref}
         when is_binary(ref) <- session,
         {user_id, ""} <- Integer.parse(ref) do
      {:pack_purchased, %{session_id: session_id, user_id: user_id}}
    else
      # Unpaid sessions (async payment methods) and sessions we didn't
      # create: verified, but nothing to grant.
      _other -> :ignored
    end
  end

  defp interpret(_decoded), do: :ignored

  defp verified?(payload, signature_header) when is_binary(signature_header) do
    parts = parse_signature_header(signature_header)

    # A missing endpoint secret refuses everything rather than crashing:
    # a misconfigured deploy must not turn webhooks into 500s Stripe retries.
    with secret when is_binary(secret) <- config()[:webhook_secret],
         {:ok, timestamp_value} <- Map.fetch(parts, "t"),
         {:ok, signatures} <- Map.fetch(parts, "v1"),
         {timestamp, ""} <- Integer.parse(timestamp_value),
         true <- fresh?(timestamp) do
      expected =
        :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
        |> Base.encode16(case: :lower)

      Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected))
    else
      _missing_or_stale -> false
    end
  end

  defp verified?(_payload, _signature_header), do: false

  # "t=1492774577,v1=5257a86...,v1=..." — Stripe sends multiple v1 entries
  # while a webhook endpoint's secret is being rolled.
  defp parse_signature_header(header) do
    header
    |> String.split(",")
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        ["t", value] -> Map.put(acc, "t", value)
        ["v1", value] -> Map.update(acc, "v1", [value], &[value | &1])
        _other -> acc
      end
    end)
  end

  defp fresh?(timestamp) do
    abs(System.system_time(:second) - timestamp) <= @signature_tolerance_seconds
  end

  defp config do
    Application.get_env(:action_points, __MODULE__, [])
  end
end
