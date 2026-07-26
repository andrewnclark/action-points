defmodule ActionPointsWeb.LayoutShellTest do
  @moduledoc """
  The shell every screen is wrapped in. Only durable landmarks are asserted —
  that the wordmark, the navigation, the Credit balance and the theme toggle are
  present and lead somewhere. How they look is checked by eye, never here.
  """

  use ActionPointsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ActionPoints.AccountsFixtures

  test "the shell carries the wordmark, the navigation, and the theme toggle", %{conn: conn} do
    {:ok, home, _html} = live(conn, ~p"/")

    assert has_element?(home, "#app-nav")
    assert has_element?(home, "#app-nav a[href='/']", "ActionPoints")
    assert has_element?(home, "#theme-toggle")
  end

  test "a signed-out visitor is offered a way in from the navigation", %{conn: conn} do
    {:ok, home, _html} = live(conn, ~p"/")

    assert has_element?(home, "#app-nav a[href='/users/log-in']")
    assert has_element?(home, "#app-nav a[href='/users/register']")
    refute has_element?(home, "#app-nav #credit-balance")
  end

  test "a signed-in user gets their Credit balance and account links", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    {:ok, home, _html} = live(conn, ~p"/")

    assert has_element?(home, "#app-nav #credit-balance")
    assert has_element?(home, "#app-nav a[href='/settings/sink']")
    assert has_element?(home, "#app-nav a[href='/users/settings']")
    assert has_element?(home, "#app-nav a[href='/users/log-out']")
  end
end
