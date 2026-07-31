defmodule ActionPointsWeb.HomeLive do
  @moduledoc """
  Landing page: paste a Transcript, kick off an Extraction, land on Review.
  Works without an account — the Extraction is keyed to the anonymous session.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Billing
  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.Meetings.Transcript
  alias ActionPointsWeb.LocalDate

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-4xl">
      <div class="mx-auto max-w-[660px]">
        <div class="pt-10 pb-2">
          <span class="mb-5 inline-flex items-center gap-2 rounded-full border border-base-300 px-3 py-1 text-[11px] font-medium tracking-[0.07em] text-base-content/65 uppercase">
            <span
              class="size-1.5 rounded-full bg-primary ring-3 ring-primary/15"
              aria-hidden="true"
            /> Transcript in, tasks out
          </span>
          <h1 class="text-4xl leading-[1.06] font-semibold tracking-[-0.033em] sm:text-[2.75rem]">
            Turn a meeting transcript<br class="hidden sm:inline" />
            into <span class="text-accent">tasks</span>.
          </h1>
          <p class="mt-4 max-w-xl text-base text-base-content/70">
            Paste the transcript your meeting tool already made. Review the extracted
            Action Points. Push the keepers to Linear — done before the next meeting starts.
          </p>
        </div>

        <%!-- The Demo's rate limit is a designed surface, not a flash: the visitor
        submitted a real Transcript and is owed the reason and the way through. --%>
        <div
          :if={@rate_limited?}
          id="rate-limit-notice"
          class="mt-8 flex gap-3 rounded-box border border-warning/40 bg-warning/10 p-4"
          role="alert"
        >
          <.icon name="hero-clock" class="size-5 shrink-0 text-warning" />
          <div>
            <p class="font-semibold">You've used up the Demo for now.</p>
            <p class="mt-1 text-base-content/70">
              The Demo runs without an account, so it's capped by the hour rather than
              charged. It opens up again shortly.
              <.link navigate={~p"/users/register"} class="text-accent hover:underline">
                Create a free account
              </.link>
              and your Free Meeting runs straight away.
            </p>
          </div>
        </div>

        <.form
          for={@form}
          id="transcript-form"
          phx-submit="extract"
          phx-change="validate"
          class="composer mt-8 overflow-hidden rounded-box border border-base-300 bg-base-200 transition-colors focus-within:border-base-content/30"
        >
          <div class="flex items-center justify-between border-b border-base-300/60 bg-base-300/30 px-4 py-2.5">
            <span class="text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
              Transcript
            </span>
            <%!-- What this run costs, stated before it is spent: the anonymous
            Demo is rate-limited rather than charged, an account run is a Credit. --%>
            <span class="rounded-field border border-base-300 px-1.5 py-0.5 text-[11px] text-base-content/65">
              {run_cost_label(@current_scope)}
            </span>
          </div>

          <div class="[&_.fieldset]:mb-0 [&_.fieldset>p]:px-4 [&_.fieldset>p]:pb-3">
            <.input
              field={@form[:transcript_text]}
              type="textarea"
              rows="12"
              class="min-h-[232px] w-full resize-y border-0 bg-transparent px-4 py-4 leading-relaxed placeholder:text-base-content/50 focus:outline-none"
              placeholder="Paste your meeting transcript here — straight from Zoom, Teams, or Meet…"
              aria-label="Meeting transcript"
            />
          </div>

          <div
            id="transcript-dropzone"
            class="border-t border-dashed border-base-300"
            phx-drop-target={@uploads.transcript.ref}
          >
            <%!-- The file input is visually hidden but stays focusable, so upload
            has a keyboard path; the label it sits in carries the focus ring. --%>
            <label class="dropzone flex cursor-pointer items-center justify-center gap-2 px-4 py-3 text-base-content/70 transition-colors hover:bg-base-300/30 hover:text-base-content">
              <.icon name="hero-arrow-up-tray" class="size-4" />
              <span>
                or upload the export file —
                <span class="font-medium text-base-content">.txt, .vtt, .srt</span>
              </span>
              <.live_file_input upload={@uploads.transcript} class="sr-only" />
            </label>

            <div
              :for={entry <- @uploads.transcript.entries}
              class="flex items-center justify-center gap-2 px-4 pb-3"
            >
              <.icon name="hero-document-text" class="size-4 text-base-content/65" />
              <span class="font-medium">{entry.client_name}</span>
              <button
                type="button"
                id={"cancel-upload-#{entry.ref}"}
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                aria-label="Remove file"
                class="rounded-field text-base-content/65 transition-colors hover:text-error"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
              <p :for={error <- upload_errors(@uploads.transcript, entry)} class="text-error">
                {upload_error_message(error)}
              </p>
            </div>

            <p
              :for={error <- upload_errors(@uploads.transcript)}
              class="px-4 pb-3 text-center text-error"
            >
              {upload_error_message(error)}
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2 border-t border-base-300/60 bg-base-300/30 px-4 py-3">
            <button id="extract-button" class="btn btn-primary btn-sm" phx-disable-with="Starting…">
              Extract Action Points
            </button>
            <button
              type="button"
              id="load-sample"
              phx-click="load_sample"
              class="btn btn-ghost btn-sm font-normal text-base-content/70"
            >
              No transcript to hand? Try the sample meeting
            </button>
          </div>
        </.form>

        <p
          id="privacy-note"
          class="mt-3.5 flex items-center gap-2 text-xs text-base-content/65"
        >
          <.icon name="hero-lock-closed-micro" class="size-3.5" />
          Your Transcript is only used to produce your Action Points — never shared.
        </p>
      </div>

      <section id="how-it-works" class="pt-[74px]">
        <h2 class="text-xs font-medium tracking-[0.09em] text-base-content/65 uppercase">
          How it works
        </h2>
        <p class="mt-1.5 mb-6 text-xl tracking-[-0.02em]">
          Three steps, no setup beyond a Linear key.
        </p>
        <ol class="grid gap-px overflow-hidden rounded-box border border-base-300 bg-base-300 sm:grid-cols-3">
          <li class="bg-base-200 p-5">
            <span class="text-[11px] font-semibold tracking-[0.08em] text-accent uppercase">
              Step 1
            </span>
            <h3 class="mt-2 font-semibold">Paste a Transcript</h3>
            <p class="mt-1.5 text-base-content/70">
              Zoom, Teams, and Meet already export one. Paste the text or drop the
              .txt, .vtt, or .srt file — timestamps get cleaned up for you.
            </p>
          </li>
          <li class="bg-base-200 p-5">
            <span class="text-[11px] font-semibold tracking-[0.08em] text-accent uppercase">
              Step 2
            </span>
            <h3 class="mt-2 font-semibold">Review the Action Points</h3>
            <p class="mt-1.5 text-base-content/70">
              Every commitment comes back with a title, context, the name the
              meeting said, and any due date said aloud. Reject the noise, edit
              the keepers.
            </p>
          </li>
          <li class="bg-base-200 p-5">
            <span class="text-[11px] font-semibold tracking-[0.08em] text-accent uppercase">
              Step 3
            </span>
            <h3 class="mt-2 font-semibold">Push to Linear</h3>
            <p class="mt-1.5 text-base-content/70">
              One Push creates the accepted Action Points as real Linear issues —
              with links back to each one, so nothing is lost in the meeting again.
            </p>
          </li>
        </ol>
      </section>

      <section id="pricing" class="pt-[74px]">
        <h2 class="text-xs font-medium tracking-[0.09em] text-base-content/65 uppercase">
          Pricing
        </h2>
        <%!-- The mockup's "pay for meetings, not seats" makes the meeting the unit
        of payment, which CONTEXT.md reserves to the Credit — meetings only ever
        size a Pack. Same contrast, correct vocabulary. --%>
        <p class="mt-1.5 mb-6 text-xl tracking-[-0.02em]">Buy Credits, not seats.</p>
        <div class="grid gap-4 sm:grid-cols-2">
          <div id="pricing-free" class="rounded-box border border-base-300 bg-base-200 p-5">
            <span class="text-[11px] tracking-[0.08em] text-base-content/65 uppercase">
              Free Meeting
            </span>
            <p class="mt-2.5 text-3xl font-semibold tracking-[-0.03em]">{@free_price}</p>
            <p class="mt-2 text-base-content/70">
              Every new account starts with one Credit, so your first meeting costs nothing.
            </p>
          </div>
          <div
            id="pricing-pack"
            class="rounded-box border border-primary/45 bg-linear-to-b from-primary/[0.07] to-transparent to-62% bg-base-200 p-5"
          >
            <span class="text-[11px] tracking-[0.08em] text-base-content/65 uppercase">
              Pack
            </span>
            <p class="mt-2.5 text-3xl font-semibold tracking-[-0.03em]">
              {@pack_price}
              <span class="text-sm font-normal tracking-normal text-base-content/70">
                / {@pack_credits} meetings
              </span>
            </p>
            <p class="mt-2 text-base-content/70">
              One Credit per successful Extraction. No subscription, no expiry.
            </p>
          </div>
        </div>
      </section>

      <footer class="mt-[84px] flex items-center justify-between border-t border-base-300/60 pt-5 pb-10 text-xs text-base-content/65">
        <span>ActionPoints</span>
        <span>Transcript in, curated tasks out.</span>
      </footer>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    # Pricing is config (ADR-0003), so the page quotes what the checkout charges
    # rather than restating it — including the Free Meeting's zero, which is only
    # "£0" for as long as the Pack is priced in pounds.
    pack = Billing.pack()

    {:ok,
     socket
     |> assign(:pack_credits, pack.credits)
     |> assign(:pack_price, Billing.format_price(pack))
     |> assign(:free_price, Billing.format_price(%{pack | price_pence: 0}))
     |> assign(:session_token, session["anon_session_token"])
     |> assign(:peer_ip, peer_ip(socket))
     |> assign(:local_date, LocalDate.from_connect_params(socket))
     |> assign(:rate_limited?, false)
     |> assign_form(Meetings.change_extraction(%Extraction{}))
     |> allow_upload(:transcript,
       accept: ~w(.txt .vtt .srt),
       max_entries: 1,
       max_file_size: 2_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    # The notice belongs to the attempt that earned it: once the visitor edits
    # the Transcript they are working on the next one, so it clears.
    {:noreply, assign(socket, :rate_limited?, false)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :transcript, ref)}
  end

  def handle_event("extract", %{"extraction" => params}, socket) do
    # An uploaded file takes precedence over anything left in the textarea, and
    # brings its own name along — the name is where the meeting date lives.
    {attrs, filename} = consume_transcript_upload(socket) || {params, nil}

    start_extraction(socket, attrs, filename)
  end

  # The sample meeting is authored, not run: no model call, no Credit, no
  # spinner, and nothing counted against the Demo's cap (issue #94). It lands
  # on a finished Review the same way a real Extraction eventually does.
  def handle_event("load_sample", _params, socket) do
    extraction =
      Meetings.create_sample_extraction(
        socket.assigns.current_scope,
        socket.assigns.session_token,
        local_date: socket.assigns.local_date
      )

    {:noreply, push_navigate(socket, to: ~p"/review/#{extraction}")}
  end

  defp start_extraction(socket, attrs, filename) do
    socket = assign(socket, :rate_limited?, false)

    case Meetings.create_extraction(
           socket.assigns.current_scope,
           socket.assigns.session_token,
           attrs,
           ip: socket.assigns.peer_ip,
           local_date: socket.assigns.local_date,
           filename: filename
         ) do
      {:ok, extraction} ->
        Meetings.start_extraction(extraction)
        {:noreply, push_navigate(socket, to: ~p"/review/#{extraction}")}

      # The gate is a screen, not a toast: the buy page reads the empty balance
      # for itself, so a flash would only say the same thing twice and then
      # evaporate.
      {:error, :out_of_credits} ->
        {:noreply, push_navigate(socket, to: ~p"/buy")}

      {:error, :rate_limited} ->
        {:noreply, assign(socket, :rate_limited?, true)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp consume_transcript_upload(socket) do
    socket
    |> consume_uploaded_entries(:transcript, fn %{path: path}, entry ->
      {:ok,
       {%{
          "transcript_text" => File.read!(path),
          "source_format" => Transcript.format_from_filename(entry.client_name)
        }, entry.client_name}}
    end)
    |> List.first()
  end

  defp upload_error_message(:too_large), do: "That file is too large (2 MB max)."

  defp upload_error_message(:not_accepted),
    do: "That file type isn't supported — use .txt, .vtt, or .srt."

  defp upload_error_message(:too_many_files), do: "Attach just one file."
  defp upload_error_message(_other), do: "Something went wrong with that upload — try again."

  # What this run will cost, stated before it is spent. An empty balance says so
  # rather than quoting a Credit the account hasn't got — the submit would only
  # bounce the reader to the Credits gate.
  defp run_cost_label(nil), do: "Free — no account needed"
  defp run_cost_label(%{credit_balance: 0}), do: "No Credits left"
  defp run_cost_label(_scope), do: "1 Credit"

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  # One half of the anonymous rate-limit key (nil when unavailable, e.g. in
  # tests without connect info — the session-token half still applies).
  defp peer_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} -> address
      _unavailable -> nil
    end
  end
end
