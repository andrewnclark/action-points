defmodule ActionPointsWeb.BuyPackLive do
  @moduledoc """
  The purchase page: one Pack, no subscriptions (ADR-0003). Checkout happens on
  Stripe — card details never enter the product — and Credits arrive via the
  webhook, so the return-from-Checkout state only reads the balance, never
  writes it.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Billing

  @balance_refresh_interval_ms 2_000
  @max_balance_refreshes 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md pt-10">
        <header class="text-center">
          <%!-- The page states why the reader is on it, and the reason changes:
          a paid checkout makes this a receipt, an empty balance makes it the
          doorway a refused Extraction sent them through, otherwise it is a
          shop. One lead per state, never a banner shouting over another. --%>
          <%= cond do %>
            <% @receipt? -> %>
              <%!-- The grant is the webhook's to write, so at this instant the
              balance may not have caught up. The page states what was bought,
              which is true the moment it renders, and points at the running
              count in the bar above rather than freezing a number that would
              read "you have 0 Credits" under a payment confirmation. --%>
              <div id="checkout-success">
                <span class="inline-flex items-center gap-2 rounded-full border border-success/40 px-3 py-1 text-[11px] font-medium tracking-[0.07em] text-base-content/65 uppercase">
                  <.icon name="hero-check-circle-micro" class="size-3.5 text-success" />
                  Payment received
                </span>
                <h1 class="mt-5 text-3xl font-semibold tracking-[-0.03em]">
                  Your Pack is on the way.
                </h1>
                <p class="mt-3 text-base-content/70">
                  {@pack_credits} Credits land on your balance a moment after payment.
                  The count in the bar above updates itself — refresh if it hasn't
                  caught up.
                </p>
                <.link navigate={~p"/"} class="btn btn-primary btn-sm mt-5">
                  Extract a Transcript
                </.link>
              </div>
            <% @gated? -> %>
              <div id="credits-gate">
                <span class="inline-flex items-center gap-2 rounded-full border border-base-300 px-3 py-1 text-[11px] font-medium tracking-[0.07em] text-base-content/65 uppercase">
                  <span
                    class="size-1.5 rounded-full bg-base-content/30 ring-3 ring-base-content/10"
                    aria-hidden="true"
                  /> Balance empty
                </span>
                <h1 class="mt-5 text-3xl font-semibold tracking-[-0.03em]">
                  You're out of Credits.
                </h1>
                <p class="mt-3 text-base-content/70">
                  An Extraction needs a Credit, and yours are spent. One Pack covers
                  your next {@pack_credits} meetings.
                </p>
              </div>
            <% true -> %>
              <div>
                <span class="text-[11px] font-medium tracking-[0.09em] text-base-content/65 uppercase">
                  Pack
                </span>
                <h1 class="mt-2 text-3xl font-semibold tracking-[-0.03em]">Buy a Pack</h1>
                <p class="mt-3 text-base-content/70">
                  One flat Pack, no subscription. A Credit is spent only when an
                  Extraction succeeds — failures are free.
                </p>
              </div>
          <% end %>
        </header>

        <%!-- The two ways back from Checkout that leave the reader still shopping.
        Each says what happened to the money first, because that is the only
        question they have. --%>
        <div
          :if={@cancelled?}
          id="checkout-cancelled"
          class="mt-8 flex gap-3 rounded-box border border-base-300 bg-base-200 p-4"
        >
          <.icon name="hero-arrow-uturn-left" class="size-5 shrink-0 text-base-content/65" />
          <div>
            <p class="font-semibold">Checkout cancelled.</p>
            <p class="mt-1 text-base-content/70">
              Nothing was charged and your balance is unchanged.
            </p>
          </div>
        </div>

        <div
          :if={@checkout_unavailable?}
          id="checkout-unavailable"
          class="mt-8 flex gap-3 rounded-box border border-error/40 bg-error/10 p-4"
          role="alert"
        >
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-error" />
          <div>
            <p class="font-semibold">Checkout wouldn't open.</p>
            <p class="mt-1 text-base-content/70">
              Nothing was charged. Try again in a moment.
            </p>
          </div>
        </div>

        <%!-- Someone who has just paid is not shopping: after a success the Pack
        stands down to a line of text, so the page they land on is a receipt with
        one next step rather than the same sales pitch with a tick on it. --%>
        <p :if={@receipt?} class="mt-10 text-center text-xs text-base-content/65">
          Need more later?
          <.link navigate={~p"/buy"} class="text-accent hover:underline">
            Buy another Pack
          </.link>
          any time.
        </p>

        <div
          :if={not @receipt?}
          id="pack"
          class="mt-8 rounded-box border border-primary/45 bg-linear-to-b from-primary/[0.07] to-transparent to-62% bg-base-200 p-6"
        >
          <span class="text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
            Pack
          </span>
          <p class="mt-2.5 text-4xl font-semibold tracking-[-0.035em]">
            {@pack_price}
            <span class="text-sm font-normal tracking-normal text-base-content/70">
              one-off
            </span>
          </p>
          <p class="mt-2 text-base-content/70">
            {@pack_credits} Credits — {@pack_credits} meetings
          </p>

          <ul class="mt-5 space-y-2 border-t border-base-300/60 pt-5 text-base-content/70">
            <li class="flex gap-2.5">
              <.icon name="hero-check-micro" class="mt-1 size-3.5 shrink-0 text-primary" />
              <span>One Credit per successful Extraction — a failed one costs nothing.</span>
            </li>
            <li class="flex gap-2.5">
              <.icon name="hero-check-micro" class="mt-1 size-3.5 shrink-0 text-primary" />
              <span>No subscription and no expiry. Credits keep until you spend them.</span>
            </li>
            <li class="flex gap-2.5">
              <.icon name="hero-check-micro" class="mt-1 size-3.5 shrink-0 text-primary" />
              <span>Buy another Pack whenever you run out.</span>
            </li>
          </ul>

          <button
            id="buy-pack"
            class="btn btn-primary mt-6 w-full"
            phx-click="checkout"
            phx-disable-with="Opening Stripe…"
          >
            Buy with Stripe
          </button>
        </div>

        <p
          :if={not @receipt?}
          class="mt-3.5 flex items-center justify-center gap-2 text-xs text-base-content/65"
        >
          <.icon name="hero-lock-closed-micro" class="size-3.5" />
          Payment is handled by Stripe — card details never touch ActionPoints.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    pack = Billing.pack()

    {:ok,
     assign(socket,
       pack_credits: pack.credits,
       pack_price: Billing.format_price(pack),
       checkout_unavailable?: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:receipt?, params["checkout"] == "success")
      |> assign(:cancelled?, params["checkout"] == "cancelled")
      # An empty balance is a fact about the account, not about the link that got
      # here — so every arrival with nothing left meets the gate, however they
      # came. Except on a receipt, where the balance is mid-flight from Stripe.
      |> assign(
        :gated?,
        socket.assigns.current_scope.credit_balance == 0 and
          params["checkout"] != "success"
      )
      # A failed checkout belongs to the attempt that caused it, not to the page.
      |> assign(:checkout_unavailable?, false)

    # The webhook, not this page, writes the grant — so the balance can trail
    # the return by a moment. Poll briefly until it lands.
    socket =
      if socket.assigns.receipt? and connected?(socket) do
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

      # A failure at the payment moment is answered in place, beside the button
      # that caused it — a toast that fades is the wrong surface for money.
      {:error, _reason} ->
        {:noreply, assign(socket, :checkout_unavailable?, true)}
    end
  end
end
