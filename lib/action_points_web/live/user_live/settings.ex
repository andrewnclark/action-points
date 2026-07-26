defmodule ActionPointsWeb.UserLive.Settings do
  use ActionPointsWeb, :live_view

  on_mount {ActionPointsWeb.UserAuth, :require_sudo_mode}

  alias ActionPoints.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md pt-10">
        <Layouts.page_lead eyebrow="Account" title="Your account.">
          <:lead>The address your login links go to, and an optional password.</:lead>
        </Layouts.page_lead>

        <%!-- The two facts an account holder comes here to check, before the two
        things they came here to change. --%>
        <dl class="mt-8 grid gap-px overflow-hidden rounded-box border border-base-300 bg-base-300 sm:grid-cols-2">
          <div class="bg-base-200 p-4">
            <dt class="text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
              Email
            </dt>
            <dd class="mt-1 truncate font-medium">{@current_email}</dd>
          </div>
          <div class="bg-base-200 p-4">
            <dt class="text-[11px] font-medium tracking-[0.08em] text-base-content/65 uppercase">
              Credits
            </dt>
            <dd class="mt-1 font-medium">
              {@current_scope.credit_balance}
              <.link navigate={~p"/buy"} class="ml-1 text-xs font-normal text-accent hover:underline">
                Buy a Pack
              </.link>
            </dd>
          </div>
        </dl>

        <section class="mt-4 rounded-box border border-base-300 bg-base-200 p-6">
          <h2 class="font-semibold">Change email</h2>
          <p class="mt-1 text-base-content/70">
            We send a confirmation link to the new address. The change lands when you
            open it — until then, login links keep going to the old one.
          </p>

          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
            class="mt-5"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label="New email"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <button class="btn btn-primary mt-2" phx-disable-with="Sending the link…">
              Change email
            </button>
          </.form>
        </section>

        <section class="mt-4 rounded-box border border-base-300 bg-base-200 p-6">
          <h2 class="font-semibold">
            {if @has_password?, do: "Change password", else: "Set a password"}
          </h2>
          <p class="mt-1 text-base-content/70">
            <%= if @has_password? do %>
              The new password replaces the old one everywhere. Logging in by emailed
              link keeps working either way.
            <% else %>
              Optional. Logging in by emailed link needs no password — set one only if
              you'd rather type it.
            <% end %>
          </p>

          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update-password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
            class="mt-5"
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              spellcheck="false"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              spellcheck="false"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm new password"
              autocomplete="new-password"
              spellcheck="false"
            />
            <button class="btn btn-primary mt-2" phx-disable-with="Saving…">
              Save password
            </button>
          </.form>
        </section>

        <p class="mt-4 text-center text-xs text-base-content/65">
          Pushing to Linear is set up in <.link
            navigate={~p"/settings/sink"}
            class="text-accent hover:underline"
            phx-no-format
          >Sink Settings</.link>.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:has_password?, not is_nil(user.hashed_password))
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
