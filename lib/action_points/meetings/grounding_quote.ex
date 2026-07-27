defmodule ActionPoints.Meetings.GroundingQuote do
  @moduledoc """
  Verifies Grounding Quotes — short verbatim excerpts attached to an Action
  Point as evidence (see CONTEXT.md). Verification is mechanical: a quote
  survives only if it appears in the normalised Transcript text, so a quote
  cannot be hallucinated the way prose can. A failing quote is dropped
  silently — the guarantee is that no shown quote is invented, not that the
  model quoted well.
  """

  @max_quotes 3

  def max_quotes, do: @max_quotes

  @doc """
  The quotes that actually appear in the Transcript, whitespace-insensitively,
  capped at #{@max_quotes}. Quotes are stored with their whitespace collapsed:
  the words are the evidence, and a line break the model kept or lost is not.
  """
  def verify(quotes, transcript_text) when is_list(quotes) and is_binary(transcript_text) do
    haystack = collapse_whitespace(transcript_text)

    quotes
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&collapse_whitespace/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&String.contains?(haystack, &1))
    |> Enum.take(@max_quotes)
  end

  def verify(_quotes, _transcript_text), do: []

  defp collapse_whitespace(text) do
    text |> String.split(~r/\s+/, trim: true) |> Enum.join(" ")
  end
end
