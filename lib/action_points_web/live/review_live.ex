defmodule ActionPointsWeb.ReviewLive do
  @moduledoc """
  The Review screen: live Extraction progress, then the Action Points to
  curate. Only the session that created the Extraction can see it.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Billing
  alias ActionPoints.Meetings
  alias ActionPoints.Sinks
  alias ActionPointsWeb.LocalDate

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
              <%!-- The anchor, stated where the dates it produced are read: any
              resolved date traces back to what it was counted from. --%>
              <p id="meeting-date" class="mt-1.5 text-xs text-base-content/65">
                Deadlines resolved relative to
                <span class="font-medium text-base-content/80">
                  {Calendar.strftime(@extraction.meeting_date, "%a %-d %b")}
                </span>
                ({meeting_date_source_label(@extraction.meeting_date_source)})
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

            <%!-- A failed member fetch degrades the picker, not the Review: the
            guesses still show as text, but nothing is guessed silently in
            their place (ADR-0007). --%>
            <div
              :if={@assignee_degraded?}
              id="assignee-degraded-notice"
              class="mb-4 flex gap-3 rounded-box border border-warning/40 bg-warning/10 p-4"
              role="alert"
            >
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
              <p class="text-base-content/70">
                Linear's member list couldn't be reached, so guessed names are shown as text below.
                Pushing now leaves them unassigned — reload once Linear is reachable to resolve them.
              </p>
            </div>

            <%!-- A sink without the relation capability gets flat tasks: the
            drop is said here, before Push, never discovered after it. --%>
            <div
              :if={
                @has_blockers and (@sink_live? or @assignee_degraded?) and not @relations_supported?
              }
              id="relations-unsupported-notice"
              class="mb-4 flex gap-3 rounded-box border border-warning/40 bg-warning/10 p-4"
              role="alert"
            >
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
              <p class="text-base-content/70">
                Your Task Sink doesn't support blocked-by relations, so the relations below stay
                here — Pushing creates the tasks without them.
              </p>
            </div>

            <div
              :if={@push_failure}
              id="push-failure"
              class="mb-4 flex gap-3 rounded-box border border-error/40 bg-error/10 p-4"
              role="alert"
            >
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-error" />
              <div>
                <%!-- A Push that never created anything did not stop partway,
                and saying it did sends the reader to Linear looking for a task
                that was never made. Only a split is reported as a split — and
                a relation split is reported as exactly that: every task
                exists, only the ordering between them is missing. --%>
                <p class="font-semibold">
                  <%= cond do %>
                    <% @push_failure.phase == :relations -> %>
                      Every task was created, but the Push stopped partway through the
                      blocked-by relations: {@push_failure.created} created, {@push_failure.remaining} not created.
                    <% @push_failure.created == 0 -> %>
                      The Push didn't go through: nothing was created.
                    <% true -> %>
                      The Push stopped partway: {@push_failure.created} created, {@push_failure.remaining} not created.
                  <% end %>
                </p>
                <p class="mt-1 text-base-content/70">
                  {push_failure_reason(@push_failure.reason)}
                  <%= cond do %>
                    <% @push_failure.phase == :relations -> %>
                      Pushing again creates only the missing relations — never a duplicate.
                    <% @push_failure.created == 0 -> %>
                      Pushing again starts from scratch — nothing is there to duplicate.
                    <% true -> %>
                      Pushing again creates only the missing ones — never a duplicate.
                  <% end %>
                </p>
              </div>
            </div>

            <div
              :if={
                @pushed_action_points != [] and @pushable_count == 0 and
                  @unpushed_relations_count == 0 and not @pushing?
              }
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
                      <%!-- Once the sink is live, the assignee is set from the
                      picker on the card itself, not here — that picker is a
                      real member, and this field would only be raw text. --%>
                      <.input
                        :if={not @sink_live?}
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
                  <%!-- Grounding Quotes: verified human speech, visibly set
                  apart from the model's prose and collapsed so the Review
                  stays scannable. Removable, never editable — an edited
                  quote would no longer be evidence. --%>
                  <details
                    :if={action_point.quotes != []}
                    id={"#{dom_id}-quotes"}
                    data-role="grounding-quotes"
                    class="mt-2"
                  >
                    <summary class="cursor-pointer text-xs text-base-content/65 select-none hover:text-base-content/80">
                      From the meeting · {ngettext(
                        "1 quote",
                        "%{count} quotes",
                        length(action_point.quotes)
                      )}
                    </summary>
                    <ul class="mt-2 space-y-2">
                      <li
                        :for={{quote, index} <- Enum.with_index(action_point.quotes)}
                        class="flex items-start gap-2"
                      >
                        <blockquote class="flex-1 border-l-2 border-base-300 pl-3 text-base-content/70 italic">
                          {quote}
                        </blockquote>
                        <button
                          :if={is_nil(action_point.sink_issue_id)}
                          id={"#{dom_id}-quote-#{index}-remove"}
                          phx-click="remove_quote"
                          phx-value-id={action_point.id}
                          phx-value-index={index}
                          class="btn btn-ghost btn-xs"
                          title="Remove this quote"
                          aria-label="Remove this quote"
                        >
                          <.icon name="hero-x-mark-micro" class="size-3.5" />
                        </button>
                      </li>
                    </ul>
                  </details>
                  <div class="mt-3 flex flex-wrap items-center gap-1.5">
                    <.assignee_field
                      action_point={action_point}
                      sink_users={@sink_users}
                      pickable={@sink_live? and is_nil(action_point.sink_issue_id)}
                    />
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
                    <%!-- Blockers: the ordering the meeting stated, editable
                    until this Action Point is real in the Task Sink. A wrong
                    guess costs one click. --%>
                    <span
                      :for={blocker <- action_point.blockers}
                      data-role="blocker"
                      class="inline-flex items-center gap-1 rounded-field border border-base-300 px-2 py-0.5 text-xs text-base-content/70"
                    >
                      <.icon name="hero-hand-raised-micro" class="size-3 text-base-content/65" />
                      Blocked by:
                      <span class="max-w-[14rem] truncate font-medium">
                        {blocker.blocked_by.title}
                      </span>
                      <%!-- Removable until the relation itself is real in the
                      sink — even when this Action Point's issue already is,
                      or a relation the sink keeps refusing could never be
                      taken back. --%>
                      <button
                        :if={is_nil(blocker.sink_relation_id)}
                        id={"#{dom_id}-blocker-#{blocker.id}-remove"}
                        phx-click="remove_blocker"
                        phx-value-id={blocker.id}
                        class="-mr-0.5 grid place-items-center rounded-[3px] p-0.5 hover:bg-base-300"
                        title="Remove this relation"
                        aria-label="Remove this relation"
                      >
                        <.icon name="hero-x-mark-micro" class="size-3" />
                      </button>
                    </span>
                    <%!-- phx-value-id lives on the form, not the select — same
                    LiveView constraint as the assignee picker above. --%>
                    <%!-- A pushed Action Point can still gain a relation: both
                    issues exist in the sink, so the next Push creates just the
                    edge (the push bar stays alive for exactly that). --%>
                    <form
                      :if={
                        action_point.status == :accepted and
                          blocker_candidates(action_point, @blocker_options) != []
                      }
                      id={"action-point-#{action_point.id}-blocker-form"}
                      phx-change="add_blocker"
                      phx-value-id={action_point.id}
                      class="inline-flex"
                    >
                      <select
                        id={"action-point-#{action_point.id}-blocker-picker"}
                        name="blocked_by_id"
                        data-role="blocker-picker"
                        aria-label="Add a blocked-by relation"
                        class="select select-xs w-auto max-w-[14rem] border-dashed text-base-content/65"
                      >
                        <option value="" selected>+ Blocked by…</option>
                        <option
                          :for={option <- blocker_candidates(action_point, @blocker_options)}
                          value={option.id}
                        >
                          {option.title}
                        </option>
                      </select>
                    </form>
                  </div>
                <% end %>
              </li>
            </ul>

            <div
              :if={
                @pushable_count > 0 or @unpushed_relations_count > 0 or
                  @pushed_action_points == []
              }
              class="sticky bottom-0 mt-4 flex flex-wrap items-center gap-3 rounded-box border border-base-300 bg-base-200/95 p-3 backdrop-blur"
            >
              <%!-- With nothing accepted the bar has no count worth stating, so
              it names the way out instead of reading "0 Action Points ready".
              With only relations left (a relation-phase failure), the bar says
              that — the way back to a complete Push must stay under the hand. --%>
              <p class="text-base-content/70">
                <%= cond do %>
                  <% @pushable_count > 0 -> %>
                    <span class="font-semibold text-base-content">{@pushable_count}</span>
                    {ngettext("Action Point ready", "Action Points ready", @pushable_count)} · pushing to Linear
                  <% @unpushed_relations_count > 0 -> %>
                    <span class="font-semibold text-base-content">{@unpushed_relations_count}</span>
                    {ngettext(
                      "blocked-by relation still to create",
                      "blocked-by relations still to create",
                      @unpushed_relations_count
                    )} · pushing to Linear
                  <% true -> %>
                    Nothing accepted yet. Accept an Action Point to Push it.
                <% end %>
              </p>
              <button
                id="push-button"
                class="btn btn-primary ml-auto"
                phx-click="push"
                disabled={@pushing? or (@pushable_count == 0 and @unpushed_relations_count == 0)}
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
                  <% @pushable_count == 0 -> %>
                    <.icon name="hero-paper-airplane" class="size-4" />
                    {ngettext(
                      "Push 1 missing relation",
                      "Push %{count} missing relations",
                      @unpushed_relations_count
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

  # One Action Point's assignee: a live picker once the sink is connected and
  # reachable and the Action Point isn't pushed yet, otherwise a static chip
  # — the resolved member if Review has settled one, the raw guess if it
  # never got the chance to (no connection, or a degraded fetch), or nothing
  # at all when there was never a guess. Nothing is guessed silently: an
  # ambiguous or unmatched guess reads as "Unassigned" once resolved, never
  # as the raw name pretending to be a real pick.
  attr :action_point, :map, required: true
  attr :sink_users, :list, required: true
  attr :pickable, :boolean, required: true

  defp assignee_field(assigns) do
    ~H"""
    <%= cond do %>
      <% @pickable -> %>
        <%!-- phx-value-id lives on the form, not the select: LiveView only
        merges phx-value-* for a `change` targeting a form element, not a
        bare input. --%>
        <form
          id={"action-point-#{@action_point.id}-assignee-form"}
          phx-change="pick_assignee"
          phx-value-id={@action_point.id}
          class="inline-flex items-center gap-1.5"
        >
          <select
            id={"action-point-#{@action_point.id}-assignee"}
            name="sink_user_id"
            data-role="assignee-picker"
            class="select select-xs w-auto max-w-[16rem]"
          >
            <option value="" selected={is_nil(@action_point.assignee_sink_user_id)}>
              Unassigned — pick a member
            </option>
            <option
              :for={user <- @sink_users}
              value={user.id}
              selected={@action_point.assignee_sink_user_id == user.id}
            >
              {user.name} (@{user.handle})
            </option>
          </select>
          <span
            :if={@action_point.assignee_resolution == :suggested}
            data-role="assignee-suggested"
            class="rounded-[3px] bg-primary/10 px-1.5 py-0.5 text-[10px] font-semibold tracking-[0.05em] text-primary uppercase"
          >
            Suggested
          </span>
        </form>
      <% @action_point.assignee_resolution && @action_point.assignee_sink_user_id -> %>
        <.chip role="assignee" icon="hero-user-micro">
          {@action_point.assignee_display_name}
        </.chip>
      <% @action_point.assignee_resolution -> %>
        <.chip role="assignee" icon="hero-user-micro" empty>Unassigned</.chip>
      <% @action_point.assignee_guess -> %>
        <.chip role="assignee" icon="hero-user-micro">{@action_point.assignee_guess}</.chip>
      <% true -> %>
    <% end %>
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

    {:ok,
     socket
     |> assign(:local_date, LocalDate.from_connect_params(socket))
     |> assign_resolved_extraction(connected?(socket), extraction)}
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:noreply, set_status(socket, id, :rejected)}
  end

  def handle_event("accept", %{"id" => id}, socket) do
    {:noreply, set_status(socket, id, :accepted)}
  end

  def handle_event("remove_quote", %{"id" => id, "index" => index}, socket) do
    action_point =
      id
      |> Meetings.get_action_point!(socket.assigns.extraction.session_token)
      |> Meetings.remove_action_point_quote(String.to_integer(index))

    {:noreply, refresh_action_point(socket, action_point)}
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
          {:ok, _action_point} ->
            # A retitle changes the "Blocked by" chips and pickers naming this
            # Action Point on other cards — refresh them all.
            {:noreply,
             socket
             |> assign(:editing, nil)
             |> refresh_all_action_points()}

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

  def handle_event("remove_blocker", %{"id" => id}, socket) do
    id
    |> Meetings.get_blocker!(socket.assigns.extraction.session_token)
    |> Meetings.remove_action_point_blocker()

    {:noreply, refresh_all_action_points(socket)}
  end

  def handle_event("add_blocker", %{"blocked_by_id" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("add_blocker", %{"id" => id, "blocked_by_id" => blocked_by_id}, socket) do
    session_token = socket.assigns.extraction.session_token
    blocked = Meetings.get_action_point!(id, session_token)
    blocked_by = Meetings.get_action_point!(blocked_by_id, session_token)

    case Meetings.add_action_point_blocker(blocked, blocked_by) do
      {:ok, _blocker} ->
        {:noreply, refresh_all_action_points(socket)}

      {:error, :cycle} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "That relation would make these Action Points block each other in a circle."
         )
         |> refresh_all_action_points()}

      # The picker never offers these; only a stale screen can attempt them,
      # and the refresh un-stales it.
      {:error, _refused} ->
        {:noreply, refresh_all_action_points(socket)}
    end
  end

  def handle_event("pick_assignee", %{"id" => id, "sink_user_id" => ""}, socket) do
    {:noreply, set_assignee(socket, id, nil)}
  end

  def handle_event("pick_assignee", %{"id" => id, "sink_user_id" => sink_user_id}, socket) do
    sink_user = Enum.find(socket.assigns.sink_users, &(&1.id == sink_user_id))
    {:noreply, set_assignee(socket, id, sink_user)}
  end

  def handle_event("push", _params, socket) do
    scope = socket.assigns.current_scope

    cond do
      # The button disables while pushing, but a queued double-click still
      # lands here — it must not start a second Push.
      socket.assigns.pushing? ->
        {:noreply, socket}

      # No flash: the signup screen reads the session for itself and says what
      # is being kept, in a panel that survives the next click.
      is_nil(scope) ->
        {:noreply, push_navigate(socket, to: ~p"/users/register")}

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
    # A retry is a fresh run: it re-anchors an assumed meeting date to the
    # retrying visitor's own local date.
    case Meetings.retry_extraction(socket.assigns.extraction,
           local_date: socket.assigns.local_date
         ) do
      :ok ->
        {:noreply, assign_extraction(socket, refetch_extraction(socket))}

      # Same doorway as the landing page: the buy page carries the reason.
      {:error, :out_of_credits} ->
        {:noreply, push_navigate(socket, to: ~p"/buy")}
    end
  end

  @impl true
  def handle_async(:push, {:ok, result}, socket) do
    socket = assign_extraction(socket, refetch_extraction(socket))

    case result do
      # A retry that had only relations left to create pushes no new issue —
      # "Pushed 0 Action Points" would read as a failure, so say what happened.
      {:ok, []} ->
        {:noreply, put_flash(socket, :info, "Push complete — everything is in Linear.")}

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

      {:error, {:relations, reason, created, remaining}} ->
        {:noreply,
         assign(socket, :push_failure, %{
           phase: :relations,
           reason: reason,
           created: created,
           remaining: remaining
         })}

      {:error, {reason, pushed, remaining}} ->
        {:noreply,
         assign(socket, :push_failure, %{
           phase: :issues,
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
       phase: :issues,
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
     |> assign_resolved_extraction(true, refetch_extraction(socket))}
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
    id
    |> Meetings.get_action_point!(socket.assigns.extraction.session_token)
    |> Meetings.set_action_point_status(status)

    # A rejection also removed the Blockers pointing at this Action Point, so
    # other cards' chips and pickers changed too — refresh them all.
    refresh_all_action_points(socket)
  end

  defp set_assignee(socket, id, sink_user) do
    action_point =
      id
      |> Meetings.get_action_point!(socket.assigns.extraction.session_token)
      |> Meetings.set_action_point_assignee(sink_user)

    refresh_action_point(socket, action_point)
  end

  # Resolves every unresolved Action Point's assignee guess against the
  # scoped user's Task Sink (ADR-0007) — only while the socket is actually
  # connected, so the static render before LiveView takes over never makes a
  # sink call. Only a succeeded Extraction with Action Points has anything to
  # resolve. Assigns the outcome and the (possibly freshly reloaded)
  # Extraction in one step, since mount and the extraction-updated PubSub
  # handler both need to do exactly this.
  defp assign_resolved_extraction(
         socket,
         true,
         %{status: :succeeded, action_points: [_ | _]} = extraction
       ) do
    case Sinks.resolve_assignees(socket.assigns.current_scope, extraction.action_points) do
      {:ok, sink_users} ->
        extraction = Meetings.get_extraction!(extraction.id, extraction.session_token)

        socket
        |> assign(:sink_users, sink_users)
        |> assign(:sink_live?, true)
        |> assign(:assignee_degraded?, false)
        |> assign_extraction(extraction)

      {:error, :not_connected} ->
        assign_unresolved_extraction(socket, extraction, false)

      {:error, :unavailable} ->
        assign_unresolved_extraction(socket, extraction, true)
    end
  end

  defp assign_resolved_extraction(socket, _connected?, extraction) do
    assign_unresolved_extraction(socket, extraction, false)
  end

  defp assign_unresolved_extraction(socket, extraction, degraded?) do
    socket
    |> assign(:sink_users, [])
    |> assign(:sink_live?, false)
    |> assign(:assignee_degraded?, degraded?)
    |> assign_extraction(extraction)
  end

  # Patches one card in place and recounts — for the curation that only ever
  # changes its own card (quotes, assignee picks). Anything that can change
  # other cards' Blocker chips goes through refresh_all_action_points/1.
  defp refresh_action_point(socket, action_point) do
    socket
    |> assign(:pushable_count, Meetings.count_pushable_action_points(action_point.extraction_id))
    |> assign(:rejected_count, Meetings.count_rejected_action_points(action_point.extraction_id))
    |> stream_insert(:action_points, action_point)
  end

  # Re-renders every card and recounts: a rejection removes Blockers on other
  # cards, a retitle renames the chips citing it. Cards are re-inserted, not
  # reset, so transient DOM state (an open quotes disclosure) survives.
  defp refresh_all_action_points(socket) do
    action_points = refetch_extraction(socket).action_points

    socket
    |> assign_action_point_aggregates(action_points)
    |> then(
      &Enum.reduce(action_points, &1, fn ap, socket ->
        stream_insert(socket, :action_points, ap)
      end)
    )
  end

  defp assign_extraction(socket, extraction) do
    action_points = extraction.action_points

    socket
    |> assign(:extraction, %{extraction | action_points: []})
    |> assign(:editing, nil)
    |> assign(:edit_form, nil)
    |> assign(:pushing?, false)
    |> assign(:push_failure, nil)
    |> assign(:relations_supported?, Sinks.supports_relations?())
    |> assign_action_point_aggregates(action_points)
    |> assign(:pushed_action_points, Enum.filter(action_points, & &1.sink_issue_id))
    |> stream(:action_points, action_points, reset: true)
  end

  defp assign_action_point_aggregates(socket, action_points) do
    socket
    |> assign(:action_point_count, length(action_points))
    |> assign(:pushable_count, Enum.count(action_points, &Meetings.ActionPoint.pushable?/1))
    |> assign(:rejected_count, Enum.count(action_points, &(&1.status == :rejected)))
    |> assign(:has_blockers, Enum.any?(action_points, &(&1.blockers != [])))
    |> assign(:unpushed_relations_count, unpushed_relations_count(action_points))
    |> assign(
      :blocker_options,
      Enum.map(action_points, &%{id: &1.id, title: &1.title, status: &1.status})
    )
  end

  # The relations a Push still owes the sink — what keeps the Push button
  # alive after a relation-phase failure. Zero for a sink that can't take
  # them: dropped relations are never "still to create".
  defp unpushed_relations_count(action_points) do
    if Sinks.supports_relations?() do
      action_points
      |> Enum.filter(&(&1.status == :accepted))
      |> Enum.flat_map(& &1.blockers)
      |> Enum.count(&is_nil(&1.sink_relation_id))
    else
      0
    end
  end

  # The sibling Action Points one card's picker may propose as its blockers:
  # not itself, not one already blocking it, and never a rejected one — its
  # task will never exist to point at.
  defp blocker_candidates(action_point, blocker_options) do
    existing = MapSet.new(action_point.blockers, & &1.blocked_by_id)

    Enum.reject(blocker_options, fn option ->
      option.id == action_point.id or option.status == :rejected or option.id in existing
    end)
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

  # Where the anchor came from, in the reader's terms — `assumed` says plainly
  # that nothing in the upload or the Transcript stated a date.
  defp meeting_date_source_label(:filename), do: "from the filename"
  defp meeting_date_source_label(:transcript), do: "stated in the Transcript"
  defp meeting_date_source_label(:assumed), do: "assumed"

  defp push_failure_reason(:invalid_key),
    do: "Linear rejected the connected API key — check it in settings."

  defp push_failure_reason(:rate_limited),
    do: "Linear rate-limited the Push — give it a minute."

  defp push_failure_reason(_reason),
    do: "Linear could not be reached."
end
