defmodule ActionPoints.MeetingsTest do
  use ActionPoints.DataCase, async: false

  alias ActionPoints.Meetings

  @transcript "Priya: I'll send the Q3 report to finance by Friday."

  defp create_action_point(session_token) do
    {:ok, extraction} =
      Meetings.create_extraction(session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)

    Meetings.get_extraction!(extraction.id, session_token).action_points |> hd()
  end

  describe "create_extraction/2" do
    test "normalises an uploaded .vtt so cue junk never reaches the Extractor" do
      vtt = """
      WEBVTT

      1
      00:00:03.600 --> 00:00:06.240
      Priya Sharma: I'll send the Q3 report to finance by Friday.

      2
      00:00:06.900 --> 00:00:10.170
      Tom Baker: Great. I'll book the venue for the offsite.
      """

      {:ok, extraction} =
        Meetings.create_extraction("session", %{
          "transcript_text" => vtt,
          "source_format" => :vtt
        })

      refute extraction.transcript_text =~ "WEBVTT"
      refute extraction.transcript_text =~ "-->"
      assert extraction.transcript_text =~ "Priya Sharma: I'll send the Q3 report"
    end

    test "rejects an over-cap transcript before any Extraction exists" do
      over_cap = String.duplicate("word ", 25_001)

      {:error, changeset} =
        Meetings.create_extraction("session", %{"transcript_text" => over_cap})

      assert "is over the 25,000-word cap for one meeting (this transcript is about 25,001 words) — trim it and try again" in errors_on(
               changeset
             ).transcript_text

      assert Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 0
    end

    test "the cap is measured after normalisation, so timestamp junk doesn't count" do
      # ~24k words of speech wrapped in .srt cues: the raw file is far over
      # the cap counted naively, but the speech itself is under it.
      cue = fn i ->
        "#{i}\n00:0#{rem(i, 10)}:00,000 --> 00:0#{rem(i, 10)}:05,000\n" <>
          String.duplicate("word ", 24) <> "\n"
      end

      srt = Enum.map_join(1..1_000, "\n", cue)

      assert {:ok, _extraction} =
               Meetings.create_extraction("session", %{
                 "transcript_text" => srt,
                 "source_format" => :srt
               })
    end

    test "rejects a trivially short input with a helpful message" do
      {:error, changeset} =
        Meetings.create_extraction("session", %{"transcript_text" => "buy milk"})

      assert "is too short to be a meeting transcript — paste the whole thing" in errors_on(
               changeset
             ).transcript_text
    end

    test "rejects whitespace-only input as blank" do
      {:error, changeset} =
        Meetings.create_extraction("session", %{"transcript_text" => "   \n\n  "})

      assert "can't be blank" in errors_on(changeset).transcript_text
    end
  end

  describe "get_action_point!/2" do
    test "returns the Action Point for the owning session" do
      action_point = create_action_point("owner-session")

      assert Meetings.get_action_point!(action_point.id, "owner-session").id == action_point.id
    end

    test "raises for any other session, so no one curates another visitor's Review" do
      action_point = create_action_point("owner-session")

      assert_raise Ecto.NoResultsError, fn ->
        Meetings.get_action_point!(action_point.id, "other-session")
      end
    end
  end
end
