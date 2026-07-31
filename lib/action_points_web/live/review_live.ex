defmodule ActionPointsWeb.ReviewLive do
  @moduledoc """
  The Review screen: live Extraction progress, then the Action Points to
  curate. Only the session that created the Extraction can see it.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Billing
  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.DependencyOrder
  alias ActionPoints.Sinks
  alias ActionPointsWeb.LocalDate

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-5xl">
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

            <%!-- The sample says it is one. Everything below it is a real
            control doing a real thing to a real Extraction — it is the
            meeting that is fiction, and a screen this persuasive owes the
            reader that distinction unprompted. --%>
            <div
              :if={@extraction.sample}
              id="sample-notice"
              class="mb-4 flex gap-3 rounded-box border border-base-300 bg-base-200 p-4"
            >
              <.icon name="hero-beaker" class="size-5 shrink-0 text-base-content/65" />
              <p class="text-base-content/70">
                This is the sample meeting — an invented Transcript, so you can see the Review
                before you spend anything on your own. Walk it, decide it, break it.
                <.link navigate={~p"/"} class="text-accent hover:underline">
                  Paste your own Transcript
                </.link>
                when you're ready.
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
                {@accepted_count} accepted
              </span>
              <span :if={@undecided_count > 0} class="inline-flex items-center gap-1.5">
                <span class="size-1.5 rounded-full bg-base-content/25" aria-hidden="true"></span>
                {@undecided_count} not yet decided
              </span>
              <span :if={@rejected_count > 0} class="inline-flex items-center gap-1.5">
                <span class="size-1.5 rounded-full bg-base-content/40" aria-hidden="true"></span>
                {@rejected_count} rejected
              </span>
              <span :if={@pushable_count > 0 or @undecided_count > 0} class="ml-auto">
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
                Linear's member list couldn't be reached, so guessed names are shown as text and nothing is resolved.
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
                Your Task Sink doesn't support blocked-by relations, so the relations this Review
                carries stay here — Pushing creates the tasks without them.
              </p>
            </div>

            <%!-- A flat sink is told about before Push, not discovered after:
            the hierarchy survives Review either way, it just can't be
            represented over there. Same optional-capability shape as the
            degraded assignee fetch above. --%>
            <div
              :if={@sink_live? and not @hierarchy_supported? and @subtask_count > 0}
              id="hierarchy-unsupported-notice"
              class="mb-4 flex gap-3 rounded-box border border-warning/40 bg-warning/10 p-4"
              role="alert"
            >
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
              <p class="text-base-content/70">
                This Task Sink can't represent Subtasks, so Pushing creates them as
                ordinary top-level tasks. The nesting still shapes your Review.
              </p>
            </div>

            <%!-- Said once, above the walk, because the reason matters and
            does not bear repeating on every chip: a date we resolved wrongly
            becomes someone else's overdue task the moment it is Pushed. The
            Push is not blocked — the decision stays the user's. --%>
            <div
              :if={@past_due_count > 0}
              id="past-due-notice"
              class="mb-4 flex gap-3 rounded-box border border-warning/40 bg-warning/10 p-4"
              role="alert"
            >
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
              <p class="text-base-content/70">
                {ngettext(
                  "1 accepted Action Point has a due date that has already passed, so Pushing creates it already overdue in Linear. Change or clear the date if the meeting meant something else.",
                  "%{count} accepted Action Points have due dates that have already passed, so Pushing creates them already overdue in Linear. Change or clear the dates if the meeting meant something else.",
                  @past_due_count
                )}
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

            <%!-- One Action Point per screen — or one family, parent and
            Subtasks together — in dependency order, until every one has been
            decided (ADR-0010). The position is a query over the rows, never
            held in this process, so a reload, a crash or a deploy all land
            back on the same step. --%>
            <.step
              :if={@step}
              action_point={@step}
              subtasks={@step_subtasks}
              sink_users={@sink_users}
              sink_live?={@sink_live?}
              decided_count={@accepted_count + @rejected_count}
              action_point_count={@action_point_count}
              today={@today}
            />
            <%!-- The walk is over and the summary that holds the set, its
            relations and the Push is #108's. Until it lands, the decisions
            are stated plainly so the end of the walk is not a blank screen. --%>
            <div :if={is_nil(@step)} id="review-decided" class="py-2">
              <h2 class="text-lg font-semibold">Every Action Point decided</h2>
              <ul class="mt-3 space-y-2">
                <li
                  :for={action_point <- @decided}
                  id={"decided-#{action_point.id}"}
                  data-role="decided-row"
                  data-status={action_point.status}
                  class={[
                    "flex flex-wrap items-center gap-x-3 gap-y-1.5 rounded-box border p-3",
                    (action_point.status == :rejected &&
                       "border-dashed border-base-300 bg-transparent") ||
                      "border-base-300/60 bg-base-200"
                  ]}
                >
                  <span class={[
                    "font-medium",
                    action_point.status == :rejected && "text-base-content/65 line-through"
                  ]}>
                    {action_point.title}
                  </span>
                  <span class="ml-auto flex flex-wrap items-center gap-1.5">
                    <%!-- Rejecting is one click and a mis-click is one too, so
                    the way back stays under the hand: a rejection is reversible
                    into an acceptance, exactly as it was on the old card. The
                    walk never sends anything back to undecided — a decision is
                    a one-way step (ADR-0010) — and re-accepting does not
                    resurrect the Blockers the rejection removed. --%>
                    <button
                      :if={action_point.status == :rejected and is_nil(action_point.sink_issue_id)}
                      id={"decided-#{action_point.id}-accept"}
                      phx-click="accept"
                      phx-value-id={action_point.id}
                      class="btn btn-ghost btn-xs"
                      title="Accept this Action Point after all"
                    >
                      <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Accept
                    </button>
                    <a
                      :if={action_point.sink_issue_id}
                      data-role="sink-issue"
                      href={action_point.sink_issue_url}
                      target="_blank"
                      rel="noopener"
                      class="inline-flex items-center gap-1 rounded-field border border-success/40 bg-success/10 px-2 py-0.5 text-xs font-medium text-success"
                    >
                      <.icon name="hero-check-micro" class="size-3" />
                      {action_point.sink_issue_identifier}
                    </a>
                    <.due_date_chip
                      action_point={action_point}
                      flagged={flag_past_due?(action_point, @today)}
                    />
                  </span>
                </li>
              </ul>
            </div>

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
  attr :flagged, :boolean, default: false, doc: "styles the chip as something to look at"
  slot :inner_block, required: true

  defp chip(assigns) do
    ~H"""
    <span
      data-role={@role}
      data-past-due={@flagged}
      class={[
        "inline-flex items-center gap-1.5 rounded-field border px-2 py-0.5 text-xs",
        cond do
          @flagged -> "border-warning/50 bg-warning/10 text-base-content/80"
          @empty -> "border-base-300 border-dashed text-base-content/65"
          true -> "border-base-300 text-base-content/70"
        end
      ]}
    >
      <.icon
        name={@icon}
        class={
          cond do
            @flagged -> "size-3 text-warning"
            @empty -> "size-3"
            true -> "size-3 text-base-content/65"
          end
        }
      />
      {render_slot(@inner_block)}
    </span>
    """
  end

  # The step: one Action Point owning the screen, or — where the meeting broke
  # one down — a whole family on it (ADR-0010).
  #
  # A Subtask cannot be judged without the thing it belongs to, and the
  # parent's title alone is not that: whether a Subtask really belongs to the
  # deliverable or should stand on its own is a question about its description,
  # its quotes and its deadline. So the parent renders in full and its Subtasks
  # render beneath it, each decidable where it stands.
  #
  # The parent is decided last, and cannot be decided sooner: rejecting it
  # promotes whatever survived to top level and that is irreversible at Review
  # (ADR-0009), so the decision waits until it can be taken knowing what
  # survived. The wait is a disabled control, not a sentence on its own.
  #
  # Nesting is never deeper than one level, so a family is bounded and this
  # screen cannot grow a third rendering of an Action Point.
  attr :action_point, :map, required: true
  attr :subtasks, :list, required: true, doc: "the family's children, already in walk order"
  attr :sink_users, :list, required: true
  attr :sink_live?, :boolean, required: true
  attr :decided_count, :integer, required: true
  attr :action_point_count, :integer, required: true
  attr :today, Date, required: true

  defp step(assigns) do
    ~H"""
    <div
      id={"step-#{@action_point.id}"}
      data-role="step"
      data-status={@action_point.status}
      data-family={@subtasks != []}
      class="rounded-box border border-base-300/60 bg-base-200 p-5 sm:p-6"
    >
      <%!-- The counter counts Action Points decided, never steps: a family is
      one step and several Action Points, and the header above promised a
      number of Action Points. --%>
      <p class="text-[11px] tracking-[0.08em] text-base-content/65 uppercase">
        {@decided_count} of {@action_point_count} decided
      </p>

      <.action_point_panel
        action_point={@action_point}
        sink_users={@sink_users}
        sink_live?={@sink_live?}
        today={@today}
      />

      <%!-- The children, in a compressed rendering of the very same panel —
      one component, so the two cannot drift apart. --%>
      <div :if={@subtasks != []} data-role="family" class="mt-6 space-y-3">
        <h3 class="text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
          {ngettext(
            "1 Subtask of this Action Point",
            "%{count} Subtasks of this Action Point",
            length(@subtasks)
          )}
        </h3>
        <div
          :for={subtask <- @subtasks}
          id={"subtask-#{subtask.id}"}
          data-role="family-subtask"
          data-status={subtask.status}
          class={[
            "rounded-box border border-l-4 p-4",
            (subtask.status == :undecided && "border-base-300/60 border-l-base-300 bg-base-100") ||
              "border-base-300/40 border-l-base-300/40 bg-base-100/50"
          ]}
        >
          <.action_point_panel
            action_point={subtask}
            sink_users={@sink_users}
            sink_live?={@sink_live?}
            today={@today}
            compact
          />
          <.decision_bar action_point={subtask} locked_reason={lock_reason(subtask, [])} compact />
        </div>
      </div>

      <%!-- Last on the screen because it is the last decision available: the
      parent's own Accept and Reject, under everything they depend on. --%>
      <.decision_bar
        action_point={@action_point}
        locked_reason={lock_reason(@action_point, @subtasks)}
      />
    </div>
    """
  end

  # An Action Point rendered in full: title, then two columns of comparable
  # weight — what the meeting said on the left, the issue we would create on
  # the right.
  #
  # The columns are a claim enforced by what can be touched: nothing in the
  # left one is interactive, because it is a record of the Transcript and a
  # record cannot be wrong. Everything the user can change lives on the right,
  # which is the thing being created.
  #
  # On a narrow viewport they stack, left above right: the meeting is read
  # first and the issue second, which is the same argument the columns make
  # left to right.
  #
  # `compact` is the only difference between a step and a Subtask beneath one:
  # the same rows, the same pills, the same controls, set smaller. Sharing the
  # component rather than writing a second one is deliberate — a family shows
  # this layout twice on one screen, and two copies of it would drift.
  attr :action_point, :map, required: true
  attr :sink_users, :list, required: true
  attr :sink_live?, :boolean, required: true
  attr :today, Date, required: true
  attr :compact, :boolean, default: false

  defp action_point_panel(assigns) do
    # A pushed Action Point is a record of something that exists: its controls
    # freeze, and only the chips saying what was created remain.
    assigns = assign(assigns, :curatable?, is_nil(assigns.action_point.sink_issue_id))

    ~H"""
    <div data-role={(@compact && "subtask-panel") || "step-panel"} class={@compact && "text-sm"}>
      <%!-- A rejected Action Point is struck through wherever it is still on
      screen, the same as on a decided row: the parent's Reject is taken
      knowing what survived, so what did not survive has to look like it. --%>
      <h2
        :if={not @compact}
        data-role="step-title"
        class={[
          "mt-1 text-xl leading-snug font-semibold",
          @action_point.status == :rejected && "text-base-content/65 line-through"
        ]}
      >
        {@action_point.title}
      </h2>
      <h3
        :if={@compact}
        data-role="subtask-title"
        class={[
          "text-base leading-snug font-semibold",
          @action_point.status == :rejected && "text-base-content/65 line-through"
        ]}
      >
        {@action_point.title}
      </h3>

      <div class={["grid gap-6 md:grid-cols-2", (@compact && "mt-3") || "mt-5"]}>
        <.meeting_column action_point={@action_point} />
        <.issue_column
          action_point={@action_point}
          sink_users={@sink_users}
          sink_live?={@sink_live?}
          curatable?={@curatable?}
          today={@today}
        />
      </div>
    </div>
    """
  end

  # Accept and Reject are the only ways forward, and Accept commits what is on
  # the screen: the pills wrote their changes when they were used, so there is
  # nothing left here to save separately.
  #
  # Three states, because a family puts more than one of them on a screen at
  # once: the decision still to take, the decision already taken — which the
  # parent's Reject has to be able to read off the page — and the record of an
  # Action Point already in the sink.
  #
  # `locked_reason` is the walk's ordering reaching the markup: a decision
  # whose dependencies are not all decided has its controls genuinely
  # disabled, not merely styled as if, and the reason stands beside them.
  attr :action_point, :map, required: true
  attr :compact, :boolean, default: false
  attr :locked_reason, :string, default: nil

  defp decision_bar(assigns) do
    assigns =
      assigns
      |> assign(:curatable?, is_nil(assigns.action_point.sink_issue_id))
      |> assign(:prefix, (assigns.compact && "subtask") || "step")

    ~H"""
    <div
      data-role={"#{@prefix}-decision"}
      class={[
        "flex flex-wrap items-center gap-2 border-t border-base-300/60",
        (@compact && "mt-4 pt-3") || "mt-6 pt-4"
      ]}
    >
      <%= cond do %>
        <% not @curatable? -> %>
          <a
            data-role="sink-issue"
            href={@action_point.sink_issue_url}
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 rounded-field border border-success/40 bg-success/10 px-2 py-0.5 text-xs font-medium text-success"
          >
            <.icon name="hero-check-micro" class="size-3" />
            {@action_point.sink_issue_identifier}
          </a>
          <span class="text-xs text-base-content/65">
            Already created in Linear — this step is a record of what was sent.
          </span>
        <% @action_point.status != :undecided -> %>
          <%!-- Said, not merely styled: the parent's Reject below is taken
          knowing which of these survived, so the screen has to state it. --%>
          <span
            data-role="decision-made"
            data-decision={@action_point.status}
            class={[
              "inline-flex items-center gap-1 rounded-field border px-2 py-0.5 text-xs font-medium",
              (@action_point.status == :accepted && "border-primary/40 bg-primary/10 text-primary") ||
                "border-base-300 border-dashed text-base-content/65"
            ]}
          >
            <.icon
              name={(@action_point.status == :accepted && "hero-check-micro") || "hero-x-mark-micro"}
              class="size-3"
            />
            {(@action_point.status == :accepted && "Accepted") || "Rejected"}
          </span>
          <%!-- A rejection is reversible into an acceptance and never the
          other way — the same one-way rule the decided rows follow, so the
          product has one answer to this and not two (ADR-0010). --%>
          <button
            :if={@action_point.status == :rejected}
            id={"#{@prefix}-#{@action_point.id}-accept"}
            data-role="accept"
            phx-click="accept"
            phx-value-id={@action_point.id}
            class="btn btn-ghost btn-xs"
            title="Accept this Action Point after all"
          >
            <.icon name="hero-arrow-uturn-left-micro" class="size-3.5" /> Accept
          </button>
        <% true -> %>
          <button
            id={"#{@prefix}-#{@action_point.id}-accept"}
            data-role="accept"
            phx-click="accept"
            phx-value-id={@action_point.id}
            disabled={@locked_reason != nil}
            aria-describedby={@locked_reason && "#{@prefix}-#{@action_point.id}-locked"}
            class={["btn btn-primary", (@compact && "btn-xs") || "btn-sm"]}
          >
            <.icon name="hero-check-micro" class="size-4" /> Accept
          </button>
          <button
            id={"#{@prefix}-#{@action_point.id}-reject"}
            data-role="reject"
            phx-click="reject"
            phx-value-id={@action_point.id}
            disabled={@locked_reason != nil}
            aria-describedby={@locked_reason && "#{@prefix}-#{@action_point.id}-locked"}
            class={["btn btn-ghost", (@compact && "btn-xs") || "btn-sm"]}
          >
            <.icon name="hero-x-mark-micro" class="size-4" /> Reject
          </button>
          <span
            :if={@locked_reason}
            id={"#{@prefix}-#{@action_point.id}-locked"}
            data-role="decision-locked"
            class="text-xs text-base-content/65"
          >
            {@locked_reason}
          </span>
          <span :if={is_nil(@locked_reason)} class="ml-auto text-xs text-base-content/65">
            Accepting creates this exactly as the right-hand column reads.
          </span>
      <% end %>
    </div>
    """
  end

  # Why a decision is not available yet, or nil when it is. "Disabled" on its
  # own reads as a bug; the reason is what makes it read as a rule.
  #
  # Both directions of the walk's one rule (ADR-0010), because a family puts
  # several Action Points on one screen and only the first of them is
  # guaranteed to have had its turn: a Subtask can still be waiting on a
  # Blocker nobody has reached, and a parent waits on all of its children.
  #
  # It says **Subtask**, which is what CONTEXT.md calls the thing and what the
  # rest of this screen already says.
  defp lock_reason(action_point, subtasks) do
    undecided = Enum.count(subtasks, &(&1.status == :undecided))

    cond do
      blocker = undecided_blocker(action_point) ->
        gettext(
          "“%{title}” blocks this and hasn't been decided yet — the walk decides a Blocker first.",
          title: blocker.blocked_by.title
        )

      undecided > 0 ->
        ngettext(
          "1 Subtask still to decide. Once it is, you can accept or reject “%{title}” — rejecting it would promote whatever survives to top level, and that can't be undone.",
          "%{count} Subtasks still to decide. Once they all are, you can accept or reject “%{title}” — rejecting it would promote whatever survives to top level, and that can't be undone.",
          undecided,
          title: action_point.title
        )

      true ->
        nil
    end
  end

  defp undecided_blocker(action_point) do
    Enum.find(action_point.blockers, &(&1.blocked_by.status == :undecided))
  end

  # The left column: what the meeting said, verbatim, and nothing that can be
  # touched. Every row is stated even when it is empty — "nobody was named" is
  # a fact about the meeting, and leaving it blank would read as nobody having
  # looked.
  attr :action_point, :map, required: true

  defp meeting_column(assigns) do
    ~H"""
    <section data-role="meeting-column" class="space-y-4">
      <h3 class="text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
        The meeting said
      </h3>

      <div>
        <p class="text-xs text-base-content/65">Who</p>
        <p data-role="named-person" class="mt-0.5 font-medium">
          {@action_point.assignee_guess || "Nobody was named"}
        </p>
      </div>

      <div :if={@action_point.quotes != []} data-role="grounding-quotes">
        <p class="text-xs text-base-content/65">In their words</p>
        <blockquote
          :for={quote <- @action_point.quotes}
          data-role="grounding-quote"
          class="mt-2 border-l-2 border-base-300 pl-3 text-base-content/70 italic"
        >
          {quote}
        </blockquote>
      </div>

      <div>
        <p class="text-xs text-base-content/65">When</p>
        <p
          :if={@action_point.timing_quote}
          data-role="timing-quote"
          class="mt-0.5 text-base-content/70 italic"
        >
          “{@action_point.timing_quote}”
        </p>
        <p :if={is_nil(@action_point.timing_quote)} class="mt-0.5 text-base-content/65">
          Nothing was said about when
        </p>
      </div>
    </section>
    """
  end

  # The right column: the issue we would create, and the only things on the
  # screen that can be changed. The description is the one Push composes, not
  # the model's bare prose — Review previewed a document that did not exist
  # until ADR-0010 (issue #106).
  attr :action_point, :map, required: true
  attr :sink_users, :list, required: true
  attr :sink_live?, :boolean, required: true
  attr :curatable?, :boolean, required: true
  attr :today, Date, required: true

  defp issue_column(assigns) do
    ~H"""
    <section data-role="issue-column" class="space-y-3">
      <h3 class="text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
        What we'll create
      </h3>

      <p data-role="issue-title" class="font-medium">{@action_point.title}</p>

      <%!-- Byte for byte the description Push sends: the parts concatenate to
      `Sinks.compose_description/1` and the removal control is an icon with no
      text of its own, so nothing this renders adds a character to it.

      `phx-no-format` is load-bearing rather than cosmetic — the formatter
      indents element bodies, and an indent inside this block is a character
      the Push never sends. --%>
      <div
        data-role="payload-description"
        class="rounded-box border border-base-300/60 bg-base-100 p-3 text-sm whitespace-pre-wrap text-base-content/80"
        phx-no-format
      ><span :for={part <- Sinks.description_parts(@action_point)}>{part.text}<button
        :if={part.quote_index && @curatable?}
        id={"quote-#{@action_point.id}-#{part.quote_index}-remove"}
        data-role="remove-quote"
        phx-click="remove_quote"
        phx-value-id={@action_point.id}
        phx-value-index={part.quote_index}
        class="ml-1 inline-grid translate-y-px place-items-center rounded-[3px] p-0.5 align-middle hover:bg-base-300"
        title="Remove this quote"
        aria-label={"Remove quote #{part.quote_index + 1}"}
      ><.icon name="hero-x-mark-micro" class="size-3" /></button></span></div>

      <div class="flex flex-wrap items-center gap-1.5">
        <.sink_member_pill
          action_point={@action_point}
          sink_users={@sink_users}
          pickable={@sink_live? and @curatable?}
        />
        <.due_date_pill action_point={@action_point} today={@today} pickable={@curatable?} />
        <%!-- Blockers: the ordering the meeting stated, and by now a statement
        about a decision already made, since the walk decides a Blocker before
        the Action Point it blocks. Removable until the relation is real in the
        Task Sink, never addable here (ADR-0009). --%>
        <span
          :for={blocker <- @action_point.blockers}
          data-role="blocker"
          class="inline-flex items-center gap-1 rounded-field border border-base-300 px-2 py-0.5 text-xs text-base-content/70"
        >
          <.icon name="hero-hand-raised-micro" class="size-3 text-base-content/65" /> Blocked by:
          <span class="max-w-[14rem] truncate font-medium">{blocker.blocked_by.title}</span>
          <button
            :if={is_nil(blocker.sink_relation_id)}
            id={"blocker-#{blocker.id}-remove"}
            phx-click="remove_blocker"
            phx-value-id={blocker.id}
            class="-mr-0.5 grid place-items-center rounded-[3px] p-0.5 hover:bg-base-300"
            title="Remove this relation"
            aria-label="Remove this relation"
          >
            <.icon name="hero-x-mark-micro" class="size-3" />
          </button>
        </span>
        <%!-- Undoing a nesting the Extraction proposed, which ADR-0009 counts
        as correcting rather than authoring. Its inverse is deliberately
        absent. --%>
        <button
          :if={@action_point.parent_id && @curatable?}
          id={"action-point-#{@action_point.id}-promote"}
          data-role="promote"
          phx-click="promote"
          phx-value-id={@action_point.id}
          class="btn btn-ghost btn-xs"
          title="Promote to top level"
        >
          <.icon name="hero-arrow-up-left-micro" class="size-3.5" /> Promote
        </button>
      </div>
    </section>
    """
  end

  # The Sink Member: the only half of an assignee that can be wrong, so the
  # only half the user can change. Matched shows the name and handle; unmatched
  # is dashed and says so. Nothing is ever guessed here — an ambiguous Named
  # Person reaches Review resolved to nobody, never to a plausible Dan.
  #
  # The member list stands open beside the pill rather than behind a
  # disclosure. A suggestion the reader never opened is a suggestion they never
  # saw, and ADR-0007's whole claim is that nobody is assigned in a colleague's
  # workspace without the pick having been on screen.
  #
  # Three states, and the third is not the second: the picker while the sink is
  # live, a static chip when Review resolved something and cannot any more, and
  # nothing at all when Review never got the chance — no connection, or a member
  # list that could not be reached. "Nobody matched" is a claim about the
  # workspace, and we do not make it about a workspace we never read.
  attr :action_point, :map, required: true
  attr :sink_users, :list, required: true
  attr :pickable, :boolean, required: true

  defp sink_member_pill(assigns) do
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
          <.sink_member_chip action_point={@action_point} />
          <select
            id={"action-point-#{@action_point.id}-assignee"}
            name="sink_user_id"
            data-role="assignee-picker"
            class="select select-xs w-auto max-w-[16rem]"
          >
            <option value="" selected={is_nil(@action_point.sink_member_id)}>
              Unassigned — pick a member
            </option>
            <option
              :for={user <- @sink_users}
              value={user.id}
              selected={@action_point.sink_member_id == user.id}
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
      <% @action_point.assignee_resolution -> %>
        <.sink_member_chip action_point={@action_point} />
      <% true -> %>
    <% end %>
    """
  end

  attr :action_point, :map, required: true

  defp sink_member_chip(assigns) do
    ~H"""
    <%= if @action_point.sink_member_id do %>
      <.chip role="sink-member" icon="hero-user-micro">
        {sink_member_label(@action_point)}
      </.chip>
    <% else %>
      <.chip role="sink-member" icon="hero-user-micro" empty>Nobody matched</.chip>
    <% end %>
    """
  end

  # One Action Point's due date — the whole of it, present or absent, flagged
  # or not. A resolved date that has already passed is shown and marked, never
  # cleared and never blocking: our guess about the deadline is the one place
  # where being wrong reaches out and touches colleagues who never used this
  # product, since an overdue task fires whatever the workspace notifies on.
  # The user sees the flag and decides — keep it, change it, or clear it.
  #
  # Change and clear stand open, for the same reason the member list does: a
  # control behind a disclosure is a control the reader did not know they had.
  # Clear especially — Edit used to be the only way to take a date the meeting
  # got wrong back off, and deleting Edit must not take that with it (#106).
  attr :action_point, :map, required: true
  attr :today, Date, required: true, doc: "the visitor's own today, read fresh at Review"
  attr :pickable, :boolean, required: true

  defp due_date_pill(assigns) do
    ~H"""
    <%= cond do %>
      <% @pickable -> %>
        <span class="inline-flex flex-wrap items-center gap-1.5">
          <.due_date_chip
            action_point={@action_point}
            flagged={pending_past_due?(@action_point, @today)}
          />
          <form
            id={"action-point-#{@action_point.id}-due-date-form"}
            phx-change="set_due_date"
            phx-value-id={@action_point.id}
          >
            <input
              type="date"
              name="due_date"
              data-role="due-date-input"
              value={@action_point.due_date && Date.to_iso8601(@action_point.due_date)}
              class="input input-xs w-auto"
            />
          </form>
          <button
            :if={@action_point.due_date}
            id={"action-point-#{@action_point.id}-due-date-clear"}
            data-role="clear-due-date"
            phx-click="clear_due_date"
            phx-value-id={@action_point.id}
            class="btn btn-ghost btn-xs"
          >
            Clear
          </button>
        </span>
      <% true -> %>
        <.due_date_chip action_point={@action_point} flagged={flag_past_due?(@action_point, @today)} />
    <% end %>
    """
  end

  attr :action_point, :map, required: true
  attr :flagged, :boolean, required: true

  defp due_date_chip(assigns) do
    ~H"""
    <%= cond do %>
      <% @flagged -> %>
        <.chip role="due-date" icon="hero-exclamation-triangle-micro" flagged>
          {Calendar.strftime(@action_point.due_date, "%-d %b %Y")}
          <span class="font-medium">· already passed</span>
        </.chip>
      <% @action_point.due_date -> %>
        <.chip role="due-date" icon="hero-calendar-micro">
          {Calendar.strftime(@action_point.due_date, "%-d %b %Y")}
        </.chip>
      <% true -> %>
        <%!-- A missing due date is stated, not left blank: the model heard no
        date, which is different from nobody having looked. --%>
        <.chip role="no-due-date" icon="hero-calendar-micro" empty>No due date</.chip>
    <% end %>
    """
  end

  # The flag on a step, where the date is still under the reader's hand.
  # Deliberately wider than `flag_past_due?/2`: the set-level notice warns
  # about what a Push would create overdue and so counts only what is
  # accepted, but a signal that waited for the decision would arrive after it.
  defp pending_past_due?(action_point, today) do
    action_point.status != :rejected and is_nil(action_point.sink_issue_id) and
      past_due?(action_point.due_date, today)
  end

  # Whether one Action Point's due date is worth warning the whole Review
  # about. One predicate for the notice and the rows beneath it, so the screen
  # can never warn in one place and stay quiet in the other. Only what a Push
  # would actually act on: a rejected Action Point creates nothing, and a
  # pushed one is past being warned about — its task is already in the sink.
  defp flag_past_due?(action_point, today) do
    action_point.status == :accepted and is_nil(action_point.sink_issue_id) and
      past_due?(action_point.due_date, today)
  end

  # A resolved due date is past when it falls before the visitor's today —
  # today itself is not late. Compared against today and never against the
  # Meeting Date: a deadline in the past relative to a three-week-old meeting
  # is exactly what we would expect, and is not the signal worth flagging.
  defp past_due?(nil, _today), do: false
  defp past_due?(%Date{} = due_date, %Date{} = today), do: Date.before?(due_date, today)

  # Name and handle, the same shape the picker's options use, so the chip a
  # pushed Action Point falls back to reads as the pick that was made. The
  # handle is here at all because it was written down when the member list was
  # reachable. It can still be absent — a row resolved before the column
  # existed, or a pick made from a source that carried no handle — and the
  # name alone is a worse answer than nothing, so it stands in.
  defp sink_member_label(%{sink_member_handle: nil} = action_point) do
    action_point.sink_member_name
  end

  defp sink_member_label(action_point) do
    "#{action_point.sink_member_name} (@#{action_point.sink_member_handle})"
  end

  @impl true
  def mount(%{"id" => id}, session, socket) do
    # Subscribe before fetching so a status change can't slip in between —
    # otherwise the spinner could hang on an update we never hear about.
    if connected?(socket), do: Meetings.subscribe(id)

    extraction = Meetings.get_extraction!(id, session["anon_session_token"])

    local_date = LocalDate.from_connect_params(socket)

    {:ok,
     socket
     |> assign(:local_date, local_date)
     # Today is read here, at Review, from the visitor's own browser — never
     # derived from the stored Meeting Date. Review can happen days after the
     # Extraction, and from a different calendar than the server's, so the
     # only "today" worth flagging against is the one on the visitor's wall.
     |> assign(:today, local_date || Date.utc_today())
     |> assign(:hierarchy_supported?, Sinks.hierarchy_supported?())
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
    id
    |> Meetings.get_action_point!(socket.assigns.extraction.session_token)
    |> Meetings.remove_action_point_quote(String.to_integer(index))

    {:noreply, refresh(socket)}
  end

  # The due date, changed and cleared without Edit. Both write immediately:
  # Accept commits what is on the screen, so there is no state in which a pill
  # has been used but not saved (ADR-0010).
  def handle_event("set_due_date", %{"id" => id, "due_date" => due_date}, socket) do
    {:noreply, curate_due_date(socket, id, due_date)}
  end

  def handle_event("clear_due_date", %{"id" => id}, socket) do
    {:noreply, curate_due_date(socket, id, nil)}
  end

  def handle_event("remove_blocker", %{"id" => id}, socket) do
    id
    |> Meetings.get_blocker!(socket.assigns.extraction.session_token)
    |> Meetings.remove_action_point_blocker()

    {:noreply, refresh(socket)}
  end

  # Undoing a nesting the model proposed, which ADR-0009 counts as correcting
  # the Extraction rather than authoring structure. Its counterpart — nesting
  # an Action Point the meeting never nested — is deliberately absent.
  def handle_event("promote", %{"id" => id}, socket) do
    action_point = Meetings.get_action_point!(id, socket.assigns.extraction.session_token)

    case Meetings.promote_action_point(action_point) do
      {:ok, _promoted} ->
        {:noreply, refresh(socket)}

      # The step offered no such control — a stale or forged event is a no-op.
      {:error, _reason} ->
        {:noreply, socket}
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

  # Deciding this step moves the walk on, and the move is a consequence of the
  # write rather than a step counter: a rejection also removes this Action
  # Point's Blockers and promotes its Subtasks, so the order itself can change
  # underneath the decision that caused it.
  defp set_status(socket, id, status) do
    action_point = Meetings.get_action_point!(id, socket.assigns.extraction.session_token)

    if decidable?(action_point) do
      Meetings.set_action_point_status(action_point, status)
      refresh(socket)
    else
      socket
    end
  end

  # The walk's ordering, enforced where a disabled attribute cannot be. Asked
  # of the row rather than of the screen that asked, so a stale tab or a forged
  # event finds no decision available either — and asked of both directions of
  # the one rule, since a screen that shows several Action Points at once can
  # be clicked out of order in more than one way.
  defp decidable?(action_point) do
    is_nil(undecided_blocker(action_point)) and
      Enum.all?(action_point.subtasks, &(&1.status != :undecided))
  end

  defp set_assignee(socket, id, sink_user) do
    id
    |> Meetings.get_action_point!(socket.assigns.extraction.session_token)
    |> Meetings.set_action_point_assignee(sink_user)

    refresh(socket)
  end

  # A due date the meeting got wrong: changed to another day, or taken off
  # entirely. Nothing else on the Action Point is castable here, so a crafted
  # submit carrying a title or a Named Person changes neither.
  defp curate_due_date(socket, id, due_date) do
    action_point = Meetings.get_action_point!(id, socket.assigns.extraction.session_token)

    case Meetings.update_action_point(action_point, %{"due_date" => due_date}) do
      {:ok, _updated} -> refresh(socket)
      # An unparseable date leaves the one that was there — the pill offers a
      # date input, so only a forged event gets here.
      {:error, _changeset} -> socket
    end
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

  # Re-reads the Action Points and re-derives everything the screen is: the
  # step is a query, so any curation that could move the walk — a decision, a
  # promotion, a removed Blocker — needs nothing more than this.
  #
  # Deliberately not `assign_extraction/2`: a partial Push leaves a report of
  # which tasks exist in Linear and which do not, and that report is the only
  # place the split is stated. Curating the rest of the Review must not wipe
  # it, and must not tell the screen that a Push still running has finished.
  defp refresh(socket) do
    assign_action_point_aggregates(socket, refetch_extraction(socket).action_points)
  end

  defp assign_extraction(socket, extraction) do
    action_points = extraction.action_points

    socket
    |> assign(:extraction, %{extraction | action_points: []})
    |> assign(:pushing?, false)
    |> assign(:push_failure, nil)
    |> assign(:relations_supported?, Sinks.supports_relations?())
    |> assign_action_point_aggregates(action_points)
  end

  defp assign_action_point_aggregates(socket, action_points) do
    socket
    |> assign(:action_point_count, length(action_points))
    |> assign(:pushable_count, Enum.count(action_points, &Meetings.ActionPoint.pushable?/1))
    # Counted rather than inferred from the total: since ADR-0010 an Action
    # Point starts undecided, so "not rejected" no longer means accepted.
    |> assign(:accepted_count, Enum.count(action_points, &(&1.status == :accepted)))
    |> assign(:undecided_count, Enum.count(action_points, &(&1.status == :undecided)))
    |> assign(:rejected_count, Enum.count(action_points, &(&1.status == :rejected)))
    |> assign(:has_blockers, Enum.any?(action_points, &(&1.blockers != [])))
    |> assign(:unpushed_relations_count, unpushed_relations_count(action_points))
    |> assign(:pushed_action_points, Enum.filter(action_points, & &1.sink_issue_id))
    |> assign(:past_due_count, past_due_count(action_points, socket.assigns.today))
    |> assign(:subtask_count, Enum.count(action_points, & &1.parent_id))
    |> assign_walk(action_points)
  end

  # Where the walk stands, derived rather than remembered (ADR-0010): the step
  # is the first Action Point in dependency order that has not been decided,
  # and the rest — behind it, in the same order — is what has been.
  defp assign_walk(socket, action_points) do
    ordered = DependencyOrder.sort(action_points)
    {step, subtasks} = family(Enum.find(ordered, &(&1.status == :undecided)), ordered)

    socket
    |> assign(:step, step)
    |> assign(:step_subtasks, subtasks)
    |> assign(:decided, Enum.reject(ordered, &(&1.status == :undecided)))
  end

  # The family the walk has arrived at: the Action Point that owns the screen
  # and the Subtasks decided beneath it.
  #
  # Dependency Order reaches a family through its children, so the parent is
  # pulled onto the screen by the first of them — a Subtask is never shown
  # without the whole it is part of. An Action Point with no nesting on either
  # side is its own step and the family furniture never appears.
  #
  # The parent is looked up in the ordered list rather than through the
  # association, so it is the same struct the walk holds, preloaded alike.
  defp family(nil, _ordered), do: {nil, []}

  defp family(%{parent_id: nil} = action_point, ordered) do
    {action_point, subtasks_of(action_point, ordered)}
  end

  defp family(%{parent_id: parent_id} = action_point, ordered) do
    case Enum.find(ordered, &(&1.id == parent_id and &1.status == :undecided)) do
      nil -> {action_point, []}
      parent -> {parent, subtasks_of(parent, ordered)}
    end
  end

  defp subtasks_of(parent, ordered), do: Enum.filter(ordered, &(&1.parent_id == parent.id))

  # How many Action Points are carrying the flag — what decides whether the notice
  # explaining it is worth showing at all.
  defp past_due_count(action_points, today) do
    Enum.count(action_points, &flag_past_due?(&1, today))
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
