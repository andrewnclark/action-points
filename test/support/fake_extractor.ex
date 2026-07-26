defmodule ActionPoints.Meetings.FakeExtractor do
  @moduledoc """
  Test double for the Extractor port. Tests script its result with:

      Application.put_env(:action_points, :fake_extractor_result, {:ok, [...]})

  Without a scripted result it returns a canned successful Extraction.
  """

  @behaviour ActionPoints.Meetings.Extractor

  @impl true
  def extract(_transcript_text) do
    case Application.get_env(:action_points, :fake_extractor_result, default_result()) do
      :crash -> raise "fake extractor crash"
      result -> result
    end
  end

  defp default_result do
    {:ok,
     [
       %{
         title: "Follow up on the meeting",
         description: "A canned Action Point from the fake Extractor.",
         assignee_guess: nil,
         due_date: nil
       }
     ]}
  end
end
