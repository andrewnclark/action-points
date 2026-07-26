defmodule ActionPoints.Meetings.TranscriptTest do
  use ExUnit.Case, async: true

  alias ActionPoints.Meetings.Transcript

  # A Zoom .vtt export: numeric cue identifiers, dot-millisecond timestamps,
  # speaker labels already inline as `Name:` prefixes.
  @zoom_vtt """
  WEBVTT

  1
  00:00:03.600 --> 00:00:06.240
  Priya Sharma: I'll send the Q3 report to finance by Friday.

  2
  00:00:06.900 --> 00:00:10.170
  Tom Baker: Great. I'll book the venue for the offsite.

  3
  00:00:10.500 --> 00:00:14.000
  Priya Sharma: Also let's loop in legal
  before the contract goes out.
  """

  # A Teams .vtt export: NOTE metadata blocks, GUID-style cue identifiers,
  # speakers carried in <v> voice tags rather than plain text.
  @teams_vtt """
  WEBVTT

  NOTE duration:"00:30:00"

  NOTE language:en-us

  b2f9e1c4-1f6a-4e0d-9c3a-7d5e8f1a2b3c/19-0
  00:00:03.600 --> 00:00:06.240
  <v Priya Sharma>I'll send the Q3 report to finance by Friday.</v>

  b2f9e1c4-1f6a-4e0d-9c3a-7d5e8f1a2b3c/21-0
  00:00:06.900 --> 00:00:10.170
  <v Tom Baker>Great. I'll book the venue for the offsite.</v>
  """

  # A Meet-style .srt: numeric cues, comma-millisecond timestamps.
  @srt """
  1
  00:00:03,600 --> 00:00:06,240
  Priya Sharma: I'll send the Q3 report to finance by Friday.

  2
  00:00:06,900 --> 00:00:10,170
  Tom Baker: Great. I'll book the venue for the offsite.
  """

  describe "normalise/2 with .vtt" do
    test "strips Zoom cue numbers and timestamps, keeps speaker labels and line breaks" do
      assert Transcript.normalise(@zoom_vtt, :vtt) == """
             Priya Sharma: I'll send the Q3 report to finance by Friday.
             Tom Baker: Great. I'll book the venue for the offsite.
             Priya Sharma: Also let's loop in legal
             before the contract goes out.\
             """
    end

    test "converts Teams <v> voice tags to Name: prefixes and drops NOTE blocks" do
      assert Transcript.normalise(@teams_vtt, :vtt) == """
             Priya Sharma: I'll send the Q3 report to finance by Friday.
             Tom Baker: Great. I'll book the venue for the offsite.\
             """
    end

    test "drops header metadata sharing the WEBVTT block and cue settings on timestamp lines" do
      vtt = """
      WEBVTT
      Kind: captions
      Language: en-US

      00:00:01.000 --> 00:00:04.000 align:start position:0%
      Priya: The launch moves to Tuesday.
      """

      assert Transcript.normalise(vtt, :vtt) == "Priya: The launch moves to Tuesday."
    end

    test "strips inline styling tags without losing the words" do
      vtt = """
      WEBVTT

      00:00:01.000 --> 00:00:04.000
      Priya: The <i>whole</i> team <c.highlight>must</c> review it.
      """

      assert Transcript.normalise(vtt, :vtt) == "Priya: The whole team must review it."
    end
  end

  describe "normalise/2 with .srt" do
    test "strips cue numbers and comma-millisecond timestamps, keeps speaker labels" do
      assert Transcript.normalise(@srt, :srt) == """
             Priya Sharma: I'll send the Q3 report to finance by Friday.
             Tom Baker: Great. I'll book the venue for the offsite.\
             """
    end

    test "a mislabelled plain-text file with no cues falls back to passthrough" do
      plain = "Priya: ship it on Tuesday.\nTom: agreed, I'll tell the team."

      assert Transcript.normalise(plain, :vtt) == plain
      assert Transcript.normalise(plain, :srt) == plain
    end

    test "handles CRLF line endings and a UTF-8 BOM, as real exports have" do
      srt = "﻿" <> String.replace(@srt, "\n", "\r\n")

      assert Transcript.normalise(srt, :srt) == """
             Priya Sharma: I'll send the Q3 report to finance by Friday.
             Tom Baker: Great. I'll book the venue for the offsite.\
             """
    end
  end

  describe "normalise/2 with pasted text" do
    test "passes plain text through, trimmed" do
      assert Transcript.normalise("  Priya: ship it.\n\nTom: agreed.  \n", :txt) ==
               "Priya: ship it.\n\nTom: agreed."
    end

    test "sniffs pasted WEBVTT content and normalises it as .vtt" do
      assert Transcript.normalise(@zoom_vtt, :txt) =~ "Priya Sharma: I'll send the Q3 report"
      refute Transcript.normalise(@zoom_vtt, :txt) =~ "-->"
      refute Transcript.normalise(@zoom_vtt, :txt) =~ "WEBVTT"
    end

    test "sniffs pasted SRT content and normalises it as .srt" do
      assert Transcript.normalise(@srt, :txt) =~ "Tom Baker: Great."
      refute Transcript.normalise(@srt, :txt) =~ "-->"
    end

    test "decodes a UTF-16 export (Windows Notepad) instead of crashing" do
      utf16 =
        <<0xFF, 0xFE>> <>
          :unicode.characters_to_binary("Priya: café budget approved.", :utf8, {:utf16, :little})

      assert Transcript.normalise(utf16, :txt) == "Priya: café budget approved."
    end

    test "decodes a latin-1 export instead of crashing" do
      latin1 = :unicode.characters_to_binary("Tom: revisit the café rota.", :utf8, :latin1)

      refute String.valid?(latin1)
      assert Transcript.normalise(latin1, :txt) == "Tom: revisit the café rota."
    end

    test "does not mistake a numbered agenda for SRT" do
      agenda = """
      1
      Budget review with the finance team next week
      2
      Hiring plan for the platform squad
      """

      assert Transcript.normalise(agenda, :txt) =~ "Budget review"
      assert Transcript.normalise(agenda, :txt) =~ "1"
    end
  end

  describe "word_count/1" do
    test "counts whitespace-separated words" do
      assert Transcript.word_count("Priya: I'll send the\nQ3 report.") == 6
      assert Transcript.word_count("") == 0
    end
  end

  describe "format_from_filename/1" do
    test "maps extensions case-insensitively, defaulting to :txt" do
      assert Transcript.format_from_filename("meeting.vtt") == :vtt
      assert Transcript.format_from_filename("Meeting Recording.VTT") == :vtt
      assert Transcript.format_from_filename("captions.srt") == :srt
      assert Transcript.format_from_filename("notes.txt") == :txt
      assert Transcript.format_from_filename("export") == :txt
    end
  end
end
