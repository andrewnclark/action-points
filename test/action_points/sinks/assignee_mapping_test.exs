defmodule ActionPoints.Sinks.AssigneeMappingTest do
  use ActionPoints.DataCase, async: true

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.AccountsFixtures
  alias ActionPoints.Repo
  alias ActionPoints.Sinks
  alias ActionPoints.Sinks.AssigneeMapping

  defp connect(user) do
    scope = Scope.for_user(user)

    {:ok, _connection} =
      Sinks.connect(scope, %{
        "api_key" => "lin_api_#{user.id}",
        "team_id" => "team-1",
        "team_name" => "Engineering"
      })

    scope
  end

  setup do
    %{scope: connect(AccountsFixtures.user_fixture())}
  end

  describe "normalisation" do
    test "the guessed name is normalised on write and on lookup", %{scope: scope} do
      {:ok, _mapping} =
        Sinks.put_assignee_mapping(scope, "  Bob  ", %{id: "u-1", name: "Bob Smith"})

      assert [%AssigneeMapping{normalized_guess: "bob"}] = Sinks.list_assignee_mappings(scope)
    end

    test "different casing and whitespace resolve to the same mapping", %{scope: scope} do
      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})
      {:ok, _} = Sinks.put_assignee_mapping(scope, " BOB ", %{id: "u-2", name: "Robert Smith"})

      assert [%AssigneeMapping{sink_user_id: "u-2"}] = Sinks.list_assignee_mappings(scope)
    end
  end

  describe "one name maps to at most one member, per connection" do
    test "writing a mapping for an already-mapped name replaces it, not duplicates it", %{
      scope: scope
    } do
      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})
      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-2", name: "Robert Smith"})

      assert [%AssigneeMapping{sink_user_id: "u-2", display_name: "Robert Smith"}] =
               Sinks.list_assignee_mappings(scope)
    end

    test "many different names can map to the same member", %{scope: scope} do
      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})
      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bobby", %{id: "u-1", name: "Bob Smith"})

      assert Sinks.list_assignee_mappings(scope) |> Enum.map(& &1.sink_user_id) == ["u-1", "u-1"]
    end
  end

  describe "scoping" do
    test "a mapping is only visible to the connection that owns it", %{scope: scope} do
      other_scope = connect(AccountsFixtures.user_fixture())

      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})

      assert Sinks.list_assignee_mappings(other_scope) == []
    end

    test "the same guessed name can map to different members on different connections", %{
      scope: scope
    } do
      other_scope = connect(AccountsFixtures.user_fixture())

      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})
      {:ok, _} = Sinks.put_assignee_mapping(other_scope, "Bob", %{id: "u-9", name: "Bob Jones"})

      assert [%AssigneeMapping{sink_user_id: "u-1"}] = Sinks.list_assignee_mappings(scope)
      assert [%AssigneeMapping{sink_user_id: "u-9"}] = Sinks.list_assignee_mappings(other_scope)
    end

    test "fetching another connection's mapping by id raises", %{scope: scope} do
      other_scope = connect(AccountsFixtures.user_fixture())
      {:ok, mapping} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})

      assert_raise Ecto.NoResultsError, fn ->
        Sinks.get_assignee_mapping!(other_scope, mapping.id)
      end
    end
  end

  describe "editing and deleting" do
    test "update_assignee_mapping repoints the mapping without changing the guessed name", %{
      scope: scope
    } do
      {:ok, mapping} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})

      {:ok, updated} =
        Sinks.update_assignee_mapping(mapping, %{id: "u-2", name: "Robert Smithson"})

      assert updated.normalized_guess == "bob"
      assert updated.sink_user_id == "u-2"
      assert updated.display_name == "Robert Smithson"
    end

    test "delete_assignee_mapping removes it", %{scope: scope} do
      {:ok, mapping} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})

      {:ok, _} = Sinks.delete_assignee_mapping(mapping)

      assert Sinks.list_assignee_mappings(scope) == []
    end
  end

  describe "cascade delete" do
    test "disconnecting the Sink Connection deletes its Assignee Mappings", %{scope: scope} do
      {:ok, _} = Sinks.put_assignee_mapping(scope, "Bob", %{id: "u-1", name: "Bob Smith"})

      :ok = Sinks.disconnect(scope)

      assert Repo.aggregate(AssigneeMapping, :count) == 0
    end
  end
end
