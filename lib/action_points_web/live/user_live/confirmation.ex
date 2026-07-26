defmodule ActionPointsWeb.UserLive.Confirmation do
  use ActionPointsWeb, :live_view

  alias ActionPoints.Accounts
  alias ActionPoints.Meetings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- The last click of signing up, and the first of coming back — the same
      link, two different moments, so the page says which one this is. --%>
      <Layouts.auth_page
        eyebrow={if @user.confirmed_at, do: "Login link", else: "New account"}
        title={if @user.confirmed_at, do: "Welcome back.", else: "Confirm your account."}
      >
        <:lead>
          <%= if @user.confirmed_at do %>
            Logging in as <span class="font-medium text-base-content">{@user.email}</span>.
          <% else %>
            Login links will go to <span class="font-medium text-base-content">{@user.email}</span>.
            Confirming logs you in, and the Free Meeting on the account means your first
            Extraction costs nothing.
          <% end %>
        </:lead>

        <Layouts.review_kept count={@review_kept_count} />

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="Confirming…"
            class="btn btn-primary w-full"
          >
            Confirm and stay logged in
          </button>
          <button
            phx-disable-with="Confirming…"
            class="btn btn-ghost mt-2 w-full font-normal text-base-content/70"
          >
            Confirm and log in only this time
          </button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <button phx-disable-with="Logging in…" class="btn btn-primary w-full">
              Log in
            </button>
          <% else %>
            <button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Logging in…"
              class="btn btn-primary w-full"
            >
              Keep me logged in on this device
            </button>
            <button
              phx-disable-with="Logging in…"
              class="btn btn-ghost mt-2 w-full font-normal text-base-content/70"
            >
              Log me in only this time
            </button>
          <% end %>
        </.form>

        <p
          :if={!@user.confirmed_at}
          class="mt-5 border-t border-base-300/60 pt-4 text-xs text-base-content/65"
        >
          Logging in by emailed link is the default. If you'd rather type a password,
          set one in Settings.
        </p>
      </Layouts.auth_page>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok,
       socket
       |> assign(user: user, form: form, trigger_submit: false)
       |> assign(
         :review_kept_count,
         Meetings.session_review_pushable_count(session["anon_session_token"])
       ), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "That login link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
