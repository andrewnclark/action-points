defmodule ActionPointsWeb.HomeLive do
  @moduledoc """
  Landing page: paste a Transcript, kick off an Extraction, land on Review.
  Works without an account — the Extraction is keyed to the anonymous session.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.Extraction

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl">
        <div class="pt-10 pb-8 text-center">
          <h1 class="text-4xl font-bold">Turn a meeting transcript into tasks</h1>
          <p class="mt-4 text-lg text-base-content/70">
            Paste the transcript. Review the extracted Action Points. Push the keepers to Linear.
          </p>
        </div>

        <.form for={@form} id="transcript-form" phx-submit="extract">
          <.input
            field={@form[:transcript_text]}
            type="textarea"
            rows="12"
            placeholder="Paste your meeting transcript here — straight from Zoom, Teams, or Meet…"
            aria-label="Meeting transcript"
          />
          <button class="btn btn-primary w-full mt-4" phx-disable-with="Starting…">
            Extract Action Points
          </button>
        </.form>

        <p class="mt-6 text-center text-sm text-base-content/50">
          Your transcript is used only to produce your Action Points — never shared.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:session_token, session["anon_session_token"])
     |> assign_form(Meetings.change_extraction(%Extraction{}))}
  end

  @impl true
  def handle_event("extract", %{"extraction" => params}, socket) do
    case Meetings.create_extraction(socket.assigns.session_token, params) do
      {:ok, extraction} ->
        Meetings.start_extraction(extraction)
        {:noreply, push_navigate(socket, to: ~p"/review/#{extraction}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
