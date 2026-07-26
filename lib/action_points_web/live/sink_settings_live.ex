defmodule ActionPointsWeb.SinkSettingsLive do
  use ActionPointsWeb, :live_view

  alias ActionPoints.Sinks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Connect Linear
          <:subtitle>
            Pushed Action Points become real issues in your Linear workspace
          </:subtitle>
        </.header>
      </div>

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
            <p class="mt-1 text-sm opacity-70">
              Create one in Linear under Settings &rarr; Security &amp; access &rarr; personal API keys.
              We check it with Linear before saving anything.
            </p>
            <p :if={@flow_error} id="sink-key-error" class="mt-2 text-sm text-error" role="alert">
              {@flow_error}
            </p>
            <div class="mt-4 flex items-center gap-3">
              <.button id="connect-sink" variant="primary" phx-disable-with="Checking key...">
                Connect
              </.button>
              <.button :if={@connection} id="cancel-replace" type="button" phx-click="cancel_replace">
                Cancel
              </.button>
            </div>
          </.form>
        <% :team_pick -> %>
          <.form for={@team_form} id="sink-team-form" phx-submit="save_team">
            <p class="mb-2 text-sm">
              Key looks good. Choose the Linear team new issues will land in:
            </p>
            <.input
              field={@team_form[:team_id]}
              type="select"
              label="Linear team"
              options={Enum.map(@teams, &{&1.name, &1.id})}
              required
            />
            <p :if={@flow_error} id="sink-team-error" class="mt-2 text-sm text-error" role="alert">
              {@flow_error}
            </p>
            <div class="mt-4 flex items-center gap-3">
              <.button id="save-sink-team" variant="primary" phx-disable-with="Saving...">
                Save connection
              </.button>
              <.button id="cancel-team-pick" type="button" phx-click="cancel_team_pick">
                Start over
              </.button>
            </div>
          </.form>
        <% :connected -> %>
          <div id="sink-connection" class="rounded-lg border border-base-300 p-4 space-y-3">
            <div class="flex items-center justify-between">
              <span class="font-semibold">Linear</span>
              <span class="rounded-full border border-current/30 px-2.5 py-0.5 text-xs font-medium">
                Connected
              </span>
            </div>
            <dl class="text-sm space-y-1">
              <div class="flex gap-2">
                <dt class="opacity-70">API key</dt>
                <dd id="sink-masked-key" class="font-mono">
                  &bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;{@connection.api_key_last4}
                </dd>
              </div>
              <div class="flex gap-2">
                <dt class="opacity-70">Team</dt>
                <dd id="sink-team-name">{@connection.team_name}</dd>
              </div>
            </dl>
            <div class="flex items-center gap-3">
              <.button id="replace-key" phx-click="replace_key">Replace key</.button>
              <.button
                id="disconnect-sink"
                phx-click="disconnect"
                data-confirm="Disconnect Linear? Pushing will stop working until you reconnect."
              >
                Disconnect
              </.button>
            </div>
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    connection = Sinks.get_connection(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Connect Linear")
     |> assign(:connection, connection)
     |> assign(:mode, if(connection, do: :connected, else: :key_entry))
     |> reset_flow()}
  end

  @impl true
  def handle_event("validate_key", %{"connection" => %{"api_key" => api_key}}, socket) do
    api_key = String.trim(api_key)

    case Sinks.validate_key(api_key) do
      {:ok, []} ->
        {:noreply,
         assign(socket, :flow_error, "That key works, but it has no teams to push issues into.")}

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
     |> reset_flow()
     |> put_flash(:info, "Linear disconnected.")}
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
