defmodule ActionPoints.Sinks.LinearTest do
  use ExUnit.Case, async: false

  alias ActionPoints.Sinks.Linear

  @credentials %{api_key: "lin_api_test123"}

  setup do
    Application.put_env(:action_points, Linear, req_options: [plug: {Req.Test, __MODULE__}])
    on_exit(fn -> Application.delete_env(:action_points, Linear) end)
  end

  defp stub_response(fun), do: Req.Test.stub(__MODULE__, fun)

  defp decode_request(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {conn, Jason.decode!(body)}
  end

  test "validate_credentials passes the key in the authorization header" do
    stub_response(fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["lin_api_test123"]
      Req.Test.json(conn, %{"data" => %{"viewer" => %{"id" => "viewer-1"}}})
    end)

    assert Linear.validate_credentials(@credentials) == :ok
  end

  test "an authentication error is an invalid key, even over HTTP 400" do
    stub_response(fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "errors" => [
          %{
            "message" => "Authentication required, not authenticated",
            "extensions" => %{"type" => "authentication error"}
          }
        ]
      })
    end)

    assert Linear.validate_credentials(@credentials) == {:error, :invalid_key}

    stub_response(fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
    end)

    assert Linear.validate_credentials(@credentials) == {:error, :invalid_key}
  end

  test "rate limiting and server errors are typed failures" do
    stub_response(fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{})
    end)

    assert Linear.validate_credentials(@credentials) == {:error, :rate_limited}

    stub_response(fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
    end)

    assert Linear.validate_credentials(@credentials) == {:error, :unavailable}
  end

  test "a 200 carrying GraphQL errors is not a success" do
    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "data" => nil,
        "errors" => [%{"message" => "Something went wrong"}]
      })
    end)

    assert Linear.validate_credentials(@credentials) == {:error, :api_error}
  end

  test "list_teams returns id/name maps" do
    stub_response(fn conn ->
      {conn, payload} = decode_request(conn)
      assert payload["query"] =~ "teams"

      Req.Test.json(conn, %{
        "data" => %{
          "teams" => %{
            "nodes" => [
              %{"id" => "team-1", "name" => "Engineering"},
              %{"id" => "team-2", "name" => "Design"}
            ]
          }
        }
      })
    end)

    assert Linear.list_teams(@credentials) ==
             {:ok, [%{id: "team-1", name: "Engineering"}, %{id: "team-2", name: "Design"}]}
  end

  test "list_users returns the real name and handle separately" do
    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "users" => %{
            "nodes" => [
              %{
                "id" => "user-1",
                "name" => "Priya Patel",
                "displayName" => "priya",
                "active" => true
              }
            ]
          }
        }
      })
    end)

    assert Linear.list_users(@credentials) ==
             {:ok, [%{id: "user-1", name: "Priya Patel", handle: "priya"}]}
  end

  test "list_users excludes deactivated members" do
    stub_response(fn conn ->
      {conn, payload} = decode_request(conn)
      assert payload["query"] =~ "active"

      Req.Test.json(conn, %{
        "data" => %{
          "users" => %{
            "nodes" => [
              %{
                "id" => "user-1",
                "name" => "Priya Patel",
                "displayName" => "priya",
                "active" => true
              },
              %{
                "id" => "user-2",
                "name" => "Sam Jones",
                "displayName" => "sam",
                "active" => false
              }
            ]
          }
        }
      })
    end)

    assert Linear.list_users(@credentials) ==
             {:ok, [%{id: "user-1", name: "Priya Patel", handle: "priya"}]}
  end

  test "push_task creates an issue in the team and returns its reference" do
    stub_response(fn conn ->
      {conn, payload} = decode_request(conn)

      assert payload["query"] =~ "issueCreate"

      assert payload["variables"]["input"] == %{
               "teamId" => "team-1",
               "title" => "Send the Q3 report",
               "description" => "Priya will send the Q3 report.",
               "assigneeId" => "user-1",
               "dueDate" => "2026-07-31"
             }

      Req.Test.json(conn, %{
        "data" => %{
          "issueCreate" => %{
            "success" => true,
            "issue" => %{
              "id" => "issue-1",
              "identifier" => "ENG-42",
              "url" => "https://linear.app/acme/issue/ENG-42"
            }
          }
        }
      })
    end)

    task = %{
      title: "Send the Q3 report",
      description: "Priya will send the Q3 report.",
      assignee_id: "user-1",
      due_date: ~D[2026-07-31],
      parent_id: nil
    }

    assert Linear.push_task(@credentials, "team-1", task) ==
             {:ok,
              %{id: "issue-1", identifier: "ENG-42", url: "https://linear.app/acme/issue/ENG-42"}}
  end

  test "push_task sends a Subtask's parent as Linear's native parentId" do
    stub_response(fn conn ->
      {conn, payload} = decode_request(conn)

      assert payload["variables"]["input"] == %{
               "teamId" => "team-1",
               "title" => "Rewrite the onboarding copy",
               "description" => "Alice takes the copy.",
               "parentId" => "issue-parent-9"
             }

      Req.Test.json(conn, %{
        "data" => %{
          "issueCreate" => %{
            "success" => true,
            "issue" => %{"id" => "i2", "identifier" => "ENG-2", "url" => "https://l/2"}
          }
        }
      })
    end)

    task = %{
      title: "Rewrite the onboarding copy",
      description: "Alice takes the copy.",
      assignee_id: nil,
      due_date: nil,
      parent_id: "issue-parent-9"
    }

    assert {:ok, %{identifier: "ENG-2"}} = Linear.push_task(@credentials, "team-1", task)
  end

  test "push_task omits nil assignee and due date rather than sending nulls" do
    stub_response(fn conn ->
      {conn, payload} = decode_request(conn)

      assert payload["variables"]["input"] == %{
               "teamId" => "team-1",
               "title" => "Circle back on hiring",
               "description" => "Vague commitment to revisit hiring."
             }

      Req.Test.json(conn, %{
        "data" => %{
          "issueCreate" => %{
            "success" => true,
            "issue" => %{"id" => "i", "identifier" => "ENG-1", "url" => "https://l/1"}
          }
        }
      })
    end)

    task = %{
      title: "Circle back on hiring",
      description: "Vague commitment to revisit hiring.",
      assignee_id: nil,
      due_date: nil,
      parent_id: nil
    }

    assert {:ok, %{identifier: "ENG-1"}} = Linear.push_task(@credentials, "team-1", task)
  end
end
