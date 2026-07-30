defmodule ActionPoints.Meetings.Extractor.ClaudeTest do
  use ExUnit.Case, async: false

  alias ActionPoints.Meetings.Extractor.Claude

  @transcript "Priya: I'll send the Q3 report by July 31st 2026."

  setup do
    Application.put_env(:action_points, Claude,
      api_key: "test-key",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:action_points, Claude) end)
  end

  defp stub_response(fun), do: Req.Test.stub(__MODULE__, fun)

  test "parses a structured-outputs response into Action Point attrs" do
    stub_response(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      # The request carries the model, the schema constraint, and the transcript
      assert payload["model"] == "claude-sonnet-5"
      assert payload["output_config"]["format"]["type"] == "json_schema"
      assert [%{"role" => "user", "content" => @transcript}] = payload["messages"]
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key"]

      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{"type" => "thinking", "thinking" => ""},
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{
                "meeting_date" => "2026-07-24",
                "action_points" => [
                  %{
                    "title" => "Send the Q3 report",
                    "description" => "Priya will send the Q3 report.",
                    "assignee_guess" => "Priya",
                    "due_date" => "2026-07-31",
                    "quotes" => ["I'll send the Q3 report by July 31st 2026."],
                    "blocked_by" => []
                  },
                  %{
                    "title" => "Circle back on hiring",
                    "description" => "Vague commitment to revisit hiring.",
                    "assignee_guess" => nil,
                    "due_date" => nil,
                    "blocked_by" => [1]
                  }
                ]
              })
          }
        ]
      })
    end)

    assert {:ok, %{meeting_date: ~D[2026-07-24], action_points: [first, second]}} =
             Claude.extract(@transcript)

    assert first == %{
             title: "Send the Q3 report",
             description: "Priya will send the Q3 report.",
             assignee_guess: "Priya",
             due_date: ~D[2026-07-31],
             quotes: ["I'll send the Q3 report by July 31st 2026."],
             blocked_by: []
           }

    assert second.assignee_guess == nil
    assert second.due_date == nil
    assert second.blocked_by == [1]

    # The schema demands quotes, but a missing key parses as none — quote
    # trouble must never cost the user their Action Points.
    assert second.quotes == []
  end

  test "a missing blocked_by key parses as no proposed Blockers" do
    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{
                "meeting_date" => nil,
                "action_points" => [
                  %{
                    "title" => "Send the Q3 report",
                    "description" => "Priya will send the Q3 report.",
                    "assignee_guess" => nil,
                    "due_date" => nil,
                    "quotes" => []
                  }
                ]
              })
          }
        ]
      })
    end)

    assert {:ok, %{action_points: [%{blocked_by: []}]}} = Claude.extract(@transcript)
  end

  test "a response stating no meeting date parses as none" do
    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{
                "meeting_date" => nil,
                "action_points" => [
                  %{
                    "title" => "Send the Q3 report",
                    "description" => "Priya will send the Q3 report.",
                    "assignee_guess" => "Priya",
                    "due_date" => nil,
                    "quotes" => []
                  }
                ]
              })
          }
        ]
      })
    end)

    assert {:ok, %{meeting_date: nil, action_points: [_one]}} = Claude.extract(@transcript)
  end

  test "a meeting date the schema should have prevented is none, not a failed Extraction" do
    for payload <- [
          %{"meeting_date" => "last Tuesday", "action_points" => []},
          %{"action_points" => []}
        ] do
      stub_response(fn conn ->
        Req.Test.json(conn, %{
          "stop_reason" => "end_turn",
          "content" => [%{"type" => "text", "text" => Jason.encode!(payload)}]
        })
      end)

      assert {:ok, %{meeting_date: nil, action_points: []}} = Claude.extract(@transcript)
    end
  end

  test "a refusal is a typed failure" do
    stub_response(fn conn ->
      Req.Test.json(conn, %{"stop_reason" => "refusal", "content" => []})
    end)

    assert Claude.extract(@transcript) == {:error, :refused}
  end

  test "rate limiting and server errors are typed failures" do
    stub_response(fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{})
    end)

    assert Claude.extract(@transcript) == {:error, :rate_limited}

    stub_response(fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
    end)

    assert Claude.extract(@transcript) == {:error, :api_unavailable}
  end

  test "a non-JSON text payload is a typed failure" do
    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => "not json"}]
      })
    end)

    assert Claude.extract(@transcript) == {:error, :invalid_response}
  end

  test "refuses to run without an API key" do
    Application.put_env(:action_points, Claude, api_key: nil)

    assert Claude.extract(@transcript) == {:error, :missing_api_key}
  end
end
