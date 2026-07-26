defmodule ActionPointsWeb.ReviewLive do
  @moduledoc """
  The Review screen: live Extraction progress, then the Action Points to
  curate. Only the session that created the Extraction can see it.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Billing
  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-3xl">
      <div>
        <%= case @extraction.status do %>
          <% status when status in [:pending, :running] -> %>
            <%!-- Waiting is a screen, not an interstitial: it names the step
            running, shows the run is alive, and says what it will cost. --%>
            <.status_card id="extraction-progress">
              <span class="inline-flex items-center gap-2 text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
                <span
                  class="size-1.5 rounded-full bg-primary motion-safe:animate-pulse"
                  aria-hidden="true"
                /> Extraction running
              </span>
              <h1 class="mt-3 text-2xl font-semibold">Extracting Action Points</h1>
              <p class="mt-2 text-base-content/70">
                Reading your Transcript. A long meeting can take up to a minute.
              </p>
              <div
                class="sweep mt-6 h-1 rounded-full"
                role="progressbar"
                aria-label="Extraction in progress"
              />
              <:footnote>
                {if @current_scope,
                  do: "A Credit is spent only if the Extraction succeeds.",
                  else: "The Demo is free — nothing is charged either way."}
              </:footnote>
            </.status_card>
          <% :failed -> %>
            <%!-- A failure is where trust is won or lost: say what happened, say
            it cost nothing, and put the next move under the reader's hand. --%>
            <.status_card id="extraction-failed">
              <span class="mx-auto grid size-10 place-items-center rounded-box border border-error/40 bg-error/10">
                <.icon name="hero-exclamation-triangle" class="size-5 text-error" />
              </span>
              <h1 class="mt-4 text-2xl font-semibold">The Extraction failed</h1>
              <p class="mt-2 text-base-content/70">
                {failure_reason(@extraction.failure_reason)}
              </p>
              <div class="mt-6 flex flex-wrap justify-center gap-2">
                <button id="retry-extraction" class="btn btn-primary btn-sm" phx-click="retry">
                  <.icon name="hero-arrow-path" class="size-4" /> Retry Extraction
                </button>
                <.link navigate={~p"/"} class="btn btn-ghost btn-sm text-base-content/70">
                  Start over
                </.link>
              </div>
              <:footnote>
                No Credit was spent — a Credit is only ever consumed by an Extraction
                that succeeds.
              </:footnote>
            </.status_card>
          <% :succeeded when @action_point_count == 0 -> %>
            <div id="review-empty" class="py-24 text-center">
              <h1 class="text-2xl font-semibold">No Action Points in this Transcript</h1>
              <p class="mx-auto mt-2 max-w-md text-base-content/70">
                The Extraction read the whole thing and found nothing anyone committed to.
                Some meetings really are just talking.
              </p>
              <.link navigate={~p"/"} class="btn btn-primary mt-6">
                Extract another Transcript
              </.link>
              <p :if={@current_scope} class="mt-4 text-xs text-base-content/65">
                This Extraction succeeded, so it used a Credit.
              </p>
            </div>
          <% :succeeded -> %>
            <div class="pt-8 pb-4">
              <span class="text-[11px] tracking-[0.08em] text-base-content/65 uppercase">
                Extraction · {Calendar.strftime(@extraction.inserted_at, "%-d %b %Y")}
              </span>
              <h1 class="mt-2 text-2xl font-semibold">Review your Action Points</h1>
              <p class="mt-1 text-base-content/70">
                {ngettext(
                  "1 Action Point extracted from your Transcript.",
                  "%{count} Action Points extracted from your Transcript.",
                  @action_point_count
                )}
              </p>
            </div>

            <%!-- The tally and the promise sit together: the counts say where the
            curation has got to, the line beside them says it is still reversible. --%>
            <div
              id="review-toolbar"
              class="mb-4 flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-base-300/60 pb-3 text-xs text-base-content/65"
            >
              <span class="inline-flex items-center gap-1.5">
                <span class="size-1.5 rounded-full bg-primary" aria-hidden="true"></span>
                {@action_point_count - @rejected_count} accepted
              </span>
              <span :if={@rejected_count > 0} class="inline-flex items-center gap-1.5">
                <span class="size-1.5 rounded-full bg-base-content/40" aria-hidden="true"></span>
                {@rejected_count} rejected
              </span>
              <span :if={@pushable_count > 0} class="ml-auto">
                Nothing is created in Linear until you Push.
              </span>
            </div>

            <div
              :if={@push_failure}
              id="push-failure"
              class="mb-4 flex gap-3 rounded-box border border-error/40 bg-error/10 p-4"
              role="alert"
            >
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-error" />
              <div>
                <p class="font-semibold">
                  The Push stopped partway: {@push_failure.created} created, {@push_failure.remaining} not created.
                </p>
                <p class="mt-1 text-base-content/70">
                  {push_failure_reason(@push_failure.reason)} Pushing again creates only the missing ones — never a duplicate.
                </p>
              </div>
            </div>

            <div
              :if={@pushed_action_points != [] and @pushable_count == 0 and not @pushing?}
              id="push-confirmation"
              class="mb-4 flex gap-3 rounded-box border border-success/40 bg-success/10 p-4"
            >
              <.icon name="hero-check-circle" class="size-5 shrink-0 text-success" />
              <div class="min-w-0">
                <p class="font-semibold">
                  {ngettext(
                    "1 task created in Linear.",
                    "%{count} tasks created in Linear.",
                    length(@pushed_action_points)
                  )} That's the meeting dealt with.
                </p>
                <ul class="mt-2 space-y-1 text-base-content/70">
                  <li :for={action_point <- @pushed_action_points} class="truncate">
                    <a
                      href={action_point.sink_issue_url}
                      target="_blank"
                      rel="noopener"
                      class="text-accent hover:underline"
                    >
                      <span class="font-medium">{action_point.sink_issue_identifier}</span>
                      — {action_point.title}
                    </a>
                  </li>
                </ul>
              </div>
            </div>

            <ul id="action-points" phx-update="stream" class="space-y-2">
              <li
                :for={{dom_id, action_point} <- @streams.action_points}
                id={dom_id}
                data-status={action_point.status}
                class={[
                  "group relative rounded-box border p-4 transition-colors",
                  card_class(@editing, action_point)
                ]}
              >
                <%= if editing?(@editing, action_point) do %>
                  <%!-- Editing is a different mode, and the card says so out loud
                  rather than relying on the reader spotting the inputs. --%>
                  <span class="absolute -top-2.5 left-3 rounded-[3px] bg-primary px-1.5 py-0.5 text-[10px] font-semibold tracking-[0.09em] text-primary-content uppercase">
                    Editing
                  </span>
                  <.form
                    for={@edit_form}
                    id={"edit-#{dom_id}"}
                    phx-submit="save_edit"
                    class="space-y-1"
                  >
                    <.input field={@edit_form[:title]} type="text" label="Title" />
                    <.input
                      field={@edit_form[:description]}
                      type="textarea"
                      rows="3"
                      label="Description"
                    />
                    <div class="grid gap-x-3 sm:grid-cols-2">
                      <.input
                        field={@edit_form[:assignee_guess]}
                        type="text"
                        label="Assignee"
                        placeholder="Unassigned"
                      />
                      <.input field={@edit_form[:due_date]} type="date" label="Due date" />
                    </div>
                    <div class="flex justify-end gap-2 pt-1">
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
                      "leading-snug font-semibold",
                      action_point.status == :rejected && "text-base-content/65 line-through"
                    ]}>
                      {action_point.title}
                    </h2>
                    <div class="flex shrink-0 gap-0.5 opacity-60 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                      <%= cond do %>
                        <% action_point.sink_issue_id -> %>
                          <a
                            data-role="sink-issue"
                            href={action_point.sink_issue_url}
                            target="_blank"
                            rel="noopener"
                            class="inline-flex items-center gap-1 rounded-field border border-success/40 bg-success/10 px-2 py-0.5 text-xs font-medium text-success"
                            title="Created in your Task Sink"
                          >
                            <.icon name="hero-check-micro" class="size-3" />
                            {action_point.sink_issue_identifier}
                          </a>
                        <% action_point.status == :accepted -> %>
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
                        <% true -> %>
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
                  <p
                    :if={action_point.description}
                    class={[
                      "mt-1.5",
                      (action_point.status == :rejected && "text-base-content/65") ||
                        "text-base-content/70"
                    ]}
                  >
                    {action_point.description}
                  </p>
                  <div class="mt-3 flex flex-wrap gap-1.5">
                    <.chip :if={action_point.assignee_guess} role="assignee" icon="hero-user-micro">
                      {action_point.assignee_guess}
                    </.chip>
                    <.chip
                      :if={action_point.due_date}
                      role="due-date"
                      icon="hero-calendar-micro"
                    >
                      {Calendar.strftime(action_point.due_date, "%-d %b %Y")}
                    </.chip>
                    <%!-- A missing due date is stated, not left blank: the model
                    heard no date, which is different from nobody having looked. --%>
                    <.chip
                      :if={is_nil(action_point.due_date)}
                      role="no-due-date"
                      icon="hero-calendar-micro"
                      empty
                    >
                      No due date
                    </.chip>
                  </div>
                <% end %>
              </li>
            </ul>

            <div
              :if={@pushable_count > 0 or @pushed_action_points == []}
              class="sticky bottom-0 mt-4 flex flex-wrap items-center gap-3 rounded-box border border-base-300 bg-base-200/95 p-3 backdrop-blur"
            >
              <%!-- With nothing accepted the bar has no count worth stating, so
              it names the way out instead of reading "0 Action Points ready". --%>
              <p class="text-base-content/70">
                <%= if @pushable_count > 0 do %>
                  <span class="font-semibold text-base-content">{@pushable_count}</span>
                  {ngettext("Action Point ready", "Action Points ready", @pushable_count)} · pushing to Linear
                <% else %>
                  Nothing accepted yet. Accept an Action Point to Push it.
                <% end %>
              </p>
              <button
                id="push-button"
                class="btn btn-primary ml-auto"
                phx-click="push"
                disabled={@pushing? or @pushable_count == 0}
              >
                <%= cond do %>
                  <% @pushing? -> %>
                    <span class="loading loading-spinner loading-xs" aria-hidden="true"></span>
                    Pushing…
                  <% is_nil(@current_scope) -> %>
                    <%!-- The paywall boundary, stated up front: Pushing needs an
                    account, and clicking here routes to signup with the Review kept. --%>
                    <.icon name="hero-paper-airplane" class="size-4" />
                    {ngettext(
                      "Sign up to Push 1 Action Point",
                      "Sign up to Push %{count} Action Points",
                      @pushable_count
                    )}
                  <% true -> %>
                    <.icon name="hero-paper-airplane" class="size-4" />
                    {ngettext("Push 1 Action Point", "Push %{count} Action Points", @pushable_count)}
                <% end %>
              </button>
            </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # The Extraction's waiting and failed screens are one designed pair — the two
  # ways a run can be found in progress — so they share their chrome: the same
  # panel, and a footnote below a divider that always says what the run cost.
  attr :id, :string, required: true
  slot :inner_block, required: true
  slot :footnote, required: true

  defp status_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="mx-auto mt-16 max-w-md rounded-box border border-base-300 bg-base-200 p-8 text-center"
    >
      {render_slot(@inner_block)}
      <p class="mt-6 border-t border-base-300/60 pt-4 text-xs text-base-content/65">
        {render_slot(@footnote)}
      </p>
    </div>
    """
  end

  # One Action Point's metadata: assignee, due date, or the absence of a due
  # date, which is drawn dashed because it states a fact rather than carrying one.
  attr :role, :string, required: true, doc: "the data-role hook tests select on"
  attr :icon, :string, required: true
  attr :empty, :boolean, default: false, doc: "styles the chip as a stated absence"
  slot :inner_block, required: true

  defp chip(assigns) do
    ~H"""
    <span
      data-role={@role}
      class={[
        "inline-flex items-center gap-1.5 rounded-field border border-base-300 px-2 py-0.5 text-xs",
        (@empty && "border-dashed text-base-content/65") || "text-base-content/70"
      ]}
    >
      <.icon name={@icon} class={if @empty, do: "size-3", else: "size-3 text-base-content/65"} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp editing?(nil, _action_point), do: false
  defp editing?(editing, action_point), do: editing.id == action_point.id

  # Reading, rejected, and editing are three visibly different cards: a rejected
  # one drops out of the surface entirely, an editing one is lifted onto it.
  defp card_class(editing, action_point) do
    cond do
      # A tinted ring rather than a drop shadow: the tokens set --depth: 0, so
      # surfaces here separate by value and not by elevation, and a black
      # shadow tuned for the dark canvas would read as grime on the light one.
      editing?(editing, action_point) ->
        "border-primary bg-base-300 ring-1 ring-primary/30"

      action_point.status == :rejected ->
        "border-dashed border-base-300 bg-transparent"

      true ->
        "border-base-300/60 bg-base-200 hover:border-base-300"
    end
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

  def handle_event("push", _params, socket) do
    scope = socket.assigns.current_scope

    cond do
      # The button disables while pushing, but a queued double-click still
      # lands here — it must not start a second Push.
      socket.assigns.pushing? ->
        {:noreply, socket}

      is_nil(scope) ->
        {:noreply,
         socket
         |> put_flash(:info, "Create a free account to Push — your Review is saved.")
         |> push_navigate(to: ~p"/users/register")}

      is_nil(Sinks.get_connection(scope)) ->
        {:noreply,
         socket
         |> put_flash(:info, "Connect Linear to Push your Action Points.")
         |> push_navigate(to: ~p"/settings/sink")}

      true ->
        extraction = socket.assigns.extraction

        {:noreply,
         socket
         |> assign(:pushing?, true)
         |> assign(:push_failure, nil)
         |> start_async(:push, fn -> Sinks.push(scope, extraction) end)}
    end
  end

  def handle_event("retry", _params, socket) do
    case Meetings.retry_extraction(socket.assigns.extraction) do
      :ok ->
        {:noreply, assign_extraction(socket, refetch_extraction(socket))}

      {:error, :out_of_credits} ->
        {:noreply,
         socket
         |> put_flash(:error, "You're out of Credits — a Pack covers your next 15 meetings.")
         |> push_navigate(to: ~p"/buy")}
    end
  end

  @impl true
  def handle_async(:push, {:ok, result}, socket) do
    socket = assign_extraction(socket, refetch_extraction(socket))

    case result do
      {:ok, pushed} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           ngettext(
             "Pushed 1 Action Point to Linear.",
             "Pushed %{count} Action Points to Linear.",
             length(pushed)
           )
         )}

      {:error, :not_connected} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connect Linear to Push your Action Points.")
         |> push_navigate(to: ~p"/settings/sink")}

      {:error, :push_in_progress} ->
        {:noreply,
         put_flash(socket, :error, "A Push of this Review is already running — give it a moment.")}

      {:error, {reason, pushed, remaining}} ->
        {:noreply,
         assign(socket, :push_failure, %{
           reason: reason,
           created: length(pushed),
           remaining: remaining
         })}
    end
  end

  def handle_async(:push, {:exit, _reason}, socket) do
    # Even a crashed Push recorded each issue it created before dying, so a
    # fresh fetch shows the true split and pushing again stays duplicate-free.
    socket = assign_extraction(socket, refetch_extraction(socket))

    {:noreply,
     assign(socket, :push_failure, %{
       reason: :api_error,
       created: length(socket.assigns.pushed_action_points),
       remaining: socket.assigns.pushable_count
     })}
  end

  @impl true
  def handle_info({:extraction_updated, _id}, socket) do
    # Success just consumed a Credit, so the nav balance must follow.
    {:noreply,
     socket
     |> refresh_credit_balance()
     |> assign_extraction(refetch_extraction(socket))}
  end

  defp refresh_credit_balance(socket) do
    case socket.assigns.current_scope do
      nil -> socket
      scope -> assign(socket, :current_scope, Billing.with_balance(scope))
    end
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
    |> assign(:pushable_count, Meetings.count_pushable_action_points(action_point.extraction_id))
    |> assign(:rejected_count, Meetings.count_rejected_action_points(action_point.extraction_id))
    |> stream_insert(:action_points, action_point)
  end

  defp assign_extraction(socket, extraction) do
    action_points = extraction.action_points

    socket
    |> assign(:extraction, %{extraction | action_points: []})
    |> assign(:editing, nil)
    |> assign(:edit_form, nil)
    |> assign(:action_point_count, length(action_points))
    |> assign(:pushable_count, Enum.count(action_points, &Meetings.ActionPoint.pushable?/1))
    |> assign(:rejected_count, Enum.count(action_points, &(&1.status == :rejected)))
    |> assign(:pushed_action_points, Enum.filter(action_points, & &1.sink_issue_id))
    |> assign(:pushing?, false)
    |> assign(:push_failure, nil)
    |> stream(:action_points, action_points, reset: true)
  end

  defp refetch_extraction(socket) do
    %{id: id, session_token: session_token} = socket.assigns.extraction
    Meetings.get_extraction!(id, session_token)
  end

  # What went wrong, in the reader's terms. Only the causes that change the
  # reader's next move are named; the rest share the "try again" wording,
  # because a visitor cannot act on the difference between a 500 and a crash.
  defp failure_reason("truncated"),
    do:
      "That meeting produced more Action Points than one Extraction can return. Splitting the Transcript in two and running each half gets all of them."

  defp failure_reason("rate_limited"),
    do: "The extraction service is busy right now. Give it a minute and run it again."

  defp failure_reason("refused"),
    do:
      "The model would not process that Transcript. If it holds anything sensitive, trimming that part and running it again usually works."

  defp failure_reason(_reason),
    do: "Something went wrong on our side. This is usually temporary — run it again."

  defp push_failure_reason(:invalid_key),
    do: "Linear rejected the connected API key — check it in settings."

  defp push_failure_reason(:rate_limited),
    do: "Linear rate-limited the Push — give it a minute."

  defp push_failure_reason(_reason),
    do: "Linear could not be reached."
end
