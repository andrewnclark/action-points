defmodule ActionPoints.Meetings.Timing do
  @moduledoc """
  Timing classifications and the calendar arithmetic that resolves them.

  The division of labour: the model classifies, the application resolves. The
  Extractor reports what kind of timing language it heard about an Action
  Point's deadline — never a computed date — and this module resolves that
  classification against the Meeting Date. Reading language is what the model
  is good at; weekday-relative calendar arithmetic is what it is unreliable
  at, so the arithmetic lives here: deterministic, unit-testable, and fixable
  without touching the prompt.

  Pure by design — no repo, no clock, no API. Classification and anchor in,
  date or `nil` out. `nil` is a real answer: an unpinnable or not-yet-resolved
  classification produces an Action Point with no due date, never a guess.

  This module currently resolves `absolute` (complete dates), `weekday`, and
  `relative_day`. `span_end`, `duration`, and partial absolute dates are later
  tickets and resolve to `nil` until theirs land.
  """

  @typedoc "A day of the week, as the classification names it."
  @type weekday :: :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday

  @typedoc """
  What kind of timing language the model heard. `vague` deliberately has
  nowhere to put a date: the boundary between pinnable and unpinnable language
  is a property of this shape, not a request in prose.
  """
  @type classification ::
          %{kind: :absolute, year: integer() | nil, month: 1..12, day: 1..31}
          | %{kind: :weekday, weekday: weekday(), modifier: :this | :next | nil}
          | %{kind: :relative_day, offset: non_neg_integer()}
          | %{kind: :span_end, modifier: :this | :next, unit: :week | :month | :quarter}
          | %{kind: :duration, unit: :day | :week | :month, count: pos_integer()}
          | %{kind: :vague}

  @iso_days %{
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6,
    sunday: 7
  }

  @doc """
  Resolves a classification against the meeting date. Returns the due date it
  pins, or `nil` when it pins nothing.
  """
  @spec resolve(classification() | nil, Date.t()) :: Date.t() | nil
  def resolve(nil, %Date{}), do: nil

  def resolve(%{kind: :absolute, year: year, month: month, day: day}, %Date{})
      when is_integer(year) do
    # A stated impossible date (February 30th) pins nothing — a malformed
    # classification must never cost the user their Action Point.
    case Date.new(year, month, day) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  # A partial date ("March the 3rd", no year) needs year inference — a later
  # ticket. Until it lands, a partial date pins nothing.
  def resolve(%{kind: :absolute}, %Date{}), do: nil

  # "Next Wednesday": that weekday in the calendar week following the
  # meeting's week, weeks starting Monday. Collapses to the bare form when the
  # meeting falls late in the week and diverges when it falls early — exactly
  # how the two phrasings behave in English.
  def resolve(%{kind: :weekday, weekday: weekday, modifier: :next}, %Date{} = meeting_date) do
    meeting_date
    |> Date.beginning_of_week()
    |> Date.add(7 + (@iso_days[weekday] - 1))
  end

  # Bare weekday (and "this", which English uses the same way): the next
  # occurrence strictly after the meeting date. The meeting's own weekday
  # resolves seven days out — nobody says "by Wednesday" in a Wednesday
  # meeting meaning that same day.
  def resolve(%{kind: :weekday, weekday: weekday}, %Date{} = meeting_date) do
    days_ahead = Integer.mod(@iso_days[weekday] - Date.day_of_week(meeting_date), 7)
    Date.add(meeting_date, if(days_ahead == 0, do: 7, else: days_ahead))
  end

  def resolve(%{kind: :relative_day, offset: offset}, %Date{} = meeting_date)
      when is_integer(offset) and offset >= 0 do
    Date.add(meeting_date, offset)
  end

  # `vague` pins nothing by definition; `span_end` and `duration` pin nothing
  # until their tickets land the rules.
  def resolve(%{kind: kind}, %Date{}) when kind in [:vague, :span_end, :duration], do: nil
end
