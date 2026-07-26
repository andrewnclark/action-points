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
  - description: enough context from the conversation that the task is
    actionable on its own
  - assignee_guess: the person responsible, grounded in the speaker labels
    when the transcript has them; null when nobody was clearly responsible
  - due_date: an ISO 8601 date, only when a date was actually said aloud
    (resolve relative dates against the transcript's context if possible,
    otherwise leave null); never invent one

  Include vague or tentative commitments ("we should probably look into
  that") as their own Action Points — the user rejects noise during Review,
  so it is better to surface a doubtful item than to silently drop it.
  Do not invent tasks that were not discussed.
  """

  @output_schema %{
    "type" => "object",
    "properties" => %{
      "action_points" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "title" => %{"type" => "string"},
            "description" => %{"type" => "string"},
            "assignee_guess" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]},
            "due_date" => %{
              "anyOf" => [%{"type" => "string", "format" => "date"}, %{"type" => "null"}]
            }
          },
          "required" => ["title", "description", "assignee_guess", "due_date"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["action_points"],
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
         {:ok, %{"action_points" => action_points}} <- Jason.decode(text) do
      {:ok, Enum.map(action_points, &to_attrs/1)}
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
      due_date: parse_date(action_point["due_date"])
    }
  end

  defp parse_date(nil), do: nil

  defp parse_date(iso8601) do
    case Date.from_iso8601(iso8601) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp config do
    Application.get_env(:action_points, __MODULE__, [])
  end
end
