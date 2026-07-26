defmodule ActionPointsWeb.BuyPackLive do
  @moduledoc """
  The purchase page: one Pack, no subscriptions (ADR-0003). Checkout happens on
  Stripe — card details never enter the product — and Credits arrive via the
  webhook, so the success banner only reads the balance, never writes it.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Billing

  @balance_refresh_interval_ms 2_000
  @max_balance_refreshes 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md pt-10 text-center">
        <h1 class="text-3xl font-bold">Buy a Pack</h1>
        <p class="mt-3 text-base-content/70">
          One flat Pack, no subscription. A Credit is spent only when an
          Extraction succeeds — failures are free.
        </p>

        <div
          :if={@checkout == "success"}
          id="checkout-success"
          class="mt-6 rounded-lg border border-success/40 bg-success/10 p-4 text-sm"
        >
          <p class="font-semibold">
            Payment received — you have {@current_scope.credit_balance}
            {credits_noun(@current_scope.credit_balance)}.
          </p>
          <p class="mt-1 text-base-content/70">
            Credits can take a few seconds to arrive; refresh if the balance
            hasn't caught up yet.
          </p>
        </div>

        <div
          :if={@checkout == "cancelled"}
          id="checkout-cancelled"
          class="mt-6 rounded-lg border border-base-300 bg-base-200 p-4 text-sm"
        >
          Checkout cancelled — nothing was charged and your balance is unchanged.
        </div>

        <div id="pack" class="card bg-base-200 mt-8 p-8">
          <p class="text-4xl font-bold">{@pack_price}</p>
          <p class="mt-2 text-base-content/70">
            {@pack_credits} Credits — {@pack_credits} meetings
          </p>
          <button id="buy-pack" class="btn btn-primary mt-6" phx-click="checkout">
            Buy with Stripe
          </button>
          <p class="mt-3 text-xs text-base-content/60">
            You'll be sent to Stripe to pay — card details never touch ActionPoints.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    pack = Billing.pack()
    {:ok, assign(socket, pack_credits: pack.credits, pack_price: format_price(pack))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, :checkout, params["checkout"])

    # The webhook, not this page, writes the grant — so the balance can trail
    # the return by a moment. Poll briefly until it lands.
    socket =
      if socket.assigns.checkout == "success" and connected?(socket) do
        Process.send_after(self(), :refresh_balance, @balance_refresh_interval_ms)
        assign(socket, :balance_refreshes_left, @max_balance_refreshes)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_balance, socket) do
    socket =
      socket
      |> assign(:current_scope, Billing.with_balance(socket.assigns.current_scope))
      |> update(:balance_refreshes_left, &(&1 - 1))

    if socket.assigns.balance_refreshes_left > 0 do
      Process.send_after(self(), :refresh_balance, @balance_refresh_interval_ms)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("checkout", _params, socket) do
    urls = %{
      success_url: url(~p"/buy?checkout=success"),
      cancel_url: url(~p"/buy?checkout=cancelled")
    }

    case Billing.payment_provider().create_checkout_session(
           socket.assigns.current_scope.user.id,
           urls
         ) do
      {:ok, %{url: checkout_url}} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Checkout is unavailable right now — please try again in a moment. Nothing was charged."
         )}
    end
  end

  defp credits_noun(1), do: "Credit"
  defp credits_noun(_count), do: "Credits"

  defp format_price(%{currency: currency, price_pence: pence}) when rem(pence, 100) == 0,
    do: "#{currency_symbol(currency)}#{div(pence, 100)}"

  defp format_price(%{currency: currency, price_pence: pence}),
    do: "#{currency_symbol(currency)}#{:erlang.float_to_binary(pence / 100, decimals: 2)}"

  defp currency_symbol("gbp"), do: "£"
  defp currency_symbol(code), do: String.upcase(code) <> " "
end
