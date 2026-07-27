defmodule ActionPoints.Meetings.Extractor do
  @moduledoc """
  The Extractor port: takes normalised transcript text and returns structured
  Action Point attributes, or a typed failure.

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
          required(:quotes) => [String.t()]
        }

  @callback extract(transcript_text :: String.t()) ::
              {:ok, [action_point_attrs()]} | {:error, atom()}
end
