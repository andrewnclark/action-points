defmodule ActionPoints.Billing.StripeTest do
  use ExUnit.Case, async: false

  alias ActionPoints.Billing.Stripe

  @webhook_secret "whsec_test_secret"

  setup do
    Application.put_env(:action_points, Stripe,
      api_key: "sk_test_key",
      webhook_secret: @webhook_secret,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:action_points, Stripe) end)
  end

  defp sign(payload, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, System.system_time(:second))
    secret = Keyword.get(opts, :secret, @webhook_secret)

    signature =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{signature}"
  end

  defp completed_session_payload(attrs \\ %{}) do
    session =
      Map.merge(
        %{
          "id" => "cs_test_123",
          "client_reference_id" => "42",
          "payment_status" => "paid"
        },
        attrs
      )

    Jason.encode!(%{
      "type" => "checkout.session.completed",
      "data" => %{"object" => session}
    })
  end

  describe "create_checkout_session/2" do
    @urls %{
      success_url: "https://example.com/buy?checkout=success",
      cancel_url: "https://example.com/buy?checkout=cancelled"
    }

    test "creates a payment-mode session for the Pack and returns its URL" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk_test_key"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["mode"] == "payment"
        assert params["client_reference_id"] == "42"
        assert params["success_url"] == @urls.success_url
        assert params["cancel_url"] == @urls.cancel_url
        assert params["line_items[0][quantity]"] == "1"
        assert params["line_items[0][price_data][currency]"] == "gbp"
        assert params["line_items[0][price_data][unit_amount]"] == "500"
        assert params["line_items[0][price_data][product_data][name]"] =~ "15"

        Req.Test.json(conn, %{
          "id" => "cs_test_123",
          "url" => "https://checkout.stripe.com/c/pay/cs_test_123"
        })
      end)

      assert Stripe.create_checkout_session(42, @urls) ==
               {:ok, %{id: "cs_test_123", url: "https://checkout.stripe.com/c/pay/cs_test_123"}}
    end

    test "a Stripe error response is a typed failure" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => %{"message" => "Invalid currency"}})
      end)

      assert Stripe.create_checkout_session(42, @urls) == {:error, :api_error}
    end

    test "a transport failure is :unavailable" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert Stripe.create_checkout_session(42, @urls) == {:error, :unavailable}
    end
  end

  describe "interpret_webhook/2" do
    test "a signed checkout.session.completed is a Pack purchase" do
      payload = completed_session_payload()

      assert Stripe.interpret_webhook(payload, sign(payload)) ==
               {:pack_purchased, %{session_id: "cs_test_123", user_id: 42}}
    end

    test "a tampered payload is rejected" do
      payload = completed_session_payload()
      signature = sign(completed_session_payload(%{"client_reference_id" => "99"}))

      assert Stripe.interpret_webhook(payload, signature) == {:error, :invalid_signature}
    end

    test "a signature from the wrong secret is rejected" do
      payload = completed_session_payload()

      assert Stripe.interpret_webhook(payload, sign(payload, secret: "whsec_other")) ==
               {:error, :invalid_signature}
    end

    test "a stale timestamp is rejected" do
      payload = completed_session_payload()
      stale = System.system_time(:second) - 600

      assert Stripe.interpret_webhook(payload, sign(payload, timestamp: stale)) ==
               {:error, :invalid_signature}
    end

    test "a missing or malformed signature header is rejected" do
      payload = completed_session_payload()

      assert Stripe.interpret_webhook(payload, nil) == {:error, :invalid_signature}
      assert Stripe.interpret_webhook(payload, "not-a-signature") == {:error, :invalid_signature}
    end

    test "an unconfigured endpoint secret refuses everything rather than crashing" do
      Application.put_env(:action_points, Stripe, api_key: "sk_test_key")

      payload = completed_session_payload()
      assert Stripe.interpret_webhook(payload, sign(payload)) == {:error, :invalid_signature}
    end

    test "verified events of other types are ignored" do
      payload = Jason.encode!(%{"type" => "invoice.paid", "data" => %{"object" => %{}}})

      assert Stripe.interpret_webhook(payload, sign(payload)) == :ignored
    end

    test "a completed session that is not paid is ignored" do
      payload = completed_session_payload(%{"payment_status" => "unpaid"})

      assert Stripe.interpret_webhook(payload, sign(payload)) == :ignored
    end
  end
end
