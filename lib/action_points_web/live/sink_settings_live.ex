defmodule ActionPointsWeb.SinkSettingsLive do
  @moduledoc """
  Sink Settings: where an account points ActionPoints at its Task Sink. The
  screen is one panel in three modes — enter a key, pick a team, or look at
  what is connected — and the lead above it says which moment this is, because
  "Connect Linear" is a lie on a screen that is already connected.
  """

  use ActionPointsWeb, :live_view

  alias ActionPoints.Sinks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.form_page eyebrow="Task Sink" title={moment(@mode, @connection).title}>
        <:lead>{moment(@mode, @connection).lead}</:lead>

        <%= case @mode do %>
          <% :key_entry -> %>
            <.form for={@key_form} id="sink-key-form" phx-submit="validate_key">
              <.input
                field={@key_form[:api_key]}
                type="password"
                label="Linear personal API key"
                autocomplete="off"
                spellcheck="false"
                required
              />
              <p class="mt-1 text-xs text-base-content/65">
                <%!-- &rsaquo; rather than an arrow: the self-hosted Inter subset
                has no U+2192, and a breadcrumb is not worth a font fallback. --%>
                Create one in Linear under Settings &rsaquo; Security &amp; access &rsaquo;
                personal API keys. We check it with Linear before saving anything.
              </p>

              <.flow_error :if={@flow_error} id="sink-key-error">{@flow_error}</.flow_error>

              <div class="mt-5 flex flex-wrap items-center gap-2">
                <button
                  id="connect-sink"
                  class="btn btn-primary"
                  phx-disable-with="Checking the key…"
                >
                  Connect
                </button>
                <button
                  :if={@connection}
                  id="cancel-replace"
                  type="button"
                  class="btn btn-ghost text-base-content/70"
                  phx-click="cancel_replace"
                >
                  Cancel
                </button>
              </div>
            </.form>
          <% :team_pick -> %>
            <.form for={@team_form} id="sink-team-form" phx-submit="save_team">
              <.input
                field={@team_form[:team_id]}
                type="select"
                label="Linear team"
                options={Enum.map(@teams, &{&1.name, &1.id})}
                required
              />
              <p class="mt-1 text-xs text-base-content/65">
                You can change the team later by replacing the key.
              </p>

              <.flow_error :if={@flow_error} id="sink-team-error">{@flow_error}</.flow_error>

              <div class="mt-5 flex flex-wrap items-center gap-2">
                <button id="save-sink-team" class="btn btn-primary" phx-disable-with="Saving…">
                  Save connection
                </button>
                <button
                  id="cancel-team-pick"
                  type="button"
                  class="btn btn-ghost text-base-content/70"
                  phx-click="cancel_team_pick"
                >
                  Start over
                </button>
              </div>
            </.form>
          <% :connected -> %>
            <div id="sink-connection">
              <div class="flex items-center justify-between gap-4">
                <span class="font-semibold">Linear</span>
                <span class="inline-flex items-center gap-2 rounded-full border border-success/40 px-3 py-1 text-[11px] font-medium tracking-[0.07em] text-base-content/65 uppercase">
                  <span
                    class="size-1.5 rounded-full bg-success ring-3 ring-success/15"
                    aria-hidden="true"
                  /> Connected
                </span>
              </div>

              <dl class="mt-5 divide-y divide-base-300/60 border-y border-base-300/60 text-sm">
                <div class="flex items-center justify-between gap-4 py-3">
                  <dt class="text-base-content/65">API key</dt>
                  <dd id="sink-masked-key" class="truncate font-mono">
                    &bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;{@connection.api_key_last4}
                  </dd>
                </div>
                <div class="flex items-center justify-between gap-4 py-3">
                  <dt class="text-base-content/65">Team</dt>
                  <dd id="sink-team-name" class="truncate font-medium">
                    {@connection.team_name}
                  </dd>
                </div>
              </dl>

              <div class="mt-5 flex flex-wrap items-center gap-2">
                <button id="replace-key" class="btn btn-soft btn-sm" phx-click="replace_key">
                  Replace key
                </button>
                <button
                  id="disconnect-sink"
                  class="btn btn-ghost btn-sm text-base-content/70"
                  phx-click="disconnect"
                  data-confirm="Disconnect Linear? You can't Push until you reconnect."
                >
                  Disconnect
                </button>
              </div>

              <%!-- The question a Disconnect button raises before it is clicked:
                whether it reaches back into work already Pushed. It does not. --%>
              <p class="mt-4 text-xs text-base-content/65">
                Disconnecting stops Pushes. Issues already created in Linear stay
                where they are.
              </p>
            </div>

            <div id="assignee-mappings" class="mt-8">
              <div class="flex items-center justify-between gap-4">
                <h2 class="text-sm font-semibold">Assignee Mappings</h2>
                <button
                  :if={is_nil(@mapping_sink_error)}
                  id="add-mapping-toggle"
                  type="button"
                  class="btn btn-soft btn-xs"
                  phx-click="toggle_add_mapping"
                >
                  <.icon name="hero-plus-micro" class="size-3.5" />
                  {if @adding_mapping?, do: "Cancel", else: "Add mapping"}
                </button>
              </div>
              <%!-- A mapping is usually born at Push, without the user ever
              visiting this screen — this line says so, rather than letting an
              empty table read as broken. --%>
              <p class="mt-1 text-xs text-base-content/65">
                A name Review resolves once resolves the same way in every later meeting.
                They're usually created by Pushing, not here.
              </p>

              <p :if={@mapping_sink_error} class="mt-3 text-xs text-warning">
                Linear's member list couldn't be reached, so mappings can't be added or changed
                right now.
              </p>

              <.flow_error :if={@mapping_flow_error} id="mapping-error">
                {@mapping_flow_error}
              </.flow_error>

              <.form
                :if={@adding_mapping?}
                for={@add_mapping_form}
                id="add-mapping-form"
                phx-submit="add_mapping"
                class="mt-3 flex flex-wrap items-end gap-2 rounded-box border border-base-300 bg-base-200 p-3"
              >
                <.input
                  field={@add_mapping_form[:guess]}
                  type="text"
                  label="Guessed name"
                  placeholder="Bob"
                />
                <.input
                  field={@add_mapping_form[:sink_user_id]}
                  type="select"
                  label="Member"
                  prompt="Pick a member"
                  options={sink_user_options(@mapping_sink_users)}
                />
                <button id="save-mapping" class="btn btn-primary btn-xs">Save</button>
              </.form>

              <ul
                id="mapping-list"
                phx-update="stream"
                class="mt-3 divide-y divide-base-300/60 border-y border-base-300/60 text-sm"
              >
                <li id="no-mappings" class="hidden py-3 text-base-content/65 only:block">
                  No Assignee Mappings yet.
                </li>
                <li
                  :for={{dom_id, mapping} <- @streams.assignee_mappings}
                  id={dom_id}
                  class="flex items-center justify-between gap-3 py-2.5"
                >
                  <% edit_form = to_form(%{"sink_user_id" => mapping.sink_user_id}, as: :mapping) %>
                  <%= if @editing_mapping_id == mapping.id do %>
                    <.form
                      for={edit_form}
                      id={"edit-mapping-#{mapping.id}"}
                      phx-submit="save_mapping_edit"
                      phx-value-id={mapping.id}
                      class="flex flex-1 flex-wrap items-end gap-2"
                    >
                      <span class="truncate font-medium">{mapping.normalized_guess}</span>
                      <.input
                        field={edit_form[:sink_user_id]}
                        type="select"
                        class="select select-xs w-auto"
                        options={sink_user_options(@mapping_sink_users)}
                      />
                      <button class="btn btn-primary btn-xs">Save</button>
                      <button
                        id={"#{dom_id}-cancel"}
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="cancel_mapping_edit"
                        phx-value-id={mapping.id}
                      >
                        Cancel
                      </button>
                    </.form>
                  <% else %>
                    <div class="min-w-0">
                      <p class="truncate font-medium">{mapping.normalized_guess}</p>
                      <p class="truncate text-base-content/65">
                        {mapping.display_name}<span :if={mapping.handle}>(@{mapping.handle})</span>
                      </p>
                    </div>
                    <div class="flex shrink-0 gap-1">
                      <button
                        id={"#{dom_id}-edit"}
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="edit_mapping"
                        phx-value-id={mapping.id}
                        disabled={not is_nil(@mapping_sink_error)}
                      >
                        Edit
                      </button>
                      <button
                        id={"#{dom_id}-delete"}
                        type="button"
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="delete_mapping"
                        phx-value-id={mapping.id}
                      >
                        Delete
                      </button>
                    </div>
                  <% end %>
                </li>
              </ul>
            </div>
        <% end %>

        <:footer>
          Your email and Credits are in <.link
            navigate={~p"/users/settings"}
            class="text-accent hover:underline"
            phx-no-format
          >Settings</.link>.
        </:footer>
      </Layouts.form_page>
    </Layouts.app>
    """
  end

  # The four moments this screen has, each with the line that names it. Entering
  # a key for the first time and replacing a working one are the same :key_entry
  # form and mean opposite things, so they are separate moments here — the panel
  # can't tell them apart, but the reader must.
  defp moment(:connected, _connection),
    do: %{
      title: "Linear is connected.",
      lead:
        "Accepted Action Points Push straight into your team. " <>
          "Nothing is created there until you Push."
    }

  defp moment(:team_pick, _connection),
    do: %{
      title: "Choose a team.",
      lead: "That key works. Pushed Action Points land in the team you pick."
    }

  defp moment(:key_entry, nil),
    do: %{
      title: "Connect Linear.",
      lead: "Linear is your Task Sink: the Action Points you Push become issues in it."
    }

  defp moment(:key_entry, _connection),
    do: %{
      title: "Replace your key.",
      lead:
        "We check the new key with Linear first. " <>
          "Your current connection keeps working until it does."
    }

  # Whatever went wrong between here and Linear, said in place under the field
  # that caused it — the same error surface the rest of the app uses.
  attr :id, :string, required: true
  slot :inner_block, required: true

  defp flow_error(assigns) do
    ~H"""
    <div
      id={@id}
      class="mt-5 flex gap-3 rounded-box border border-error/40 bg-error/10 p-4"
      role="alert"
    >
      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-error" />
      <p class="text-base-content/70">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    connection = Sinks.get_connection(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Task Sink")
     |> assign(:connection, connection)
     |> assign(:mode, if(connection, do: :connected, else: :key_entry))
     |> assign_mapping_sink_users()
     |> refresh_mappings()
     |> assign(:adding_mapping?, false)
     |> assign(:editing_mapping_id, nil)
     |> assign(:mapping_flow_error, nil)
     |> assign(:add_mapping_form, to_form(%{"guess" => "", "sink_user_id" => ""}, as: :mapping))
     |> reset_flow()}
  end

  @impl true
  def handle_event("validate_key", %{"connection" => %{"api_key" => api_key}}, socket) do
    api_key = String.trim(api_key)

    case Sinks.validate_key(api_key) do
      {:ok, []} ->
        {:noreply,
         assign(socket, :flow_error, "That key works, but it has no teams to Push into.")}

      {:ok, teams} ->
        {:noreply,
         socket
         |> assign(:pending_key, api_key)
         |> assign(:teams, teams)
         |> assign(:flow_error, nil)
         |> assign(:mode, :team_pick)}

      {:error, reason} ->
        {:noreply, assign(socket, :flow_error, failure_message(reason))}
    end
  end

  def handle_event("save_team", %{"connection" => %{"team_id" => team_id}}, socket) do
    case Enum.find(socket.assigns.teams, &(&1.id == team_id)) do
      nil ->
        {:noreply, assign(socket, :flow_error, "Pick a team from the list.")}

      team ->
        attrs = %{
          api_key: socket.assigns.pending_key,
          team_id: team.id,
          team_name: team.name
        }

        case Sinks.connect(socket.assigns.current_scope, attrs) do
          {:ok, _connection} ->
            {:noreply,
             socket
             |> assign(:connection, Sinks.get_connection(socket.assigns.current_scope))
             |> assign(:mode, :connected)
             |> assign_mapping_sink_users()
             |> refresh_mappings()
             |> reset_flow()
             |> put_flash(
               :info,
               "Linear connected. Pushed Action Points will land in #{team.name}."
             )}

          {:error, _changeset} ->
            {:noreply,
             assign(socket, :flow_error, "The connection could not be saved. Try again.")}
        end
    end
  end

  def handle_event("replace_key", _params, socket) do
    {:noreply, socket |> assign(:mode, :key_entry) |> reset_flow()}
  end

  def handle_event("cancel_replace", _params, socket) do
    {:noreply, socket |> assign(:mode, :connected) |> reset_flow()}
  end

  def handle_event("cancel_team_pick", _params, socket) do
    {:noreply, socket |> assign(:mode, :key_entry) |> reset_flow()}
  end

  def handle_event("disconnect", _params, socket) do
    :ok = Sinks.disconnect(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:connection, nil)
     |> assign(:mode, :key_entry)
     |> assign_mapping_sink_users()
     |> refresh_mappings()
     |> reset_flow()
     |> put_flash(:info, "Linear disconnected. You can't Push until you reconnect.")}
  end

  def handle_event("toggle_add_mapping", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding_mapping?, not socket.assigns.adding_mapping?)
     |> assign(:mapping_flow_error, nil)
     |> assign(:add_mapping_form, to_form(%{"guess" => "", "sink_user_id" => ""}, as: :mapping))}
  end

  def handle_event("add_mapping", %{"mapping" => params}, socket) do
    guess = params["guess"] |> to_string() |> String.trim()
    sink_user = Enum.find(socket.assigns.mapping_sink_users, &(&1.id == params["sink_user_id"]))

    case {guess, sink_user} do
      {"", _} ->
        {:noreply, assign(socket, :mapping_flow_error, "Enter a guessed name.")}

      {_guess, nil} ->
        {:noreply, assign(socket, :mapping_flow_error, "Pick a member.")}

      {guess, sink_user} ->
        {:ok, _mapping} =
          Sinks.put_assignee_mapping(socket.assigns.current_scope, guess, sink_user)

        {:noreply,
         socket
         |> assign(:adding_mapping?, false)
         |> assign(:mapping_flow_error, nil)
         |> refresh_mappings()
         |> put_flash(:info, "Mapped \"#{guess}\" to #{sink_user.name}.")}
    end
  end

  def handle_event("edit_mapping", %{"id" => id}, socket) do
    mapping = fetch_mapping!(socket, id)

    # A stream item only re-renders when re-inserted (AGENTS.md) — changing
    # `editing_mapping_id` alone would leave this row showing its old markup.
    {:noreply,
     socket
     |> assign(:editing_mapping_id, mapping.id)
     |> assign(:mapping_flow_error, nil)
     |> stream_insert(:assignee_mappings, mapping)}
  end

  def handle_event("cancel_mapping_edit", %{"id" => id}, socket) do
    mapping = fetch_mapping!(socket, id)

    {:noreply,
     socket
     |> assign(:editing_mapping_id, nil)
     |> stream_insert(:assignee_mappings, mapping)}
  end

  def handle_event(
        "save_mapping_edit",
        %{"id" => id, "mapping" => %{"sink_user_id" => sink_user_id}},
        socket
      ) do
    case Enum.find(socket.assigns.mapping_sink_users, &(&1.id == sink_user_id)) do
      nil ->
        {:noreply, assign(socket, :mapping_flow_error, "Pick a member.")}

      sink_user ->
        mapping = fetch_mapping!(socket, id)
        {:ok, _mapping} = Sinks.update_assignee_mapping(mapping, sink_user)

        {:noreply,
         socket
         |> assign(:editing_mapping_id, nil)
         |> assign(:mapping_flow_error, nil)
         |> refresh_mappings()
         |> put_flash(:info, "Updated the mapping for \"#{mapping.normalized_guess}\".")}
    end
  end

  def handle_event("delete_mapping", %{"id" => id}, socket) do
    mapping = fetch_mapping!(socket, id)
    {:ok, _mapping} = Sinks.delete_assignee_mapping(mapping)

    {:noreply,
     socket
     |> stream_delete(:assignee_mappings, mapping)
     |> put_flash(:info, "Removed the mapping for \"#{mapping.normalized_guess}\".")}
  end

  # The live member list backing the mapping pickers — fetched once per
  # connection change, not on every render, since Assignee Mappings only need
  # it while this screen is open (Review does its own live fetch, ADR-0007).
  defp assign_mapping_sink_users(socket) do
    case socket.assigns.connection && Sinks.list_sink_users(socket.assigns.current_scope) do
      {:ok, users} ->
        socket |> assign(:mapping_sink_users, users) |> assign(:mapping_sink_error, nil)

      {:error, reason} ->
        socket |> assign(:mapping_sink_users, []) |> assign(:mapping_sink_error, reason)

      nil ->
        socket |> assign(:mapping_sink_users, []) |> assign(:mapping_sink_error, nil)
    end
  end

  defp refresh_mappings(socket) do
    stream(socket, :assignee_mappings, Sinks.list_assignee_mappings(socket.assigns.current_scope),
      reset: true
    )
  end

  defp fetch_mapping!(socket, id) do
    Sinks.get_assignee_mapping!(socket.assigns.current_scope, id)
  end

  # Select options for a mapping's target member — the same list, shaped the
  # same way, for both the add form and each row's edit form.
  defp sink_user_options(sink_users) do
    Enum.map(sink_users, &{"#{&1.name} (@#{&1.handle})", &1.id})
  end

  defp reset_flow(socket) do
    socket
    |> assign(:pending_key, nil)
    |> assign(:teams, [])
    |> assign(:flow_error, nil)
    |> assign(:key_form, to_form(%{"api_key" => ""}, as: :connection))
    |> assign(:team_form, to_form(%{"team_id" => ""}, as: :connection))
  end

  defp failure_message(:invalid_key),
    do: "Linear rejected that API key. Check you pasted the whole key and try again."

  defp failure_message(:rate_limited),
    do: "Linear is rate-limiting requests right now. Wait a moment and try again."

  defp failure_message(:unavailable),
    do: "Linear could not be reached. Check your connection and try again."

  defp failure_message(_reason),
    do: "Linear returned an unexpected response. Try again in a moment."
end
