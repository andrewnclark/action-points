defmodule ActionPointsWeb.CreditBalanceTest do
  use ActionPointsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ActionPoints.AccountsFixtures

  alias ActionPoints.Accounts

  describe "credit balance in the nav" do
    test "signup through the magic link shows a balance of one Credit", %{conn: conn} do
      email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      lv
      |> form("#registration_form", user: %{email: email})
      |> render_submit()

      user = Accounts.get_user_by_email(email)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      form = form(lv, "#confirmation_form", %{"user" => %{"token" => token}})
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      html = conn |> get(~p"/") |> html_response(200)

      balance_text =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#credit-balance")
        |> LazyHTML.text()
        |> String.split()
        |> Enum.join(" ")

      assert balance_text == "1 Credit"
    end

    test "the nav shows no balance when logged out", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#credit-balance")
             |> Enum.empty?()
    end
  end
end
