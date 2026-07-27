defmodule ActionPoints.Meetings.Transcript do
  @moduledoc """
  Normalises a raw Transcript before any Extraction starts — and therefore
  before any Credit could be charged.

  `.vtt`/`.srt` cue numbers, timestamps, and styling tags are stripped;
  speaker labels survive as `Name:` prefixes (Teams-style `<v Name>` voice
  tags are converted to the same prefix). Pasted text is sniffed, so a
  visitor who pastes the contents of a subtitle file still gets a clean
  transcript.

  Also the one place that reads an uploaded file's *name*, which carries two
  things worth having: the format to normalise as, and the date of the meeting.
  """

  @max_words 25_000
  @min_words 8

  # Year-first only: Zoom's `GMT20260312-140000` and an ISO `2026-03-12` both
  # read the same way round. The year must open the run of digits — a year
  # trailing a day-first date (`12-03-2026`, and worse `12-03-2026-1005`, where
  # the time that follows would read as a plausible month and day) is refused
  # by the leading lookbehind rather than read the wrong way round.
  @filename_date ~r/(?<!\d)(?<![\d][-_.\/])(20\d{2})[-_.]?(\d{2})[-_.]?(\d{2})(?!\d)/

  def max_words, do: @max_words
  def min_words, do: @min_words

  def format_from_filename(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".vtt" -> :vtt
      ".srt" -> :srt
      _ -> :txt
    end
  end

  @doc """
  The meeting date carried by an uploaded file's name, or nil when it carries
  none.

  Meeting tools bake the date into their exports, and it is the most reliable
  statement of when the meeting happened that reaches us. Only unambiguous
  year-first forms are read: `12/03/2026` could be March or December, and a
  silent nine-month error is far worse than no date at all — those fall through
  to nil so the caller keeps its own default.
  """
  def date_from_filename(filename) do
    @filename_date
    |> Regex.scan(filename)
    |> Enum.find_value(fn [_match, year, month, day] ->
      case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
        {:ok, date} -> date
        {:error, _invalid} -> nil
      end
    end)
  end

  def normalise(raw, format \\ :txt)

  def normalise(raw, :txt) do
    text = prepare(raw)

    if String.starts_with?(String.trim_leading(text), "WEBVTT") or srt?(text) do
      cues_to_text(text)
    else
      tidy(text)
    end
  end

  def normalise(raw, format) when format in [:vtt, :srt] do
    raw |> prepare() |> cues_to_text()
  end

  defp prepare(raw) do
    raw
    |> ensure_utf8()
    |> String.replace_prefix("﻿", "")
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end

  # Real-world .txt exports aren't always UTF-8 (Windows Notepad favours
  # UTF-16; older tools latin-1). Decode rather than crash mid-upload.
  defp ensure_utf8(<<0xFF, 0xFE, rest::binary>>), do: utf16_to_utf8(rest, :little)
  defp ensure_utf8(<<0xFE, 0xFF, rest::binary>>), do: utf16_to_utf8(rest, :big)

  defp ensure_utf8(raw) do
    if String.valid?(raw), do: raw, else: :unicode.characters_to_binary(raw, :latin1)
  end

  defp utf16_to_utf8(raw, endianness) do
    case :unicode.characters_to_binary(raw, {:utf16, endianness}) do
      utf8 when is_binary(utf8) -> utf8
      _undecodable -> :unicode.characters_to_binary(raw, :latin1)
    end
  end

  # SRT has no header — recognise it by its opening shape: a bare cue number
  # followed by a timestamp line.
  defp srt?(text) do
    case text |> String.trim_leading() |> String.split("\n") do
      [first, second | _] -> String.match?(String.trim(first), ~r/^\d+$/) and timestamp?(second)
      _ -> false
    end
  end

  defp cues_to_text(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.flat_map(&cue_block_text/1)
    |> Enum.join("\n")
    |> tidy()
    |> case do
      # No cues found: a mislabelled plain-text file, not an empty meeting.
      # Fall through to passthrough so the user isn't told it was "blank".
      "" -> tidy(text)
      parsed -> parsed
    end
  end

  defp cue_block_text(block) do
    lines = String.split(block, "\n", trim: true)

    if header_block?(lines) do
      []
    else
      case Enum.find_index(lines, &timestamp?/1) do
        # A block with no timestamp is cue-file furniture, not speech.
        nil ->
          []

        timestamp_index ->
          # Everything before the timestamp is the cue identifier; the speech
          # is what follows.
          lines
          |> Enum.drop(timestamp_index + 1)
          |> Enum.map(&clean_cue_line/1)
          |> Enum.reject(&(&1 == ""))
      end
    end
  end

  defp header_block?([first | _]),
    do: String.starts_with?(first, ["WEBVTT", "NOTE", "STYLE", "REGION"])

  defp header_block?([]), do: true

  defp timestamp?(line), do: String.contains?(line, "-->")

  defp clean_cue_line(line) do
    line
    |> String.replace(~r/<v(?:\.[^\s>]*)?\s+([^>]*)>/, "\\1: ")
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end

  defp tidy(text) do
    text
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  def word_count(text) do
    text |> String.split(~r/\s+/, trim: true) |> length()
  end
end
