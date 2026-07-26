defmodule ActionPointsWeb.ReviewLive do
  @moduledoc """
  The Review screen: live Extraction progress, then the Action Points to
  curate. Only the session that created the Extraction can see it.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Meetings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl">
        <%= case @extraction.status do %>
          <% status when status in [:pending, :running] -> %>
            <div id="extraction-progress" class="py-24 text-center">
              <span class="loading loading-dots loading-lg" aria-hidden="true"></span>
              <h1 class="mt-6 text-2xl font-semibold">Extracting Action Points…</h1>
              <p class="mt-2 text-base-content/70">
                Reading your transcript. This can take up to a minute for long meetings.
              </p>
            </div>
          <% :failed -> %>
            <div id="extraction-failed" class="py-24 text-center">
              <.icon name="hero-exclamation-triangle" class="size-10 text-error" />
              <h1 class="mt-4 text-2xl font-semibold">The Extraction failed</h1>
              <p class="mt-2 text-base-content/70">
                Nothing was charged. This is usually temporary — try again.
              </p>
              <button id="retry-extraction" class="btn btn-primary mt-6" phx-click="retry">
                Retry Extraction
              </button>
            </div>
          <% :succeeded -> %>
            <div class="pt-6 pb-4">
              <h1 class="text-2xl font-bold">Review your Action Points</h1>
              <p class="mt-1 text-base-content/70">
                {ngettext(
                  "1 Action Point extracted from your transcript.",
                  "%{count} Action Points extracted from your transcript.",
                  @action_point_count
                )}
              </p>
            </div>

            <ul id="action-points" phx-update="stream" class="space-y-4">
              <li
                :for={{dom_id, action_point} <- @streams.action_points}
                id={dom_id}
                class="card bg-base-200 p-5"
              >
                <h2 class="font-semibold">{action_point.title}</h2>
                <p :if={action_point.description} class="mt-1 text-sm text-base-content/80">
                  {action_point.description}
                </p>
                <div class="mt-3 flex flex-wrap gap-2 text-sm">
                  <span :if={action_point.assignee_guess} class="badge badge-outline gap-1">
                    <.icon name="hero-user-micro" class="size-3" />
                    {action_point.assignee_guess}
                  </span>
                  <span :if={action_point.due_date} class="badge badge-outline gap-1">
                    <.icon name="hero-calendar-micro" class="size-3" />
                    {action_point.due_date}
                  </span>
                </div>
              </li>
            </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, session, socket) do
    # Subscribe before fetching so a status change can't slip in between —
    # otherwise the spinner could hang on an update we never hear about.
    if connected?(socket), do: Meetings.subscribe(id)

    extraction = Meetings.get_extraction!(id, session["anon_session_token"])

    {:ok, assign_extraction(socket, extraction)}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    %{id: id, session_token: session_token} = socket.assigns.extraction
    Meetings.retry_extraction(socket.assigns.extraction)
    {:noreply, assign_extraction(socket, Meetings.get_extraction!(id, session_token))}
  end

  @impl true
  def handle_info({:extraction_updated, _id}, socket) do
    %{id: id, session_token: session_token} = socket.assigns.extraction
    {:noreply, assign_extraction(socket, Meetings.get_extraction!(id, session_token))}
  end

  defp assign_extraction(socket, extraction) do
    socket
    |> assign(:extraction, %{extraction | action_points: []})
    |> assign(:action_point_count, length(extraction.action_points))
    |> stream(:action_points, extraction.action_points, reset: true)
  end
end
