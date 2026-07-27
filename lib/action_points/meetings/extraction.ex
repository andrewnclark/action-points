defmodule ActionPoints.Meetings.Extraction do
  @moduledoc """
  A single run of the model over one Transcript. It either succeeds — producing
  Action Points — or fails as a whole (see CONTEXT.md).

  Keyed to the anonymous visitor's session token; `user_id` is claimed at
  signup so the visitor's Extraction survives registration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ActionPoints.Meetings.Transcript

  schema "extractions" do
    field :session_token, :string
    field :transcript_text, :string
    field :source_format, Ecto.Enum, values: [:txt, :vtt, :srt], virtual: true, default: :txt
    field :status, Ecto.Enum, values: [:pending, :running, :succeeded, :failed], default: :pending
    field :failure_reason, :string

    # The anchor every relative deadline resolves against, and where it came
    # from: an unambiguous date in the uploaded filename, a date stated in the
    # Transcript itself, or — failing both — the visitor's own local date.
    field :meeting_date, :date
    field :meeting_date_source, Ecto.Enum, values: [:filename, :transcript, :assumed]

    belongs_to :user, ActionPoints.Accounts.User
    has_many :action_points, ActionPoints.Meetings.ActionPoint, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Normalises the Transcript (per `source_format`) and enforces the size caps
  here in the changeset, so no create path can start an Extraction — or charge
  a Credit — on junk input.
  """
  def changeset(extraction, attrs) do
    extraction
    |> cast(attrs, [:transcript_text, :source_format])
    |> normalise_transcript()
    |> validate_required([:transcript_text])
    |> validate_word_count()
  end

  defp normalise_transcript(changeset) do
    case get_change(changeset, :transcript_text) do
      nil ->
        changeset

      raw ->
        format = get_field(changeset, :source_format) || :txt
        put_change(changeset, :transcript_text, Transcript.normalise(raw, format))
    end
  end

  defp validate_word_count(changeset) do
    with text when is_binary(text) <- get_change(changeset, :transcript_text),
         words when words > 0 <- Transcript.word_count(text) do
      cond do
        words > Transcript.max_words() ->
          add_error(
            changeset,
            :transcript_text,
            "is over the #{with_thousands_separator(Transcript.max_words())}-word cap for one meeting " <>
              "(this transcript is about #{with_thousands_separator(words)} words) — trim it and try again"
          )

        words < Transcript.min_words() ->
          add_error(
            changeset,
            :transcript_text,
            "is too short to be a meeting transcript — paste the whole thing"
          )

        true ->
          changeset
      end
    else
      # Blank input is validate_required's to report.
      _ -> changeset
    end
  end

  defp with_thousands_separator(number) do
    number
    |> Integer.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
