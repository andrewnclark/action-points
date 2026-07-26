defmodule ActionPointsWeb.UserLive.LoginTest do
  use ActionPointsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ActionPoints.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, "#login_form_magic button", "Email me a login link")
      assert has_element?(lv, "#login_form_password")
      assert has_element?(lv, "main a", "Create one")
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, sent, _html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in?magic_link=requested")

      # Naming the address the visitor typed discloses nothing; the wording
      # still refuses to confirm whether an account exists.
      assert has_element?(sent, "#magic-link-sent", user.email)
      assert has_element?(sent, "#magic-link-sent", "If that address has an account")

      assert ActionPoints.Repo.get_by!(ActionPoints.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, sent, _html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in?magic_link=requested")

      assert has_element?(sent, "#magic-link-sent", "If that address has an account")
    end

    test "the sent screen leads back to the form for a mistyped address", %{conn: conn} do
      {:ok, sent, _html} = live(conn, ~p"/users/log-in?magic_link=requested")

      refute has_element?(sent, "#login_form_magic")

      {:ok, login, _html} =
        sent
        |> element("#magic-link-sent a", "use a different address")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert has_element?(login, "#login_form_magic")
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the sign-up link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, registration, _html} =
        lv
        |> element("main a", "Create one")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert has_element?(registration, "#registration_form")
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Confirm it&#39;s you"
      # Someone already signed in is not being sold an account.
      refute has_element?(lv, "main a", "Create one")
      assert has_element?(lv, "#login_form_magic button", "Email me a login link")

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_magic_email" value="#{user.email}")
    end
  end
end
