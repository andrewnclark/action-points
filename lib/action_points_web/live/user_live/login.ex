defmodule ActionPointsWeb.UserLive.Login do
  use ActionPointsWeb, :live_view

  alias ActionPoints.Accounts

  @impl true
  def render(%{magic_link: kind} = assigns) when kind in [:sent, :requested] do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Asking for a link ends on a screen, not on a toast: the visitor has
      to leave for their inbox and come back, and a message that evaporates on
      the way is no use to them there. --%>
      <Layouts.auth_page eyebrow="Login link" title="Check your email.">
        <:lead>
          <%= if @magic_link == :sent do %>
            Your account is created. The link logs you in — it works once.
          <% else %>
            The link logs you in — it works once.
          <% end %>
        </:lead>

        <div id="magic-link-sent">
          <p class="flex gap-3">
            <.icon name="hero-envelope" class="mt-0.5 size-5 shrink-0 text-primary" />
            <span>
              <%= if @magic_link == :sent do %>
                We sent it to
              <% else %>
                If that address has an account, we sent a link to
              <% end %>
              <span class="font-semibold">{@email || "your address"}</span>.
            </span>
          </p>

          <.local_mailbox_note :if={local_mail_adapter?()} class="mt-5" />

          <p class="mt-5 border-t border-base-300/60 pt-4 text-xs text-base-content/65">
            Nothing arrived? Check spam, or <.link
              navigate={~p"/users/log-in"}
              class="text-accent hover:underline"
              phx-no-format
            >use a different address</.link>.
          </p>
        </div>
      </Layouts.auth_page>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Re-authenticating is not logging in: the reader is already inside and
      is being asked to prove it before changing account details. --%>
      <Layouts.auth_page
        eyebrow={if @current_scope, do: "Confirm it's you", else: "Account"}
        title={if @current_scope, do: "Log in again.", else: "Log in."}
      >
        <:lead>
          <%= if @current_scope do %>
            Changing your account details needs a fresh login. We'll send a link to the
            address on the account.
          <% else %>
            We email you a link — there is no password to remember, unless you chose one.
          <% end %>
        </:lead>

        <.local_mailbox_note :if={local_mail_adapter?()} class="mb-5" />

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            placeholder="you@company.com"
            autocomplete="username"
            spellcheck="false"
            required
            {focus_on_mount(@current_scope)}
          />
          <button class="btn btn-primary mt-2 w-full">
            Email me a login link
          </button>
        </.form>

        <%!-- A password is the exception, not the alternative on offer: it exists
        only for someone who set one in Settings, so it folds away until asked
        for rather than doubling the screen. --%>
        <details class="group mt-6 border-t border-base-300/60 pt-4">
          <summary class="cursor-pointer list-none text-xs text-base-content/65 hover:text-base-content">
            <.icon
              name="hero-chevron-right-micro"
              class="size-3.5 transition-transform group-open:rotate-90"
            /> Log in with a password instead
          </summary>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/users/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
            class="mt-4"
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              spellcheck="false"
            />
            <button
              class="btn btn-primary mt-2 w-full"
              name={@form[:remember_me].name}
              value="true"
            >
              Log in and stay logged in
            </button>
            <button class="btn btn-ghost mt-2 w-full font-normal text-base-content/70">
              Log in only this time
            </button>
          </.form>
        </details>

        <:footer :if={is_nil(@current_scope)}>
          No account yet?
          <.link navigate={~p"/users/register"} class="text-accent hover:underline">
            Create one
          </.link>
          — it comes with a Free Meeting.
        </:footer>
      </Layouts.auth_page>
    </Layouts.app>
    """
  end

  # Autofocus belongs on a field there is something to type in. Re-authenticating
  # fixes the address to the one on the account, so the cursor stays away.
  defp focus_on_mount(nil), do: %{"phx-mounted" => JS.focus()}
  defp focus_on_mount(_scope), do: %{}

  # Development only: the login link never leaves the machine, so the screen
  # says where it landed instead of leaving the developer waiting on an inbox.
  attr :class, :string, default: nil

  defp local_mailbox_note(assigns) do
    ~H"""
    <p class={[
      "flex gap-2.5 rounded-box border border-base-300 bg-base-300/30 p-3 text-xs text-base-content/70",
      @class
    ]}>
      <.icon name="hero-wrench-screwdriver-micro" class="mt-0.5 size-3.5 shrink-0" />
      <span>
        Local mail adapter: nothing is actually sent.
        <.link href="/dev/mailbox" class="text-accent hover:underline">Open the mailbox</.link>
        to read it.
      </span>
    </p>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, email: email, trigger_submit: false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # `sent` means the account definitely exists — registration just made it.
    # `requested` must not say whether it does, so the two states are told apart
    # here rather than in the copy.
    magic_link =
      case params["magic_link"] do
        "sent" -> :sent
        "requested" -> :requested
        _ -> nil
      end

    {:noreply, assign(socket, :magic_link, magic_link)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(:email, email)
     |> push_navigate(to: ~p"/users/log-in?magic_link=requested")}
  end

  defp local_mail_adapter? do
    Application.get_env(:action_points, ActionPoints.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
