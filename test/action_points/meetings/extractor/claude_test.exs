defmodule ActionPoints.Meetings.Extractor.ClaudeTest do
  use ExUnit.Case, async: false

  alias ActionPoints.Meetings.Extractor.Claude
  alias ActionPoints.Meetings.Timing

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
                    "timing" => %{
                      "kind" => "absolute",
                      "year" => 2026,
                      "month" => 7,
                      "day" => 31
                    },
                    "timing_quote" => "by July 31st 2026",
                    "quotes" => ["I'll send the Q3 report by July 31st 2026."],
                    "blocked_by" => []
                  },
                  %{
                    "title" => "Circle back on hiring",
                    "description" => "Vague commitment to revisit hiring.",
                    "assignee_guess" => nil,
                    "timing" => nil,
                    "parent" => 1,
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
             timing: %{kind: :absolute, year: 2026, month: 7, day: 31},
             timing_quote: "by July 31st 2026",
             quotes: ["I'll send the Q3 report by July 31st 2026."],
             # A missing parent key parses as no parent, like quotes below.
             parent: nil,
             blocked_by: []
           }

    assert second.assignee_guess == nil
    assert second.timing == nil

    # A proposed Subtask carries its parent's 1-based position through.
    assert second.parent == 1
    assert second.blocked_by == [1]

    # The schema demands quotes, but a missing key parses as none — quote
    # trouble must never cost the user their Action Points.
    assert second.quotes == []

    # Same for the Timing Quote: a missing (or non-text) key is no quote.
    assert second.timing_quote == nil
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
                    "timing" => nil,
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

  test "parses each timing kind into the tagged union" do
    timings = [
      {%{"kind" => "weekday", "weekday" => "wednesday", "modifier" => nil},
       %{kind: :weekday, weekday: :wednesday, modifier: nil}},
      {%{"kind" => "weekday", "weekday" => "monday", "modifier" => "next"},
       %{kind: :weekday, weekday: :monday, modifier: :next}},
      {%{"kind" => "weekday", "weekday" => "friday", "modifier" => "this"},
       %{kind: :weekday, weekday: :friday, modifier: :this}},
      {%{"kind" => "relative_day", "offset" => 1}, %{kind: :relative_day, offset: 1}},
      # A date said in part keeps the parts that were said and nothing more —
      # completing it is the application's, against the Meeting Date.
      {%{"kind" => "absolute", "year" => nil, "month" => 3, "day" => 3},
       %{kind: :absolute, year: nil, month: 3, day: 3}},
      {%{"kind" => "absolute", "year" => nil, "month" => nil, "day" => 12},
       %{kind: :absolute, year: nil, month: nil, day: 12}},
      {%{"kind" => "span_end", "modifier" => "next", "unit" => "month"},
       %{kind: :span_end, modifier: :next, unit: :month}},
      {%{"kind" => "duration", "unit" => "week", "count" => 2},
       %{kind: :duration, unit: :week, count: 2}},
      # A spoken quantifier arrives as the word, not as a number the model
      # chose: decoding it is the application's, through a closed lexicon.
      {%{"kind" => "duration", "unit" => "week", "count" => "couple"},
       %{kind: :duration, unit: :week, count: :couple}},
      {%{"kind" => "vague"}, %{kind: :vague}}
    ]

    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{
                "meeting_date" => nil,
                "action_points" =>
                  Enum.map(timings, fn {json, _expected} ->
                    %{
                      "title" => "A task",
                      "description" => "",
                      "assignee_guess" => nil,
                      "timing" => json,
                      "quotes" => []
                    }
                  end)
              })
          }
        ]
      })
    end)

    assert {:ok, %{action_points: action_points}} = Claude.extract(@transcript)

    for {{_json, expected}, attrs} <- Enum.zip(timings, action_points) do
      assert attrs.timing == expected
    end
  end

  test "every quantifier the adapter accepts is one the resolver decodes" do
    # The adapter's lexicon is derived from the resolver's rather than
    # restated, and this is what makes that visible: a word accepted here but
    # unknown there would parse cleanly and then pin no date at all.
    timings =
      Enum.map(Timing.quantifiers(), fn quantifier ->
        %{"kind" => "duration", "unit" => "week", "count" => Atom.to_string(quantifier)}
      end)

    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{
                "meeting_date" => nil,
                "action_points" =>
                  Enum.map(timings, fn timing ->
                    %{
                      "title" => "A task",
                      "description" => "",
                      "assignee_guess" => nil,
                      "timing" => timing,
                      "quotes" => []
                    }
                  end)
              })
          }
        ]
      })
    end)

    assert {:ok, %{action_points: action_points}} = Claude.extract(@transcript)
    assert length(action_points) == length(Timing.quantifiers())

    for %{timing: timing} <- action_points do
      assert Timing.resolve(timing, ~D[2026-07-28])
    end
  end

  test "timing the schema should have prevented is no classification, not a failed Extraction" do
    malformed = [
      %{"kind" => "weekday", "weekday" => "someday", "modifier" => nil},
      %{"kind" => "weekday", "weekday" => "monday", "modifier" => "last"},
      %{"kind" => "relative_day", "offset" => "tomorrow"},
      # A year is only ever spoken after its month, so a year beside an unsaid
      # month is a date no meeting produced.
      %{"kind" => "absolute", "year" => 2027, "month" => nil, "day" => 3},
      %{"kind" => "absolute", "year" => nil, "month" => 3, "day" => "3rd"},
      %{"kind" => "duration", "unit" => "fortnight", "count" => 1},
      # A quantifier outside the closed lexicon is not decoded into an atom the
      # resolver would then have to reject — it never becomes one.
      %{"kind" => "duration", "unit" => "week", "count" => "a few"},
      %{"kind" => "duration", "unit" => "day", "count" => 0},
      %{"kind" => "eventually"},
      "by Wednesday"
    ]

    stub_response(fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{
                "meeting_date" => nil,
                "action_points" =>
                  Enum.map(malformed, fn timing ->
                    %{
                      "title" => "A task",
                      "description" => "",
                      "assignee_guess" => nil,
                      "timing" => timing,
                      "quotes" => []
                    }
                  end)
              })
          }
        ]
      })
    end)

    assert {:ok, %{action_points: action_points}} = Claude.extract(@transcript)
    assert length(action_points) == length(malformed)
    assert Enum.all?(action_points, &is_nil(&1.timing))
  end

  test "the prompt carries no date, time, or timezone — classification is anchor-independent" do
    stub_response(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      send(self(), {:request, payload})

      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [
          %{
            "type" => "text",
            "text" => Jason.encode!(%{"meeting_date" => nil, "action_points" => []})
          }
        ]
      })
    end)

    assert {:ok, _result} = Claude.extract(@transcript)
    assert_received {:request, payload}
    system = payload["system"]

    # No calendar date of any shape — in particular not today's — no clock
    # time, and no timezone. The prompt is static: the same Transcript always
    # produces the same request, whenever it is sent.
    refute system =~ ~r/\d{4}-\d{2}-\d{2}/
    refute system =~ ~r/\b(19|20)\d{2}\b/
    refute system =~ ~r/\d{1,2}:\d{2}/
    refute system =~ ~r/\b(current date|UTC|GMT|timezone|time zone)\b/i
    refute system =~ Date.to_iso8601(Date.utc_today())
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
