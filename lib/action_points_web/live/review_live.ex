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
            <div class="flex flex-wrap items-end justify-between gap-4 pt-6 pb-4">
              <div>
                <h1 class="text-2xl font-bold">Review your Action Points</h1>
                <p class="mt-1 text-base-content/70">
                  {ngettext(
                    "1 Action Point extracted from your transcript.",
                    "%{count} Action Points extracted from your transcript.",
                    @action_point_count
                  )}
                </p>
              </div>
              <button
                id="push-button"
                class="btn btn-primary"
                disabled
                title="Push is coming soon"
              >
                <.icon name="hero-paper-airplane" class="size-4" />
                {ngettext("Push 1 Action Point", "Push %{count} Action Points", @accepted_count)}
              </button>
            </div>

            <ul id="action-points" phx-update="stream" class="space-y-4">
              <li
                :for={{dom_id, action_point} <- @streams.action_points}
                id={dom_id}
                data-status={action_point.status}
                class={[
                  "card bg-base-200 p-5 transition-opacity",
                  action_point.status == :rejected && "opacity-50"
                ]}
              >
                <%= if @editing && @editing.id == action_point.id do %>
                  <.form
                    for={@edit_form}
                    id={"edit-#{dom_id}"}
                    phx-submit="save_edit"
                    class="space-y-3"
                  >
                    <.input field={@edit_form[:title]} type="text" label="Title" />
                    <.input
                      field={@edit_form[:description]}
                      type="textarea"
                      rows="3"
                      label="Description"
                    />
                    <div class="grid grid-cols-2 gap-3">
                      <.input
                        field={@edit_form[:assignee_guess]}
                        type="text"
                        label="Assignee"
                        placeholder="Unassigned"
                      />
                      <.input field={@edit_form[:due_date]} type="date" label="Due date" />
                    </div>
                    <div class="flex justify-end gap-2">
                      <button
                        id={"#{dom_id}-cancel"}
                        type="button"
                        class="btn btn-ghost btn-sm"
                        phx-click="cancel_edit"
                      >
                        Cancel
                      </button>
                      <button id={"#{dom_id}-save"} class="btn btn-primary btn-sm">Save</button>
                    </div>
                  </.form>
                <% else %>
                  <div class="flex items-start justify-between gap-3">
                    <h2 class={[
                      "font-semibold",
                      action_point.status == :rejected && "line-through"
                    ]}>
                      {action_point.title}
                    </h2>
                    <div class="flex shrink-0 gap-1">
                      <%= if action_point.status == :accepted do %>
                        <button
                          id={"#{dom_id}-edit"}
                          phx-click="edit"
                          phx-value-id={action_point.id}
                          class="btn btn-ghost btn-xs"
                          title="Edit this Action Point"
                        >
                          <.icon name="hero-pencil-square-micro" class="size-3.5" /> Edit
                        </button>
                        <button
                          id={"#{dom_id}-reject"}
                          phx-click="reject"
                          phx-value-id={action_point.id}
                          class="btn btn-ghost btn-xs"
                          title="Reject this Action Point"
                        >
                          <.icon name="hero-x-mark-micro" class="size-3.5" /> Reject
                        </button>
                      <% else %>
                        <button
                          id={"#{dom_id}-accept"}
                          phx-click="accept"
                          phx-value-id={action_point.id}
                          class="btn btn-outline btn-xs"
                          title="Accept this Action Point again"
                        >
                          <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Accept
                        </button>
                      <% end %>
                    </div>
                  </div>
                  <p :if={action_point.description} class="mt-1 text-sm text-base-content/80">
                    {action_point.description}
                  </p>
                  <div class="mt-3 flex flex-wrap gap-2 text-sm">
                    <span
                      :if={action_point.assignee_guess}
                      data-role="assignee"
                      class="badge badge-outline gap-1"
                    >
                      <.icon name="hero-user-micro" class="size-3" />
                      {action_point.assignee_guess}
                    </span>
                    <span
                      :if={action_point.due_date}
                      data-role="due-date"
                      class="badge badge-outline gap-1"
                    >
                      <.icon name="hero-calendar-micro" class="size-3" />
                      {action_point.due_date}
                    </span>
                  </div>
                <% end %>
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
  def handle_event("reject", %{"id" => id}, socket) do
    {:noreply, set_status(socket, id, :rejected)}
  end

  def handle_event("accept", %{"id" => id}, socket) do
    {:noreply, set_status(socket, id, :accepted)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    action_point = Meetings.get_action_point!(id, socket.assigns.extraction.session_token)

    {:noreply,
     socket
     |> close_editor()
     |> assign(:editing, action_point)
     |> assign(:edit_form, to_form(Meetings.change_action_point(action_point)))
     |> stream_insert(:action_points, action_point)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, close_editor(socket)}
  end

  def handle_event("save_edit", %{"action_point" => params}, socket) do
    case socket.assigns.editing do
      # A stray submit after the editor closed (e.g. a double click) is a no-op.
      nil ->
        {:noreply, socket}

      editing ->
        case Meetings.update_action_point(editing, params) do
          {:ok, action_point} ->
            {:noreply,
             socket
             |> assign(:editing, nil)
             |> refresh_action_point(action_point)}

          {:error, changeset} ->
            # Re-insert the card — stream items only re-render when
            # re-inserted, and the form must show its errors.
            {:noreply,
             socket
             |> assign(:edit_form, to_form(changeset))
             |> stream_insert(:action_points, editing)}
        end
    end
  end

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

  defp close_editor(socket) do
    case socket.assigns.editing do
      nil ->
        socket

      action_point ->
        socket
        |> assign(:editing, nil)
        # Re-insert so the card re-renders back in display mode.
        |> stream_insert(:action_points, action_point)
    end
  end

  defp set_status(socket, id, status) do
    action_point =
      id
      |> Meetings.get_action_point!(socket.assigns.extraction.session_token)
      |> Meetings.set_action_point_status(status)

    refresh_action_point(socket, action_point)
  end

  # Patches one card in place and recounts — a full re-stream would wipe
  # transient UI state on the other cards.
  defp refresh_action_point(socket, action_point) do
    socket
    |> assign(:accepted_count, Meetings.count_accepted_action_points(action_point.extraction_id))
    |> stream_insert(:action_points, action_point)
  end

  defp assign_extraction(socket, extraction) do
    socket
    |> assign(:extraction, %{extraction | action_points: []})
    |> assign(:editing, nil)
    |> assign(:edit_form, nil)
    |> assign(:action_point_count, length(extraction.action_points))
    |> assign(:accepted_count, Meetings.count_accepted_action_points(extraction.id))
    |> stream(:action_points, extraction.action_points, reset: true)
  end
end
