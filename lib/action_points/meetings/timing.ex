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

  Every kind of the classification union resolves here: `absolute` (complete
  or partial), `weekday`, `relative_day`, `span_end`, and `duration`. Only
  `vague` — and anything malformed — pins nothing.
  """

  @typedoc "A day of the week, as the classification names it."
  @type weekday :: :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday

  @typedoc """
  What kind of timing language the model heard. `vague` deliberately has
  nowhere to put a date: the boundary between pinnable and unpinnable language
  is a property of this shape, not a request in prose.

  An `absolute` date may arrive with its year unsaid, or with neither its year
  nor its month — people rarely say a year aloud and often not a month either.
  It cannot arrive with a year but no month: a spoken year always follows the
  month it belongs to, so that shape is malformed rather than partial.
  """
  @type classification ::
          %{kind: :absolute, year: integer(), month: 1..12, day: 1..31}
          | %{kind: :absolute, year: nil, month: 1..12 | nil, day: 1..31}
          | %{kind: :weekday, weekday: weekday(), modifier: :this | :next | nil}
          | %{kind: :relative_day, offset: non_neg_integer()}
          | %{kind: :span_end, modifier: :this | :next, unit: :week | :month | :quarter}
          | %{kind: :duration, unit: :day | :week | :month, count: pos_integer() | quantifier()}
          | %{kind: :vague}

  @typedoc """
  A spoken quantifier a duration's count may be given as instead of a number.
  The lexicon is closed — one entry — and this type is its statement in the
  code: a quantifier is only ever decoded when it can be named here and tested
  individually.
  """
  @type quantifier :: :couple

  # "A couple of weeks" means two to very nearly everyone, so refusing it
  # would discard a real deadline on a technicality. "A few", "several",
  # "some" and "a while" are a different thing entirely: picking three, or
  # four, or five is invention dressed as resolution, so they classify as
  # vague and pin nothing. The lexicon is closed rather than open because the
  # moment quantifiers are read sensibly rather than enumerably, "a few"
  # follows and there is no principled place to stop.
  @quantifiers %{couple: 2}

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
  The closed quantifier lexicon: every spoken quantifier a duration's count
  may be given as, in place of a number.

  Enumerated here, where the decoding happens, so that an adapter asking the
  model for a quantifier and this module decoding one cannot drift apart. A
  word an adapter accepted but this module did not know would pin no date at
  all, and the user would lose a deadline to a table nobody noticed was two
  tables.
  """
  @spec quantifiers() :: [quantifier()]
  def quantifiers, do: Map.keys(@quantifiers)

  @doc """
  Resolves a classification against the meeting date. Returns the due date it
  pins, or `nil` when it pins nothing.

  Takes any map carrying a `kind`, not only a well-formed
  `t:classification/0`, and never raises: a map this module does not recognise
  pins nothing.
  """
  @spec resolve(%{required(:kind) => atom()} | nil, Date.t()) :: Date.t() | nil
  def resolve(nil, %Date{}), do: nil

  # A date is taken at its word — the parts that were said are never second-
  # guessed, and a completed date is left where it falls, weekend or not. Only
  # the parts the meeting left out are supplied here, and always forward: a
  # meeting cannot set a deadline in its own past, so the earliest completion
  # that is not behind the meeting date is the one it meant.
  def resolve(%{kind: :absolute, day: day} = classification, %Date{} = meeting_date)
      when is_integer(day) do
    complete(Map.get(classification, :year), Map.get(classification, :month), day, meeting_date)
  end

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

  # A count given as a spoken quantifier rather than a number decodes through
  # the closed lexicon and resolves as that number. A quantifier outside the
  # lexicon falls through to the catch-all and pins nothing, which is the
  # whole point of the lexicon being a table rather than a judgement.
  def resolve(%{kind: :duration, count: count} = classification, %Date{} = meeting_date)
      when is_map_key(@quantifiers, count) do
    resolve(%{classification | count: @quantifiers[count]}, meeting_date)
  end

  # "In two weeks": the meeting date plus the length spoken. A duration names
  # a length rather than a stretch of calendar, so — unlike a span end — it is
  # left where it lands, weekend or not. Someone who says "in two weeks" on a
  # Saturday has named a day; moving it would be answering a question nobody
  # asked.
  def resolve(%{kind: :duration, unit: unit, count: count}, %Date{} = meeting_date)
      when unit in [:day, :week] and is_integer(count) and count > 0 do
    Date.add(meeting_date, if(unit == :week, do: 7, else: 1) * count)
  end

  # Months count by the calendar rather than in thirty-day blocks, so "in a
  # month" said on the 15th is the 15th.
  def resolve(%{kind: :duration, unit: :month, count: count}, %Date{} = meeting_date)
      when is_integer(count) and count > 0 do
    shift_months(meeting_date, count)
  end

  # Everything else pins nothing. That covers two different things, which end
  # the same way: `vague`, which pins nothing by definition; and anything
  # malformed — an unknown kind, a misspelt weekday, an `absolute` date with
  # no day, a `span_end` in a unit this module does not know, a duration
  # counted in a quantifier outside the lexicon, a negative `relative_day`
  # offset. The second group is why this clause is a catch-all rather than a
  # list of known kinds: a malformed classification must never cost the user
  # their Action Point, so the resolver has to have an answer for a
  # classification nobody anticipated, not just for the ones it was written
  # against.
  def resolve(%{kind: _kind}, %Date{}), do: nil

  # A complete date needs no completing: the meeting said all three parts, so
  # the meeting date has no say. An impossible one (February 30th) pins
  # nothing — a malformed classification must never cost the user their
  # Action Point.
  defp complete(year, month, day, %Date{}) when is_integer(year) and is_integer(month) do
    case Date.new(year, month, day) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  # "March the 3rd": the meeting's own year if that date is still ahead of it,
  # otherwise the next. Two years are the whole search, so the 29th of
  # February said in the run-up to two non-leap years pins nothing rather than
  # reaching out to a leap year nobody could have meant.
  defp complete(nil, month, day, %Date{} = meeting_date) when is_integer(month) do
    Enum.find_value([meeting_date.year, meeting_date.year + 1], fn year ->
      forward(Date.new(year, month, day), meeting_date)
    end)
  end

  # "The 3rd": the first month from the meeting's own that both holds that day
  # and does not put it in the past. Two months on is the furthest the answer
  # can lie — the 30th, asked on the 31st of January, is March's, and no gap
  # in the calendar is longer than February's.
  defp complete(nil, nil, day, %Date{} = meeting_date) do
    Enum.find_value(0..2, fn ahead ->
      month = add_months(meeting_date, ahead)
      forward(Date.new(month.year, month.month, day), meeting_date)
    end)
  end

  # A year without the month it belongs to, or a part of the wrong type: the
  # meeting date can supply what was left unsaid, but not what came through
  # malformed.
  defp complete(_year, _month, _day, %Date{}), do: nil

  defp forward({:ok, %Date{} = date}, %Date{} = meeting_date), do: reject_past(date, meeting_date)
  defp forward({:error, _reason}, %Date{}), do: nil

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

  # The same date `count` months on, keeping its day where the target month
  # has one. A day the target month does not have — the 31st of a 30-day
  # month — lands on that month's last, which is the reading that keeps the
  # deadline inside the month "in a month" named.
  defp shift_months(%Date{} = date, count) do
    target = add_months(date, count)
    Date.new!(target.year, target.month, min(date.day, Date.days_in_month(target)))
  end

  defp add_months(%Date{} = date, count) do
    months = date.year * 12 + (date.month - 1) + count
    Date.new!(div(months, 12), rem(months, 12) + 1, 1)
  end

  defp last_working_day(%Date{} = date) do
    if weekend?(date), do: last_working_day(Date.add(date, -1)), else: date
  end

  defp weekend?(%Date{} = date), do: Date.day_of_week(date) > 5

  # A date behind the meeting that set it is worse than no date at all, so it
  # pins nothing. Two callers reach it: a month or quarter whose working days
  # are already spent (only reachable from a weekend meeting sitting past its
  # last working day), and a completion candidate that has already gone by.
  defp reject_past(%Date{} = resolved, %Date{} = meeting_date) do
    if Date.compare(resolved, meeting_date) == :lt, do: nil, else: resolved
  end
end
