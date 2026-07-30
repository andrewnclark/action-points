defmodule ActionPoints.Meetings.Extractor do
  @moduledoc """
  The Extractor port: takes normalised transcript text and returns what the
  model read out of it — the Action Points, plus the meeting's own date when
  the Transcript states one — or a typed failure.

  Real adapter: `ActionPoints.Meetings.Extractor.Claude`. Tests replace it with
  `ActionPoints.Meetings.FakeExtractor` via the `:extractor` application env.
  """

  @type action_point_attrs :: %{
          required(:title) => String.t(),
          required(:description) => String.t() | nil,
          required(:assignee_guess) => String.t() | nil,
          required(:due_date) => Date.t() | nil,
          # Up to three candidate Grounding Quotes — claimed verbatim by the
          # model, verified against the Transcript only when the Extraction
          # finalises.
          required(:quotes) => [String.t()],
          # Proposed Blockers: the 1-based positions, in this same output, of
          # the sibling Action Points this one waits on — proposed only when
          # the transcript states the ordering. Sanitised (self-references,
          # cycles, duplicates, dangling positions) when the Extraction
          # finalises.
          required(:blocked_by) => [pos_integer()]
        }

  @typedoc """
  A successful read of one Transcript. `meeting_date` is the date the Transcript
  itself states the meeting happened on — `nil` when it says nothing — and is
  the strongest evidence the anchor chain has, so it is carried alongside the
  Action Points rather than buried in them.
  """
  @type result :: %{
          required(:action_points) => [action_point_attrs()],
          required(:meeting_date) => Date.t() | nil
        }

  @callback extract(transcript_text :: String.t()) :: {:ok, result()} | {:error, atom()}
end
