defmodule ActionPointsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ActionPointsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :max_width, :string,
    default: "max-w-2xl",
    doc: "the content column width — Review runs wider than the form screens"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header
      id="app-nav"
      class="sticky top-0 z-20 border-b border-base-300/60 bg-base-100/80 backdrop-blur-md"
    >
      <%!-- A signed-in account carries enough links to outrun a phone's width, so
      below `sm` the cluster wraps onto its own row rather than scrolling the
      whole page sideways. --%>
      <nav class="mx-auto flex max-w-[1180px] flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-2 sm:h-13 sm:flex-nowrap sm:py-0 sm:px-6 lg:px-8">
        <.wordmark navigate={~p"/"} />

        <div class="flex items-center gap-1 text-xs text-base-content/70">
          <%!-- The Credit balance renders here rather than in the root layout so
          LiveViews can update it as Credits are consumed --%>
          <.link
            :if={@current_scope}
            id="credit-balance"
            navigate={~p"/buy"}
            class="inline-flex items-center gap-1.5 rounded-full border border-base-300 bg-base-200 px-2.5 py-1 transition-colors hover:border-base-content/30 hover:text-base-content"
            title="Credits remaining"
          >
            <span class="font-semibold text-base-content">
              {@current_scope.credit_balance}
            </span>
            {if @current_scope.credit_balance == 1, do: "Credit", else: "Credits"}
          </.link>

          <%= if @current_scope do %>
            <span class="hidden px-2 text-base-content/65 lg:inline">
              {@current_scope.user.email}
            </span>
            <.nav_link href={~p"/settings/sink"}>Linear</.nav_link>
            <.nav_link href={~p"/users/settings"}>Settings</.nav_link>
            <.nav_link href={~p"/users/log-out"} method="delete">Log out</.nav_link>
          <% else %>
            <.nav_link href={~p"/users/log-in"}>Log in</.nav_link>
            <.link href={~p"/users/register"} class="btn btn-primary btn-xs ml-1">
              Register
            </.link>
          <% end %>

          <.theme_toggle />
        </div>
      </nav>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class={["mx-auto space-y-4", @max_width]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The one mark the product has.

  Shared because the shell is not the only place it appears: the error pages
  render outside `app/1` — no navigation, no `current_scope` — and are the one
  screen where a drifting wordmark would be least likely to be noticed.

  Takes `navigate` inside the app, where the shell is already live, and `href`
  on the error pages, which are static documents with no socket to push to.

  ## Examples

      <Layouts.wordmark navigate={~p"/"} />
      <Layouts.wordmark href={~p"/"} class="mx-auto" />
  """
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(href navigate)

  def wordmark(assigns) do
    ~H"""
    <.link
      class={["flex w-fit items-center gap-2 font-semibold tracking-[-0.02em]", @class]}
      {@rest}
    >
      <%!-- The mark is drawn, not typed. Inter ships here as a latin subset and
      has no U+25B2, so a ▲ glyph fell through to whatever the visitor's system
      happened to offer — a different triangle per OS for the one mark that has
      to be the same everywhere. --%>
      <span
        class="grid size-[18px] place-items-center rounded-[4px] bg-linear-to-br from-accent to-primary text-base-100"
        aria-hidden="true"
      >
        <svg viewBox="0 0 10 9" class="w-[9px]" fill="currentColor" aria-hidden="true">
          <path d="M5 0 10 9H0z" />
        </svg>
      </span>
      ActionPoints
    </.link>
    """
  end

  @doc """
  The chrome the single-column screens share: a narrow column, a lead that says
  which moment this is, the panel, and a quiet footer link out.

  The screens differ by state — registering with a Demo Review in hand is a
  different moment from re-authenticating, and connecting a Task Sink is a
  different moment from replacing its key — so the lead is a slot and every
  screen writes its own. What they must not differ in is the shape.

  ## Examples

      <Layouts.form_page eyebrow="Account" title="Log in.">
        <:lead>We email you a link — no password to remember.</:lead>
        <.form for={@form} id="login_form_magic">…</.form>
        <:footer>No account yet? <.link navigate={~p"/users/register"}>Create one</.link></:footer>
      </Layouts.form_page>
  """
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  slot :lead
  slot :inner_block, required: true
  slot :footer

  def form_page(assigns) do
    ~H"""
    <div class="mx-auto max-w-md pt-10">
      <.page_lead eyebrow={@eyebrow} title={@title}>
        <:lead :if={@lead != []}>{render_slot(@lead)}</:lead>
      </.page_lead>

      <div class="mt-8 rounded-box border border-base-300 bg-base-200 p-6">
        {render_slot(@inner_block)}
      </div>

      <p :if={@footer != []} class="mt-4 text-center text-xs text-base-content/65">
        {render_slot(@footer)}
      </p>
    </div>
    """
  end

  @doc """
  How a page opens: the small eyebrow naming the moment, the sentence-cased
  title, and an optional line of context. Shared so the account screens can't
  drift apart a tracking value at a time.
  """
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  slot :lead

  def page_lead(assigns) do
    ~H"""
    <header>
      <span class="text-[11px] font-medium tracking-[0.09em] text-base-content/65 uppercase">
        {@eyebrow}
      </span>
      <h1 class="mt-2 text-3xl font-semibold tracking-[-0.03em]">{@title}</h1>
      <p :if={@lead != []} class="mt-3 text-base-content/70">{render_slot(@lead)}</p>
    </header>
    """
  end

  @doc """
  The Demo Review a visitor is about to sign up around, stated on the signup
  screens themselves.

  The Push button promised the Review would survive; this is that promise kept
  in view at the moment of doubt, counting exactly what is waiting. It renders
  nothing when there is no Demo behind the visitor.
  """
  attr :count, :integer, default: nil, doc: "Action Points ready to Push, nil when there is none"

  def review_kept(assigns) do
    ~H"""
    <div
      :if={@count}
      id="review-kept"
      class="mb-5 flex gap-3 rounded-box border border-primary/40 bg-primary/[0.07] p-4"
    >
      <.icon name="hero-bookmark" class="size-5 shrink-0 text-primary" />
      <div>
        <p class="font-semibold">Your Review is kept.</p>
        <p class="mt-1 text-base-content/70">
          <%= if @count > 0 do %>
            {ngettext("1 Action Point is", "%{count} Action Points are", @count)} waiting to Push,
            and you land straight back on them. Nothing is created until you Push.
          <% else %>
            You land straight back on it once you're in. Nothing is created until you Push.
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  # A quiet account link in the navigation: the shell's links recede so the
  # wordmark and the Credit balance are the only things with weight up there.
  # Never wrapped — the cluster wraps as a row on a phone, but "Log out" broken
  # across two lines just looks like a mistake.
  attr :rest, :global, include: ~w(href method)
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link class="rounded-field px-2 py-1 whitespace-nowrap hover:text-base-content" {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <%!-- The two connection toasts every tester eventually sees. Stock
      phx.new writes them as "We can't find the internet" and "Something went
      wrong!"; in this product's voice they say which end broke and that the
      Review is not what is at risk — Action Points live on the server, so a
      dropped socket loses a connection, never curation. --%>
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("You've gone offline")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting — your Review is kept")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Lost the connection at our end")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting — your Review is kept")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      class="relative ml-1 flex flex-row items-center rounded-full border border-base-300 bg-base-200"
      role="group"
      aria-label="Theme"
    >
      <div class="absolute left-0 h-full w-1/3 rounded-full bg-base-300 transition-[left] [[data-theme=dark]_&]:left-2/3 [[data-theme=light]_&]:left-1/3" />

      <button
        type="button"
        class="relative flex w-1/3 cursor-pointer p-1.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Follow system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-3.5 opacity-70 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="relative flex w-1/3 cursor-pointer p-1.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-3.5 opacity-70 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="relative flex w-1/3 cursor-pointer p-1.5"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-3.5 opacity-70 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
