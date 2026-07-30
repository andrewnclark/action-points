defmodule ActionPoints.Meetings.TranscriptQuote do
  @moduledoc """
  The mechanical check shared by every kind of quote the model claims to have
  copied out of a Transcript (Grounding Quote, Timing Quote): the words must
  really appear in the normalised Transcript, compared whitespace-insensitively.

  This is a mechanism, not a domain term — the domain terms are the quotes
  themselves, in `ActionPoints.Meetings.GroundingQuote` and
  `ActionPoints.Meetings.TimingQuote`, which both verify through here so
  "verbatim" means exactly one thing across the product.
  """

  @doc """
  A Transcript prepared as a haystack: one pass, so a caller verifying many
  quotes against the same Transcript does not renormalise it each time.
  """
  def normalise(text) when is_binary(text), do: collapse(text)

  @doc """
  The quote as it should be stored — whitespace collapsed — when it appears in
  the already-normalised Transcript, and `nil` when it does not. Quotes are
  stored collapsed: the words are the evidence, and a line break the model kept
  or lost is not.
  """
  def verified(quote, normalised_transcript) when is_binary(normalised_transcript) do
    with true <- is_binary(quote),
         collapsed when collapsed != "" <- collapse(quote),
         true <- String.contains?(normalised_transcript, collapsed) do
      collapsed
    else
      _ -> nil
    end
  end

  def verified(_quote, _normalised_transcript), do: nil

  @doc """
  `verified/2` against a raw Transcript, for a single quote.
  """
  def verify(quote, transcript_text) when is_binary(transcript_text) do
    verified(quote, normalise(transcript_text))
  end

  def verify(_quote, _transcript_text), do: nil

  defp collapse(text) do
    text |> String.split(~r/\s+/, trim: true) |> Enum.join(" ")
  end
end
