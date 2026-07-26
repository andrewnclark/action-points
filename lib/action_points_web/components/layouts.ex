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
      <nav class="mx-auto flex h-13 max-w-[1180px] items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <.link
          navigate={~p"/"}
          class="flex w-fit items-center gap-2 font-semibold tracking-[-0.02em]"
        >
          <span
            class="grid size-[18px] place-items-center rounded-[4px] bg-linear-to-br from-accent to-primary text-[11px] font-bold text-base-100"
            aria-hidden="true"
          >
            ▲
          </span>
          ActionPoints
        </.link>

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

  # A quiet account link in the navigation: the shell's links recede so the
  # wordmark and the Credit balance are the only things with weight up there.
  attr :rest, :global, include: ~w(href method)
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link class="rounded-field px-2 py-1 hover:text-base-content" {@rest}>
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

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
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
