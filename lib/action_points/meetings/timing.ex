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

  Total by design too: `resolve/2` never raises on a map carrying an atom
  `kind`. An unknown kind, a misspelt weekday, a missing field, a field of the
  wrong type — all of them pin nothing rather than crashing. The exception is
  `modifier`, which is read for one recognised value rather than validated: an
  unrecognised modifier reads as the bare form of its kind, the same as a
  missing one, because that is the reading that loses the user least.

  This guarantee lives here rather than in any one Extractor adapter, because
  `Extractor` is a port: a malformed classification must never cost the user
  their Action Points, and a second adapter should inherit that without having
  to reimplement the first one's sanitising. What an adapter still owes is the
  shape either side of the classification — an atom-keyed map with a `kind`,
  and values within the range a date can hold — not the vocabulary inside it.

  This module currently resolves `absolute` (complete dates), `weekday`,
  `relative_day`, and `span_end`. `duration` and partial absolute dates are
  later tickets and resolve to `nil` until theirs land.
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

  Takes any map carrying a `kind`, not only a well-formed
  `t:classification/0`, and never raises: a map this module does not recognise
  pins nothing.
  """
  @spec resolve(%{required(:kind) => atom()} | nil, Date.t()) :: Date.t() | nil
  def resolve(nil, %Date{}), do: nil

  def resolve(%{kind: :absolute, year: year, month: month, day: day}, %Date{})
      when is_integer(year) and is_integer(month) and is_integer(day) do
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
  def resolve(%{kind: :weekday, weekday: weekday, modifier: :next}, %Date{} = meeting_date)
      when is_map_key(@iso_days, weekday) do
    meeting_date
    |> Date.beginning_of_week()
    |> Date.add(7 + (@iso_days[weekday] - 1))
  end

  # Bare weekday (and "this", which English uses the same way): the next
  # occurrence strictly after the meeting date. The meeting's own weekday
  # resolves seven days out — nobody says "by Wednesday" in a Wednesday
  # meeting meaning that same day.
  def resolve(%{kind: :weekday, weekday: weekday}, %Date{} = meeting_date)
      when is_map_key(@iso_days, weekday) do
    days_ahead = Integer.mod(@iso_days[weekday] - Date.day_of_week(meeting_date), 7)
    Date.add(meeting_date, if(days_ahead == 0, do: 7, else: days_ahead))
  end

  def resolve(%{kind: :relative_day, offset: offset}, %Date{} = meeting_date)
      when is_integer(offset) and offset >= 0 do
    Date.add(meeting_date, offset)
  end

  # "By the end of the week": Friday, not Sunday. These are work deliverables,
  # and a task dated to a Sunday is visibly a machine's answer — one obviously
  # wrong date corrodes trust in every other date on the Review screen. So a
  # span resolves to the last *working* day it contains.
  #
  # A weekend meeting's own week has no working days left in it, and the
  # backward reading is impossible: nobody says "by the end of the week" on a
  # Saturday meaning the Friday just gone. So "this week" said on a weekend is
  # the working week ahead — which collapses it onto "next week", exactly as
  # the bare and `next` forms of a weekday collapse when the meeting falls
  # late in the week. The bump is `this`-only: the weekend is the tail of the
  # week it ends, so "next week" already names the week beginning Monday.
  def resolve(%{kind: :span_end, modifier: modifier, unit: :week}, %Date{} = meeting_date) do
    weeks = if modifier == :next or weekend?(meeting_date), do: 1, else: 0

    meeting_date
    |> Date.beginning_of_week()
    |> Date.add(7 * weeks + 4)
  end

  def resolve(%{kind: :span_end, modifier: modifier, unit: unit}, %Date{} = meeting_date)
      when unit in [:month, :quarter] do
    meeting_date
    |> span_last_day(unit, if(modifier == :next, do: 1, else: 0))
    |> last_working_day()
    |> reject_past(meeting_date)
  end

  # Everything else pins nothing. That covers three different things, all of
  # which end the same way: `vague`, which pins nothing by definition;
  # `duration`, which pins nothing until its ticket lands the rules; and
  # anything malformed — an unknown kind, a misspelt weekday, a `span_end` in
  # a unit this module does not know, a negative `relative_day` offset. The
  # last group is why this clause is a catch-all rather than a list of known
  # kinds: a malformed classification must never cost the user their Action
  # Point, so the resolver has to have an answer for a classification nobody
  # anticipated, not just for the ones it was written against.
  def resolve(%{kind: _kind}, %Date{}), do: nil

  # The final calendar day of the month or quarter `ahead` spans on from the
  # meeting's own — `ahead` counting in that same unit. Month arithmetic runs
  # on a month count rather than on dates, so December rolls into January of
  # the next year with no special case and no invalid intermediate date.
  defp span_last_day(%Date{} = date, :month, ahead) do
    date
    |> add_months(ahead)
    |> Date.end_of_month()
  end

  defp span_last_day(%Date{} = date, :quarter, ahead) do
    date.year
    |> Date.new!(div(date.month - 1, 3) * 3 + 1, 1)
    |> add_months(3 * ahead + 2)
    |> Date.end_of_month()
  end

  defp add_months(%Date{} = date, count) do
    months = date.year * 12 + (date.month - 1) + count
    Date.new!(div(months, 12), rem(months, 12) + 1, 1)
  end

  defp last_working_day(%Date{} = date) do
    if weekend?(date), do: last_working_day(Date.add(date, -1)), else: date
  end

  defp weekend?(%Date{} = date), do: Date.day_of_week(date) > 5

  # A month or quarter whose working days are already spent — only reachable
  # from a weekend meeting sitting past its last working day — pins nothing.
  # There is no working day left in the span the meeting named, and a deadline
  # before the meeting that set it is worse than no deadline at all.
  defp reject_past(%Date{} = resolved, %Date{} = meeting_date) do
    if Date.compare(resolved, meeting_date) == :lt, do: nil, else: resolved
  end
end
