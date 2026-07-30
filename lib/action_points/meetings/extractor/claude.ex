defmodule ActionPoints.Meetings.Extractor.Claude do
  @moduledoc """
  Real Extractor adapter: Claude API (Sonnet 5) with structured outputs, so
  the response is schema-validated JSON rather than parsed from prose.
  """

  @behaviour ActionPoints.Meetings.Extractor

  @url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-5"

  @system_prompt """
  You extract Action Points from a meeting transcript.

  An Action Point is a task somebody committed to or proposed in the meeting.
  For each one produce:
  - title: a short imperative task title
  - description: the context that makes the task actionable days later, for
    a reader who was not in the meeting: why the task exists, the decisions
    the meeting took about it, and the constraints or concerns raised. Never
    a restatement of the title — if the conversation gave nothing beyond the
    task itself, keep the description short rather than padding it
  - assignee_guess: the person responsible, grounded in the speaker labels
    when the transcript has them; null when nobody was clearly responsible
  - timing: how the meeting talked about this task's deadline, classified.
    Never compute, resolve, or infer a calendar date — report the kind of
    timing language you heard and its parts exactly as spoken; the
    application does the calendar arithmetic. The kinds:
    - "absolute": an actual calendar date was said aloud — report its day,
      month, and year as numbers, with a null year when none was said
    - "weekday": a day of the week was named ("by Wednesday") — report the
      weekday, and the modifier "this" or "next" when one was said, null
      when the weekday stood bare
    - "relative_day": "today" or "tomorrow" — report the offset in days,
      zero for today, one for tomorrow
    - "span_end": the end of a period ("by the end of the week") — report
      whether it was this or next, and whether a week, month, or quarter
    - "duration": a length of time out ("in two weeks") — report the unit
      and the count
    - "vague": a deadline was voiced but pins down no date ("soon", "before
      the launch", "when things calm down")
    - null: no deadline was mentioned at all. Never invent timing that was
      not said aloud
  - quotes: up to three short verbatim excerpts from the transcript — the
    decision-bearing words actually spoken about this task. Copy them
    character for character from the transcript; every quote is checked
    against it and a paraphrase, trimmed filler, or corrected typo is
    silently discarded. Prefer one or two quotes that carry a decision,
    constraint, or commitment over three weak ones; an empty list is fine.

  Alongside the Action Points, report meeting_date: the date this meeting
  itself took place, as an ISO 8601 date, but only when the transcript states
  it outright — a header line naming the meeting's own date, or a speaker
  saying what today's date is. A date merely mentioned in the conversation is
  not the meeting's own date: a deadline, another event's date, or a date
  something shipped on are all null here. When nothing states when this
  meeting happened, report null rather than guessing.

  Include vague or tentative commitments ("we should probably look into
  that") as their own Action Points — the user rejects noise during Review,
  so it is better to surface a doubtful item than to silently drop it.
  Do not invent tasks that were not discussed.
  """

  @weekday_names %{
    "monday" => :monday,
    "tuesday" => :tuesday,
    "wednesday" => :wednesday,
    "thursday" => :thursday,
    "friday" => :friday,
    "saturday" => :saturday,
    "sunday" => :sunday
  }

  @span_units %{"week" => :week, "month" => :month, "quarter" => :quarter}
  @duration_units %{"day" => :day, "week" => :week, "month" => :month}

  # The timing classification: a tagged union, `kind` the tag. `vague` has
  # nowhere to put a date by construction — the boundary between pinnable and
  # unpinnable language is the schema's, not the prompt's to ask for.
  @timing_schema %{
    "anyOf" => [
      %{"type" => "null"},
      %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"enum" => ["absolute"]},
          "year" => %{"anyOf" => [%{"type" => "integer"}, %{"type" => "null"}]},
          "month" => %{"type" => "integer"},
          "day" => %{"type" => "integer"}
        },
        "required" => ["kind", "year", "month", "day"],
        "additionalProperties" => false
      },
      %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"enum" => ["weekday"]},
          "weekday" => %{"enum" => Map.keys(@weekday_names)},
          "modifier" => %{"anyOf" => [%{"enum" => ["this", "next"]}, %{"type" => "null"}]}
        },
        "required" => ["kind", "weekday", "modifier"],
        "additionalProperties" => false
      },
      %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"enum" => ["relative_day"]},
          "offset" => %{"type" => "integer"}
        },
        "required" => ["kind", "offset"],
        "additionalProperties" => false
      },
      %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"enum" => ["span_end"]},
          "modifier" => %{"enum" => ["this", "next"]},
          "unit" => %{"enum" => Map.keys(@span_units)}
        },
        "required" => ["kind", "modifier", "unit"],
        "additionalProperties" => false
      },
      %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"enum" => ["duration"]},
          "unit" => %{"enum" => Map.keys(@duration_units)},
          "count" => %{"type" => "integer"}
        },
        "required" => ["kind", "unit", "count"],
        "additionalProperties" => false
      },
      %{
        "type" => "object",
        "properties" => %{"kind" => %{"enum" => ["vague"]}},
        "required" => ["kind"],
        "additionalProperties" => false
      }
    ]
  }

  @output_schema %{
    "type" => "object",
    "properties" => %{
      "meeting_date" => %{
        "anyOf" => [%{"type" => "string", "format" => "date"}, %{"type" => "null"}]
      },
      "action_points" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "title" => %{"type" => "string"},
            "description" => %{"type" => "string"},
            "assignee_guess" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]},
            "timing" => @timing_schema,
            # No `maxItems`: structured outputs reject it outright ("For
            # 'array' type, property 'maxItems' is not supported"), failing the
            # whole request. The cap is the prompt's to ask for and
            # `GroundingQuote.verify/2`'s to enforce.
            "quotes" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          "required" => ["title", "description", "assignee_guess", "timing", "quotes"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["meeting_date", "action_points"],
    "additionalProperties" => false
  }

  @impl true
  def extract(transcript_text) when is_binary(transcript_text) do
    case config()[:api_key] do
      nil -> {:error, :missing_api_key}
      api_key -> request(transcript_text, api_key)
    end
  end

  defp request(transcript_text, api_key) do
    body = %{
      model: @model,
      max_tokens: 16_000,
      system: @system_prompt,
      output_config: %{format: %{type: "json_schema", schema: @output_schema}},
      messages: [%{role: "user", content: transcript_text}]
    }

    request_options =
      [
        json: body,
        headers: [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
        receive_timeout: 120_000
      ] ++ Keyword.get(config(), :req_options, [])

    case Req.post(@url, request_options) do
      {:ok, %Req.Response{status: 200, body: response}} -> parse_response(response)
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{status: status}} when status >= 500 -> {:error, :api_unavailable}
      {:ok, %Req.Response{}} -> {:error, :api_error}
      {:error, _exception} -> {:error, :api_unavailable}
    end
  end

  defp parse_response(%{"stop_reason" => "refusal"}), do: {:error, :refused}
  defp parse_response(%{"stop_reason" => "max_tokens"}), do: {:error, :truncated}

  defp parse_response(%{"content" => content}) do
    # Adaptive thinking may put a thinking block before the text block.
    with %{"text" => text} <- Enum.find(content, %{}, &(&1["type"] == "text")),
         {:ok, %{"action_points" => action_points} = decoded} <- Jason.decode(text) do
      {:ok,
       %{
         action_points: Enum.map(action_points, &to_attrs/1),
         meeting_date: parse_date(decoded["meeting_date"])
       }}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp parse_response(_), do: {:error, :invalid_response}

  defp to_attrs(action_point) do
    %{
      title: action_point["title"],
      description: action_point["description"],
      assignee_guess: action_point["assignee_guess"],
      timing: parse_timing(action_point["timing"]),
      quotes: action_point["quotes"] || []
    }
  end

  # Reads the model's timing classification into the tagged union
  # `ActionPoints.Meetings.Timing` resolves. Anything the schema should have
  # prevented — an unknown kind, a misspelt weekday, a missing field — reads
  # as no classification rather than as a failed Extraction: malformed timing
  # must never cost the user their Action Points.
  defp parse_timing(%{"kind" => "absolute", "year" => year, "month" => month, "day" => day})
       when (is_integer(year) or is_nil(year)) and is_integer(month) and is_integer(day) do
    %{kind: :absolute, year: year, month: month, day: day}
  end

  defp parse_timing(%{"kind" => "weekday", "weekday" => weekday} = timing) do
    with %{^weekday => day} <- @weekday_names,
         {:ok, modifier} <- parse_modifier(timing["modifier"]) do
      %{kind: :weekday, weekday: day, modifier: modifier}
    else
      _ -> nil
    end
  end

  defp parse_timing(%{"kind" => "relative_day", "offset" => offset})
       when is_integer(offset) and offset >= 0 do
    %{kind: :relative_day, offset: offset}
  end

  defp parse_timing(%{"kind" => "span_end", "modifier" => modifier, "unit" => unit}) do
    with {:ok, m} when m in [:this, :next] <- parse_modifier(modifier),
         %{^unit => u} <- @span_units do
      %{kind: :span_end, modifier: m, unit: u}
    else
      _ -> nil
    end
  end

  defp parse_timing(%{"kind" => "duration", "unit" => unit, "count" => count})
       when is_integer(count) and count > 0 do
    case @duration_units do
      %{^unit => u} -> %{kind: :duration, unit: u, count: count}
      _ -> nil
    end
  end

  defp parse_timing(%{"kind" => "vague"}), do: %{kind: :vague}
  defp parse_timing(_), do: nil

  defp parse_modifier("this"), do: {:ok, :this}
  defp parse_modifier("next"), do: {:ok, :next}
  defp parse_modifier(nil), do: {:ok, nil}
  defp parse_modifier(_), do: :error

  # Used for the meeting date. Anything the schema should have prevented — a
  # missing key, a phrase like "last Tuesday", a number — reads as no date
  # rather than as a failed Extraction: a malformed date must never cost the
  # user their Action Points.
  defp parse_date(iso8601) when is_binary(iso8601) do
    case Date.from_iso8601(iso8601) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(_), do: nil

  defp config do
    Application.get_env(:action_points, __MODULE__, [])
  end
end
