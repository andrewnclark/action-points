defmodule ActionPointsWeb.UserLive.Registration do
  use ActionPointsWeb, :live_view

  alias ActionPoints.Accounts
  alias ActionPoints.Accounts.User
  alias ActionPoints.Meetings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Two ways to arrive, and they are not the same moment: a visitor who
      has just been stopped at Push is here for their Review, and one who came
      off the landing page is here for the Free Meeting. The page leads with
      whichever it is. --%>
      <Layouts.form_page
        eyebrow={if @review_kept_count, do: "Review saved", else: "Account"}
        title={if @pushable?, do: "Create an account to Push.", else: "Create an account."}
      >
        <:lead>
          <%= if @pushable? do %>
            Pushing creates real tasks in your Task Sink, so it takes an account.
            Signing up takes an email address — and the Free Meeting that comes with it
            means your next Extraction costs nothing.
          <% else %>
            Every account starts with a Free Meeting, so your first Extraction costs
            nothing. No subscription: after that, Credits come in Packs.
          <% end %>
        </:lead>

        <Layouts.review_kept count={@review_kept_count} />

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            placeholder="you@company.com"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <button class="btn btn-primary mt-2 w-full" phx-disable-with="Creating account…">
            Create account
          </button>

          <p class="mt-3 text-xs text-base-content/65">
            We email you a link to log in — there is no password to choose.
          </p>
        </.form>

        <:footer>
          Already have an account? <.link
            navigate={~p"/users/log-in"}
            class="text-accent hover:underline"
          >Log in</.link>.
        </:footer>
      </Layouts.form_page>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: ActionPointsWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)
    kept_count = Meetings.session_review_pushable_count(session["anon_session_token"])

    {:ok,
     socket
     |> assign(:review_kept_count, kept_count)
     # A Review whose Action Points were all rejected still carries over, but it
     # has nothing to Push — so the page must not promise one.
     |> assign(:pushable?, kept_count not in [nil, 0])
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        # The address travels in the flash rather than the URL — the login
        # screen names it so the visitor can check they typed it correctly,
        # and an email address has no business in a query string.
        {:noreply,
         socket
         |> put_flash(:email, user.email)
         |> push_navigate(to: ~p"/users/log-in?magic_link=sent")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
