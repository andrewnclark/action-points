defmodule ActionPointsWeb.SinkSettingsTest do
  use ActionPointsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ActionPoints.Repo
  alias ActionPoints.Vault

  @api_key "lin_api_secret_key_abcd"

  setup :register_and_log_in_user

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_task_sink_pushes)
    end)
  end

  defp script_sink(script), do: Application.put_env(:action_points, :fake_task_sink, script)

  defp submit_key(view, api_key) do
    view
    |> form("#sink-key-form", connection: %{api_key: api_key})
    |> render_submit()
  end

  defp connect(view) do
    submit_key(view, @api_key)

    view
    |> form("#sink-team-form", connection: %{team_id: "team-2"})
    |> render_submit()
  end

  test "requires a signed-in user", %{conn: _conn} do
    conn = build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/settings/sink")
  end

  test "shows the key form when no connection exists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    assert has_element?(view, "#sink-key-form")
    refute has_element?(view, "#sink-connection")
  end

  test "the key form names the Task Sink and what a Push does", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    assert has_element?(view, "main header", "Task Sink")
    assert has_element?(view, "h1", "Connect Linear")
    assert has_element?(view, "main header p", "Action Points you Push become issues")
  end

  test "an invalid key shows the reason and stores nothing", %{conn: conn} do
    script_sink(validate: {:error, :invalid_key})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    assert submit_key(view, "bad-key") =~ "Linear rejected that API key"
    assert has_element?(view, "#sink-key-error")
    assert Repo.aggregate("sink_connections", :count) == 0
  end

  test "an unreachable sink shows the reason", %{conn: conn} do
    script_sink(validate: {:error, :unavailable})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    assert submit_key(view, @api_key) =~ "Linear could not be reached"
  end

  test "a key with no teams behind it is refused and stores nothing", %{conn: conn} do
    script_sink(teams: {:ok, []})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    submit_key(view, @api_key)

    assert has_element?(view, "#sink-key-error", "no teams to Push into")
    refute has_element?(view, "#sink-team-form")
    assert Repo.aggregate("sink_connections", :count) == 0
  end

  test "a valid key moves to a team picker listing the user's Linear teams", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    submit_key(view, @api_key)

    assert has_element?(view, "#sink-team-form")
    assert has_element?(view, "#sink-team-form option", "Engineering")
    assert has_element?(view, "#sink-team-form option", "Design")
  end

  test "the team picker says the pick decides where Pushes land", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    submit_key(view, @api_key)

    assert has_element?(view, "h1", "Choose a team")
    assert has_element?(view, "main header p", "Pushed Action Points land in the team you pick")
  end

  test "choosing a team saves the connection and shows it masked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    html = connect(view)

    assert has_element?(view, "#sink-connection")
    assert has_element?(view, "#sink-team-name", "Design")
    # Masked: the last four characters appear, the full key never does
    assert has_element?(view, "#sink-masked-key", "abcd")
    refute html =~ @api_key
  end

  test "the connected screen says the Task Sink is live and names it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    connect(view)

    assert has_element?(view, "h1", "Linear is connected")
    assert has_element?(view, "#sink-connection", "Connected")
    assert has_element?(view, "#sink-connection", "Linear")
    # Disconnecting is reversible for the Task Sink but not for what it already
    # created, and the screen says so before the button is reached for.
    assert has_element?(view, "#sink-connection", "Issues already created in Linear stay")
  end

  test "replacing a key says the current connection keeps working meanwhile", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")
    connect(view)

    view |> element("#replace-key") |> render_click()

    assert has_element?(view, "h1", "Replace your key")
    assert has_element?(view, "main header p", "keeps working until it does")
  end

  test "the key is encrypted at rest", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    connect(view)

    %{rows: [[stored, last4]]} =
      Repo.query!("SELECT api_key, api_key_last4 FROM sink_connections WHERE user_id = $1", [
        user.id
      ])

    refute stored == @api_key
    refute String.contains?(stored, @api_key)
    assert Vault.decrypt(stored) == {:ok, @api_key}
    assert last4 == "abcd"
  end

  test "replace validates the new key and swaps the connection in place", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")
    connect(view)

    view |> element("#replace-key") |> render_click()
    assert has_element?(view, "#sink-key-form")

    submit_key(view, "lin_api_replacement_wxyz")

    view
    |> form("#sink-team-form", connection: %{team_id: "team-1"})
    |> render_submit()

    assert has_element?(view, "#sink-masked-key", "wxyz")
    assert has_element?(view, "#sink-team-name", "Engineering")
    assert Repo.aggregate("sink_connections", :count) == 1

    %{rows: [[stored]]} =
      Repo.query!("SELECT api_key FROM sink_connections WHERE user_id = $1", [user.id])

    assert Vault.decrypt(stored) == {:ok, "lin_api_replacement_wxyz"}
  end

  test "replace can be cancelled without touching the connection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")
    connect(view)

    view |> element("#replace-key") |> render_click()
    view |> element("#cancel-replace") |> render_click()

    assert has_element?(view, "#sink-connection")
    assert has_element?(view, "#sink-masked-key", "abcd")
  end

  test "disconnect removes the connection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")
    connect(view)

    html = view |> element("#disconnect-sink") |> render_click()

    assert has_element?(view, "#sink-key-form")
    refute has_element?(view, "#sink-connection")
    assert Repo.aggregate("sink_connections", :count) == 0
    # Disconnecting is a Push-affecting act, and the confirmation says which.
    assert html =~ "You can&#39;t Push until you reconnect"
  end

  test "a returning connected user sees their connection, not the key form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")
    connect(view)

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    assert has_element?(view, "#sink-connection")
    assert has_element?(view, "#sink-masked-key", "abcd")
  end
end
