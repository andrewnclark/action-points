defmodule ActionPointsWeb.HomeLive do
  @moduledoc """
  Landing page: paste a Transcript, kick off an Extraction, land on Review.
  Works without an account — the Extraction is keyed to the anonymous session.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.Meetings.Transcript

  # A canned product-team standup, for visitors with no transcript to hand.
  @sample_transcript """
  Maya: Right, quick one today. Where are we on the launch?
  Dan: Landing page is done bar the pricing table. I'll have the pricing table finished by Thursday.
  Maya: Good. Priya, the onboarding emails?
  Priya: Drafted. I still owe the welcome email a proper subject line — I'll send the final versions to Maya for sign-off tomorrow.
  Maya: Please. And someone needs to chase legal about the updated terms before we flip the switch.
  Dan: I can take that. I'll email Sofia in legal today and ask for a yes/no by Friday.
  Priya: One more thing — the signup form still breaks on Safari. Jonas said he'd look but he's out this week.
  Maya: Then let's not wait. Dan, can you pick up the Safari signup bug once the pricing table's out the door?
  Dan: Yep, fine.
  Maya: I'll book the go/no-go call for Monday morning and send the invite round this afternoon. Anything else? No? Good — thanks all.
  """

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl">
        <div class="pt-10 pb-8 text-center">
          <h1 class="text-4xl font-bold">Turn a meeting transcript into tasks</h1>
          <p class="mt-4 text-lg text-base-content/70">
            Paste the transcript your meeting tool already made. Review the extracted
            Action Points. Push the keepers to Linear — done before the next meeting starts.
          </p>
        </div>

        <.form for={@form} id="transcript-form" phx-submit="extract" phx-change="validate">
          <.input
            field={@form[:transcript_text]}
            type="textarea"
            rows="12"
            placeholder="Paste your meeting transcript here — straight from Zoom, Teams, or Meet…"
            aria-label="Meeting transcript"
          />

          <div
            id="transcript-dropzone"
            class="mt-3 rounded-lg border border-dashed border-base-content/20 px-4 py-3 transition-colors hover:border-base-content/40"
            phx-drop-target={@uploads.transcript.ref}
          >
            <label class="flex cursor-pointer items-center justify-center gap-2 text-sm text-base-content/70">
              <.icon name="hero-arrow-up-tray" class="h-4 w-4" />
              <span>
                or upload the export file — <span class="font-medium">.txt, .vtt, .srt</span>
              </span>
              <.live_file_input upload={@uploads.transcript} class="hidden" />
            </label>

            <div
              :for={entry <- @uploads.transcript.entries}
              class="mt-2 flex items-center justify-center gap-2 text-sm"
            >
              <.icon name="hero-document-text" class="h-4 w-4 text-base-content/50" />
              <span class="font-medium">{entry.client_name}</span>
              <button
                type="button"
                id={"cancel-upload-#{entry.ref}"}
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                aria-label="Remove file"
                class="text-base-content/50 transition-colors hover:text-error"
              >
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </button>
              <p :for={error <- upload_errors(@uploads.transcript, entry)} class="text-error">
                {upload_error_message(error)}
              </p>
            </div>

            <p
              :for={error <- upload_errors(@uploads.transcript)}
              class="mt-2 text-center text-sm text-error"
            >
              {upload_error_message(error)}
            </p>
          </div>

          <p id="privacy-note" class="mt-3 text-center text-sm text-base-content/50">
            Your transcript is only used to produce your Action Points — never shared.
          </p>

          <button class="btn btn-primary w-full mt-4" phx-disable-with="Starting…">
            Extract Action Points
          </button>
        </.form>

        <button
          type="button"
          id="load-sample"
          phx-click="load_sample"
          phx-disable-with="Loading the sample…"
          class="btn btn-ghost btn-sm mx-auto mt-3 flex text-base-content/70"
        >
          No transcript to hand? Try the sample meeting
        </button>

        <section id="how-it-works" class="mt-20">
          <h2 class="text-center text-2xl font-bold">How it works</h2>
          <ol class="mt-8 grid gap-6 sm:grid-cols-3">
            <li class="card bg-base-200 p-5">
              <span class="text-sm font-semibold text-primary">Step 1</span>
              <h3 class="mt-1 font-semibold">Paste a transcript</h3>
              <p class="mt-2 text-sm text-base-content/70">
                Zoom, Teams, and Meet already export one. Paste the text or drop the
                .txt, .vtt, or .srt file — timestamps get cleaned up for you.
              </p>
            </li>
            <li class="card bg-base-200 p-5">
              <span class="text-sm font-semibold text-primary">Step 2</span>
              <h3 class="mt-1 font-semibold">Review the Action Points</h3>
              <p class="mt-2 text-sm text-base-content/70">
                Every commitment comes back with a title, context, an assignee guess,
                and any due date said aloud. Reject the noise, edit the keepers.
              </p>
            </li>
            <li class="card bg-base-200 p-5">
              <span class="text-sm font-semibold text-primary">Step 3</span>
              <h3 class="mt-1 font-semibold">Push to Linear</h3>
              <p class="mt-2 text-sm text-base-content/70">
                One click creates the accepted Action Points as real Linear issues —
                with links back to each one, so nothing is lost in the meeting again.
              </p>
            </li>
          </ol>
        </section>

        <section id="pricing" class="mt-16 pb-20 text-center">
          <h2 class="text-2xl font-bold">Simple pricing</h2>
          <p class="mx-auto mt-3 max-w-md text-base-content/70">
            Your first meeting is free — every new account starts with one Credit.
            After that, £5 buys a Pack of 15 meetings. No subscription.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:session_token, session["anon_session_token"])
     |> assign(:peer_ip, peer_ip(socket))
     |> assign_form(Meetings.change_extraction(%Extraction{}))
     |> allow_upload(:transcript,
       accept: ~w(.txt .vtt .srt),
       max_entries: 1,
       max_file_size: 2_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :transcript, ref)}
  end

  def handle_event("extract", %{"extraction" => params}, socket) do
    # An uploaded file takes precedence over anything left in the textarea.
    attrs = consume_transcript_upload(socket) || params

    start_extraction(socket, attrs)
  end

  def handle_event("load_sample", _params, socket) do
    start_extraction(socket, %{"transcript_text" => @sample_transcript})
  end

  defp start_extraction(socket, attrs) do
    case Meetings.create_extraction(
           socket.assigns.current_scope,
           socket.assigns.session_token,
           attrs,
           ip: socket.assigns.peer_ip
         ) do
      {:ok, extraction} ->
        Meetings.start_extraction(extraction)
        {:noreply, push_navigate(socket, to: ~p"/review/#{extraction}")}

      {:error, :out_of_credits} ->
        {:noreply,
         socket
         |> put_flash(:error, "You're out of Credits — a Pack covers your next 15 meetings.")
         |> push_navigate(to: ~p"/buy")}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The Demo is rate-limited — try again in a while, " <>
             "or create a free account for your Free Meeting."
         )}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp consume_transcript_upload(socket) do
    socket
    |> consume_uploaded_entries(:transcript, fn %{path: path}, entry ->
      {:ok,
       %{
         "transcript_text" => File.read!(path),
         "source_format" => Transcript.format_from_filename(entry.client_name)
       }}
    end)
    |> List.first()
  end

  defp upload_error_message(:too_large), do: "That file is too large (2 MB max)."

  defp upload_error_message(:not_accepted),
    do: "That file type isn't supported — use .txt, .vtt, or .srt."

  defp upload_error_message(:too_many_files), do: "Attach just one file."
  defp upload_error_message(_other), do: "Something went wrong with that upload — try again."

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
