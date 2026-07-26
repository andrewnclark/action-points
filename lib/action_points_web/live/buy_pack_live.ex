defmodule ActionPointsWeb.BuyPackLive do
  @moduledoc """
  The purchase page: one Pack, no subscriptions (ADR-0003). Checkout itself
  arrives with the Stripe story; the page already exists because it is where
  the zero-Credit gate routes an Extraction attempt.
  """

  use ActionPointsWeb, :live_view

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

        <div id="pack" class="card bg-base-200 mt-8 p-8">
          <p class="text-4xl font-bold">£5</p>
          <p class="mt-2 text-base-content/70">15 Credits — 15 meetings</p>
          <button
            id="buy-pack"
            class="btn btn-primary mt-6"
            disabled
            title="Checkout is coming shortly"
          >
            Checkout coming shortly
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
