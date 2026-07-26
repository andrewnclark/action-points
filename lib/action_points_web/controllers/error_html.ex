defmodule ActionPointsWeb.ErrorHTML do
  @moduledoc """
  The pages for requests that never reach a screen.

  Phoenix ships these as bare status text — "Not Found" on a white page — which
  after the facelift would be the one place the old scaffold still showed. They
  are real pages of the design system instead, wrapped in the root layout
  (`:render_errors` in `config/config.exs`) so the stylesheet and the theme
  script arrive with them.

  What they must survive shapes them: a 500 can mean the database is gone and a
  404 has no `current_scope`, so these pages read nothing from assigns, run no
  queries, and use the app shell not at all. Only the wordmark is shared, and
  every status lands on a designed page rather than falling back to a word.

  See config/config.exs.
  """
  use ActionPointsWeb, :html

  # `assigns = %{}` before each ~H: the incoming assigns are deliberately
  # dropped (see the moduledoc), and Phoenix hands this a keyword list rather
  # than a map, which ~H cannot take.
  def render("404.html", _assigns) do
    assigns = %{}

    ~H"""
    <.error_page
      code="404"
      title="That page isn't here."
      lead="The link may be old, or the address off by a character. Nothing is broken."
    />
    """
  end

  def render("500.html", _assigns) do
    assigns = %{}

    ~H"""
    <.error_page
      code="500"
      title="Something broke at our end."
      lead="The failure is logged and it's ours to fix. Reloading is safe to try."
    />
    """
  end

  # Every other status the endpoint can raise. Rare enough to have no copy of
  # its own, but it still arrives as a page rather than as a word.
  def render(template, _assigns) do
    assigns = %{
      code: Path.rootname(template),
      title: Phoenix.Controller.status_message_from_template(template) <> "."
    }

    ~H"""
    <.error_page
      code={@code}
      title={@title}
      lead="The request didn't get through. Reloading is safe to try."
    />
    """
  end

  # The shape the pages share: the wordmark to prove where you still are, the
  # status stated plainly, and one way onward.
  attr :code, :string, required: true
  attr :title, :string, required: true
  attr :lead, :string, required: true

  defp error_page(assigns) do
    ~H"""
    <main id="error-page" class="grid min-h-svh place-items-center px-6 py-16">
      <div class="w-full max-w-md text-center">
        <Layouts.wordmark href={~p"/"} class="mx-auto" />

        <span class="mt-10 inline-flex items-center gap-2 rounded-full border border-base-300 px-3 py-1 text-[11px] font-medium tracking-[0.07em] text-base-content/65 uppercase">
          <span
            class="size-1.5 rounded-full bg-base-content/30 ring-3 ring-base-content/10"
            aria-hidden="true"
          />
          {@code}
        </span>

        <h1 class="mt-5 text-3xl font-semibold tracking-[-0.03em]">{@title}</h1>
        <p class="mt-3 text-base-content/70">{@lead}</p>

        <.link id="error-page-home" href={~p"/"} class="btn btn-primary btn-sm mt-6">
          Back to the start
        </.link>
      </div>
    </main>
    """
  end
end
