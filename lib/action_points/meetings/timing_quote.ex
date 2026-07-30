defmodule ActionPoints.Meetings.TimingQuote do
  @moduledoc """
  Verifies Timing Quotes — the verbatim words the meeting used about *when* an
  Action Point is due (see CONTEXT.md). Verification is the same mechanical
  check a Grounding Quote gets (`ActionPoints.Meetings.TranscriptQuote`): the
  words must appear in the normalised Transcript, whitespace-insensitively, or
  they are dropped silently.

  Dropping governs the words only. The resolved due date is the application's
  own work on the model's Timing Classification (ADR-0008) and survives a
  dropped quote untouched — a paraphrased quote is no evidence that the date
  is wrong.
  """

  alias ActionPoints.Meetings.TranscriptQuote

  @doc """
  The Timing Quote as it should be stored, or `nil` when the model did not
  offer one or offered words the Transcript does not contain.
  """
  def verify(quote, transcript_text), do: TranscriptQuote.verify(quote, transcript_text)
end
