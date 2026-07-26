defmodule ActionPoints.Meetings do
  @moduledoc """
  The meetings pipeline: Transcript → Extraction → Action Points → Review state.

  An Extraction is persisted server-side and keyed to the visitor's anonymous
  session token, so a preview survives signup. The Extraction itself runs as a
  background task; progress reaches LiveViews via PubSub (`subscribe/1`).
  """

  import Ecto.Query

  alias ActionPoints.Meetings.ActionPoint
  alias ActionPoints.Meetings.Extraction
  alias ActionPoints.Repo

  ## Extractions

  @doc """
  Returns a changeset for the paste-a-transcript form.
  """
  def change_extraction(%Extraction{} = extraction, attrs \\ %{}) do
    Extraction.changeset(extraction, attrs)
  end

  @doc """
  Creates a pending Extraction keyed to the anonymous session token.
  """
  def create_extraction(session_token, attrs) when is_binary(session_token) do
    %Extraction{session_token: session_token}
    |> Extraction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetches an Extraction (with its Action Points) only if it belongs to the
  given session token. Raises `Ecto.NoResultsError` otherwise, so a visitor
  can never read another session's Review.
  """
  def get_extraction!(id, session_token) when is_binary(session_token) do
    Extraction
    |> Repo.get_by!(id: id, session_token: session_token)
    |> Repo.preload(:action_points)
  end

  @doc """
  Runs the Extraction as a supervised background task — LLM latency on a big
  transcript is tens of seconds, so it never runs in the request cycle.
  """
  def start_extraction(%Extraction{} = extraction) do
    {:ok, _pid} =
      Task.Supervisor.start_child(ActionPoints.TaskSupervisor, fn ->
        run_extraction(extraction)
      end)

    :ok
  end

  @doc """
  Resets a failed Extraction and runs it again. Failures consume no Credit,
  so retrying is always free.
  """
  def retry_extraction(%Extraction{status: :failed} = extraction) do
    extraction = update_status!(extraction, %{status: :pending, failure_reason: nil})
    broadcast(extraction)
    start_extraction(extraction)
    extraction
  end

  @doc """
  The background-task body: marks the Extraction running, calls the Extractor
  port, and finalises success or failure. Each transition is broadcast.
  """
  def run_extraction(%Extraction{} = extraction) do
    extraction = update_status!(extraction, %{status: :running})
    broadcast(extraction)

    case extractor().extract(extraction.transcript_text) do
      {:ok, action_points} -> finalize_success(extraction, action_points)
      {:error, reason} -> finalize_failure(extraction, reason)
    end
  end

  defp finalize_success(extraction, action_points) do
    {:ok, extraction} =
      Repo.transaction(fn ->
        action_points
        |> Enum.with_index(1)
        |> Enum.each(fn {attrs, position} ->
          %ActionPoint{extraction_id: extraction.id, position: position}
          |> ActionPoint.changeset(attrs)
          |> Repo.insert!()
        end)

        update_status!(extraction, %{status: :succeeded})
      end)

    broadcast(extraction)
    extraction
  end

  defp finalize_failure(extraction, reason) do
    extraction = update_status!(extraction, %{status: :failed, failure_reason: to_string(reason)})
    broadcast(extraction)
    extraction
  end

  defp update_status!(extraction, attrs) do
    extraction
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end

  ## PubSub

  @doc """
  Subscribes the caller to status updates for one Extraction. Messages arrive
  as `{:extraction_updated, extraction_id}`.
  """
  def subscribe(%Extraction{id: id}) do
    Phoenix.PubSub.subscribe(ActionPoints.PubSub, topic(id))
  end

  defp broadcast(%Extraction{id: id}) do
    Phoenix.PubSub.broadcast(ActionPoints.PubSub, topic(id), {:extraction_updated, id})
  end

  defp topic(id), do: "extraction:#{id}"

  defp extractor do
    Application.fetch_env!(:action_points, :extractor)
  end

  @doc false
  # Used by tests and future tickets to assert what an Extraction produced.
  def list_action_points(%Extraction{id: extraction_id}) do
    Repo.all(
      from ap in ActionPoint,
        where: ap.extraction_id == ^extraction_id,
        order_by: [asc: ap.position]
    )
  end
end
