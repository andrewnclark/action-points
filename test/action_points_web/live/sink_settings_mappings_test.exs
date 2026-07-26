defmodule ActionPointsWeb.SinkSettingsMappingsTest do
  use ActionPointsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ActionPoints.Sinks

  @api_key "lin_api_secret_key_abcd"

  setup :register_and_log_in_user

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_task_sink_pushes)
    end)
  end

  defp connect(scope) do
    {:ok, _connection} =
      Sinks.connect(scope, %{
        "api_key" => @api_key,
        "team_id" => "team-1",
        "team_name" => "Engineering"
      })

    :ok
  end

  defp script_users(users), do: Application.put_env(:action_points, :fake_task_sink, users: users)

  test "the mappings section only shows once connected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    refute has_element?(view, "#assignee-mappings")
  end

  test "an empty mapping list says so", %{conn: conn, scope: scope} do
    connect(scope)
    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    assert has_element?(view, "#no-mappings", "No Assignee Mappings yet")
  end

  test "existing mappings are listed with the resolved member's name and handle", %{
    conn: conn,
    scope: scope
  } do
    connect(scope)

    {:ok, _} =
      Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith", handle: "bsmith"})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    assert has_element?(view, "#mapping-list", "bob")
    assert has_element?(view, "#mapping-list", "Bob Smith")
    assert has_element?(view, "#mapping-list", "@bsmith")
  end

  test "adding a mapping ahead of time creates it", %{conn: conn, scope: scope} do
    connect(scope)
    script_users({:ok, [%{id: "u-1", name: "Bob Smith", handle: "bsmith"}]})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    view |> element("#add-mapping-toggle") |> render_click()
    assert has_element?(view, "#add-mapping-form")

    view
    |> form("#add-mapping-form", mapping: %{guess: "Bob", sink_user_id: "u-1"})
    |> render_submit()

    refute has_element?(view, "#add-mapping-form")
    assert has_element?(view, "#mapping-list", "bob")
    assert has_element?(view, "#mapping-list", "Bob Smith")
  end

  test "adding a mapping with no guessed name is refused", %{conn: conn, scope: scope} do
    connect(scope)
    script_users({:ok, [%{id: "u-1", name: "Bob Smith", handle: "bsmith"}]})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")
    view |> element("#add-mapping-toggle") |> render_click()

    view
    |> form("#add-mapping-form", mapping: %{guess: "", sink_user_id: "u-1"})
    |> render_submit()

    assert has_element?(view, "#mapping-error", "Enter a guessed name")
    assert Sinks.list_assignee_mappings(scope) == []
  end

  test "adding a mapping with no member picked is refused", %{conn: conn, scope: scope} do
    connect(scope)
    script_users({:ok, [%{id: "u-1", name: "Bob Smith", handle: "bsmith"}]})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")
    view |> element("#add-mapping-toggle") |> render_click()

    view
    |> form("#add-mapping-form", mapping: %{guess: "Bob", sink_user_id: ""})
    |> render_submit()

    assert has_element?(view, "#mapping-error", "Pick a member")
    assert Sinks.list_assignee_mappings(scope) == []
  end

  test "editing a mapping repoints it at a different member", %{conn: conn, scope: scope} do
    connect(scope)
    {:ok, mapping} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})

    script_users(
      {:ok,
       [
         %{id: "u-1", name: "Bob Smith", handle: "bsmith"},
         %{id: "u-2", name: "Robert Jones", handle: "rjones"}
       ]}
    )

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    view |> element("#assignee_mappings-#{mapping.id}-edit") |> render_click()
    assert has_element?(view, "#edit-mapping-#{mapping.id}")

    view
    |> form("#edit-mapping-#{mapping.id}", mapping: %{sink_user_id: "u-2"})
    |> render_submit()

    refute has_element?(view, "#edit-mapping-#{mapping.id}")
    assert has_element?(view, "#mapping-list", "Robert Jones")

    assert %{sink_user_id: "u-2"} = Sinks.get_assignee_mapping!(scope, mapping.id)
  end

  test "cancelling an edit leaves the mapping unchanged", %{conn: conn, scope: scope} do
    connect(scope)
    {:ok, mapping} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})
    script_users({:ok, [%{id: "u-1", name: "Bob Smith", handle: "bsmith"}]})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    view |> element("#assignee_mappings-#{mapping.id}-edit") |> render_click()
    view |> element("#assignee_mappings-#{mapping.id} button", "Cancel") |> render_click()

    refute has_element?(view, "#edit-mapping-#{mapping.id}")
    assert %{sink_user_id: "u-1"} = Sinks.get_assignee_mapping!(scope, mapping.id)
  end

  test "deleting a mapping removes it", %{conn: conn, scope: scope} do
    connect(scope)
    {:ok, mapping} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    view |> element("#assignee_mappings-#{mapping.id}-delete") |> render_click()

    assert has_element?(view, "#no-mappings")
    assert Sinks.list_assignee_mappings(scope) == []
  end

  test "an unreachable member list disables adding and editing, with a notice", %{
    conn: conn,
    scope: scope
  } do
    connect(scope)
    {:ok, mapping} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})
    script_users({:error, :unavailable})

    {:ok, view, _html} = live(conn, ~p"/settings/sink")

    refute has_element?(view, "#add-mapping-toggle")
    assert has_element?(view, "#assignee-mappings", "couldn't be reached")
    assert has_element?(view, "#assignee_mappings-#{mapping.id}-edit[disabled]")
  end
end
