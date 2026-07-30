defmodule ActionPoints.Meetings.TranscriptQuoteTest do
  use ExUnit.Case, async: true

  alias ActionPoints.Meetings.GroundingQuote
  alias ActionPoints.Meetings.TranscriptQuote

  @transcript """
  Priya: I'll send the Q3 report to finance
  by Friday.
  """

  describe "verify/2" do
    test "a quote that appears is returned with its whitespace collapsed" do
      assert TranscriptQuote.verify("the Q3 report   to finance\nby Friday", @transcript) ==
               "the Q3 report to finance by Friday"
    end

    test "a quote that does not appear is dropped" do
      assert TranscriptQuote.verify("by the end of the week", @transcript) == nil
    end

    test "an empty quote is dropped rather than matching every Transcript" do
      assert TranscriptQuote.verify("   \n ", @transcript) == nil
    end

    test "anything that is not text is dropped" do
      assert TranscriptQuote.verify(nil, @transcript) == nil
      assert TranscriptQuote.verify(%{"text" => "by Friday"}, @transcript) == nil
    end

    test "a missing Transcript verifies nothing" do
      assert TranscriptQuote.verify("by Friday", nil) == nil
    end
  end

  describe "the mechanism shared with Grounding Quotes" do
    test "both kinds of quote accept and reject the same words" do
      assert GroundingQuote.verify(["by Friday", "by the end of the week"], @transcript) ==
               ["by Friday"]

      assert TranscriptQuote.verify("by Friday", @transcript) == "by Friday"
      assert TranscriptQuote.verify("by the end of the week", @transcript) == nil
    end
  end
end
