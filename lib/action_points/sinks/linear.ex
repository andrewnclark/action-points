defmodule ActionPoints.Sinks.Linear do
  @moduledoc """
  Real Task Sink adapter: Linear's GraphQL API, authenticated with the user's
  personal API key (ADR-0002 — no OAuth at launch).
  """

  @behaviour ActionPoints.Sinks.TaskSink

  @url "https://api.linear.app/graphql"

  @impl true
  def validate_credentials(credentials) do
    case query(credentials, "{ viewer { id } }", %{}) do
      {:ok, %{"viewer" => %{"id" => _id}}} -> :ok
      {:ok, _data} -> {:error, :api_error}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_teams(credentials) do
    case query(credentials, "{ teams { nodes { id name } } }", %{}) do
      {:ok, %{"teams" => %{"nodes" => nodes}}} ->
        {:ok, Enum.map(nodes, &%{id: &1["id"], name: &1["name"]})}

      {:ok, _data} ->
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_users(credentials) do
    case query(credentials, "{ users { nodes { id name displayName } } }", %{}) do
      {:ok, %{"users" => %{"nodes" => nodes}}} ->
        {:ok, Enum.map(nodes, &%{id: &1["id"], name: &1["displayName"] || &1["name"]})}

      {:ok, _data} ->
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def push_task(credentials, team_id, task) do
    mutation = """
    mutation IssueCreate($input: IssueCreateInput!) {
      issueCreate(input: $input) { success issue { id identifier url } }
    }
    """

    input =
      %{
        "teamId" => team_id,
        "title" => task.title,
        "description" => task.description,
        "assigneeId" => task.assignee_id,
        "dueDate" => task.due_date && Date.to_iso8601(task.due_date)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case query(credentials, mutation, %{"input" => input}) do
      {:ok, %{"issueCreate" => %{"success" => true, "issue" => issue}}} ->
        {:ok, %{id: issue["id"], identifier: issue["identifier"], url: issue["url"]}}

      {:ok, _data} ->
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query(%{api_key: api_key}, document, variables) do
    request_options =
      [
        json: %{query: document, variables: variables},
        headers: [{"authorization", api_key}],
        receive_timeout: 30_000
      ] ++ Keyword.get(config(), :req_options, [])

    case Req.post(@url, request_options) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data} = body}}
      when not is_map_key(body, "errors") ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:error, if(authentication_error?(body), do: :invalid_key, else: :api_error)}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :invalid_key}

      {:ok, %Req.Response{status: 400, body: body}} ->
        {:error, if(authentication_error?(body), do: :invalid_key, else: :api_error)}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        {:error, :unavailable}

      {:ok, %Req.Response{}} ->
        {:error, :api_error}

      {:error, _exception} ->
        {:error, :unavailable}
    end
  end

  # Linear reports a bad key as a GraphQL error whose extensions type is
  # "authentication error" (with HTTP 400), not always as a bare 401.
  defp authentication_error?(%{"errors" => errors}) when is_list(errors) do
    Enum.any?(errors, fn error ->
      type = get_in(error, ["extensions", "type"]) || ""
      String.contains?(String.downcase(type), "authentication")
    end)
  end

  defp authentication_error?(_body), do: false

  defp config do
    Application.get_env(:action_points, __MODULE__, [])
  end
end
