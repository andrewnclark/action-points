defmodule ActionPoints.Meetings.FakeExtractor do
  @moduledoc """
  Test double for the Extractor port. Tests script its result with:

      Application.put_env(:action_points, :fake_extractor_result,
        {:ok, %{action_points: [...], meeting_date: ~D[2026-05-04]}})

  The shape is the port's own — a double that accepted a looser one would let
  callers pass against a contract the real adapter never produces. Tests that
  care only about Action Points get their shorthand from
  `ActionPoints.ExtractionHelpers.stub_extractor/1` instead.

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
     %{
       meeting_date: nil,
       action_points: [
         %{
           title: "Follow up on the meeting",
           description: "A canned Action Point from the fake Extractor.",
           assignee_guess: nil,
           timing: nil,
           quotes: []
         }
       ]
     }}
  end
end
