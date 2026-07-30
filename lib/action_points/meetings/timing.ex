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
  date or no date out. No date is a real answer: a classification this module
  cannot pin produces an Action Point with no due date, never a guess.

  `pin/2` is the full answer and says *why* nothing was pinned; `resolve/2` is
  the short one, for callers that only need to know whether there is a date.
  The reason matters because "the meeting never mentioned when" and "the
  meeting set a deadline this module declined to pin" are different facts
  about a meeting and justify different treatment, and a bare `nil` cannot
  tell them apart. The four are exhaustive:

    * `:unspoken` — no timing language at all; there was no classification.
    * `:vague` — language too vague to pin ("in a few weeks"). The boundary
      between pinnable and unpinnable language is where the model put it.
    * `:malformed` — a classification this module could not read: an unknown
      kind, a misspelt weekday, a field of the wrong type or out of range, a
      quantifier outside the lexicon, a fully stated date the calendar does
      not hold. This one says nothing about the meeting and everything about
      the Extractor — it is a prompt or adapter defect, not vague language.
    * `:declined` — language read perfectly well, whose date a resolution rule
      then refused: a month or quarter span from a weekend meeting whose
      working days are already spent, or a partial date whose only completions
      lie past the year ahead the forward search reaches.

  The reason is deliberately not persisted. It is representable here, and
  nothing downstream stores it per Action Point; counting it over time is
  #84's question, not this module's.

  Total by design too: neither function raises on a map carrying an atom
  `kind`. An unknown kind, a misspelt weekday, a missing field, a field of the
  wrong type — all of them pin nothing rather than crashing. The exception is
  `modifier`, which is read for one recognised value rather than validated: an
  unrecognised modifier reads as the bare form of its kind, the same as a
  `nil` one, because that is the reading that loses the user least. (A
  `span_end` missing the `modifier` key altogether is a different thing and is
  `:malformed` — an adapter still owes every field of the shape, and a key it
  never sent is evidence about the adapter rather than about the meeting.)

  This guarantee lives here rather than in any one Extractor adapter, because
  `Extractor` is a port: a malformed classification must never cost the user
  their Action Points, and a second adapter should inherit that without having
  to reimplement the first one's sanitising. What an adapter still owes is the
  shape either side of the classification — an atom-keyed map with a `kind`,
  and values within the range a date can hold — not the vocabulary inside it.

  Every kind of the classification union resolves here: `absolute` (complete
  or partial), `weekday`, `relative_day`, `span_end`, and `duration`. What
  pins nothing is `vague`, anything malformed, and the two dates a rule
  declines — a spent month or quarter span, and a partial date whose only
  completions lie past the year ahead.

  One edge of the malformed/declined boundary is worth naming, because it
  moves with the prompt rather than with the meeting: "the 29th of February",
  said in the run-up to two non-leap years, is `:declined` when the model
  leaves the year unsaid and `:malformed` when the model supplies one that has
  no such day. Both readings are right on their own terms — the resolver only
  declines the parts it was itself completing — but it means a change to what
  the prompt asks for can move a case across the line.
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
  Why no due date was pinned. Four reasons rather than one `nil`, because they
  are four different facts about a meeting — see the moduledoc for what each
  one asserts and who it is evidence against.
  """
  @type unpinned_reason :: :unspoken | :vague | :malformed | :declined

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
  Pins a due date from a classification and the meeting date, or reports why
  it pinned none.

  Takes any map carrying a `kind`, not only a well-formed
  `t:classification/0`, and never raises: a map this module does not recognise
  is `:malformed` rather than an exception.
  """
  @spec pin(%{required(:kind) => atom()} | nil, Date.t()) ::
          {:pinned, Date.t()} | {:unpinned, unpinned_reason()}
  def pin(nil, %Date{}), do: {:unpinned, :unspoken}

  # A date is taken at its word — the parts that were said are never second-
  # guessed, and a completed date is left where it falls, weekend or not. Only
  # the parts the meeting left out are supplied here, and always forward: a
  # meeting cannot set a deadline in its own past, so the earliest completion
  # that is not behind the meeting date is the one it meant.
  def pin(%{kind: :absolute, year: year, month: month, day: day}, %Date{} = meeting_date)
      when is_integer(day) do
    complete(year, month, day, meeting_date)
  end

  # "Next Wednesday": that weekday in the calendar week following the
  # meeting's week, weeks starting Monday. Collapses to the bare form when the
  # meeting falls late in the week and diverges when it falls early — exactly
  # how the two phrasings behave in English.
  def pin(%{kind: :weekday, weekday: weekday, modifier: :next}, %Date{} = meeting_date)
      when is_map_key(@iso_days, weekday) do
    {:pinned,
     meeting_date
     |> Date.beginning_of_week()
     |> Date.add(7 + (@iso_days[weekday] - 1))}
  end

  # Bare weekday (and "this", which English uses the same way): the next
  # occurrence strictly after the meeting date. The meeting's own weekday
  # resolves seven days out — nobody says "by Wednesday" in a Wednesday
  # meeting meaning that same day.
  def pin(%{kind: :weekday, weekday: weekday}, %Date{} = meeting_date)
      when is_map_key(@iso_days, weekday) do
    days_ahead = Integer.mod(@iso_days[weekday] - Date.day_of_week(meeting_date), 7)
    {:pinned, Date.add(meeting_date, if(days_ahead == 0, do: 7, else: days_ahead))}
  end

  def pin(%{kind: :relative_day, offset: offset}, %Date{} = meeting_date)
      when is_integer(offset) and offset >= 0 do
    {:pinned, Date.add(meeting_date, offset)}
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
  def pin(%{kind: :span_end, modifier: modifier, unit: :week}, %Date{} = meeting_date) do
    weeks = if modifier == :next or weekend?(meeting_date), do: 1, else: 0

    {:pinned,
     meeting_date
     |> Date.beginning_of_week()
     |> Date.add(7 * weeks + 4)}
  end

  def pin(%{kind: :span_end, modifier: modifier, unit: unit}, %Date{} = meeting_date)
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
  def pin(%{kind: :duration, count: count} = classification, %Date{} = meeting_date)
      when is_map_key(@quantifiers, count) do
    pin(%{classification | count: @quantifiers[count]}, meeting_date)
  end

  # "In two weeks": the meeting date plus the length spoken. A duration names
  # a length rather than a stretch of calendar, so — unlike a span end — it is
  # left where it lands, weekend or not. Someone who says "in two weeks" on a
  # Saturday has named a day; moving it would be answering a question nobody
  # asked.
  def pin(%{kind: :duration, unit: unit, count: count}, %Date{} = meeting_date)
      when unit in [:day, :week] and is_integer(count) and count > 0 do
    {:pinned, Date.add(meeting_date, if(unit == :week, do: 7, else: 1) * count)}
  end

  # Months count by the calendar rather than in thirty-day blocks, so "in a
  # month" said on the 15th is the 15th.
  def pin(%{kind: :duration, unit: :month, count: count}, %Date{} = meeting_date)
      when is_integer(count) and count > 0 do
    {:pinned, shift_months(meeting_date, count)}
  end

  # Language the model itself judged too vague to pin. It is not malformed and
  # not declined: the boundary between pinnable and unpinnable language is a
  # property of the classification union, and this is the union saying so.
  def pin(%{kind: :vague}, %Date{}), do: {:unpinned, :vague}

  # Everything else was unreadable — an unknown kind, a misspelt weekday, an
  # `absolute` date with no day, a `span_end` in a unit this module does not
  # know, a duration counted in a quantifier outside the lexicon, a negative
  # `relative_day` offset. This is a catch-all rather than a list of known
  # kinds because a malformed classification must never cost the user their
  # Action Point: the resolver has to have an answer for a classification
  # nobody anticipated, not just for the ones it was written against.
  def pin(%{kind: _kind}, %Date{}), do: {:unpinned, :malformed}

  @doc """
  The due date a classification pins, or `nil` when it pins none.

  The short form of `pin/2`, for the callers — the great majority — that need
  only to know whether there is a date. It agrees with `pin/2` on every
  classification by construction, because it is `pin/2` with the reason
  dropped.
  """
  @spec resolve(%{required(:kind) => atom()} | nil, Date.t()) :: Date.t() | nil
  def resolve(classification, %Date{} = meeting_date) do
    case pin(classification, meeting_date) do
      {:pinned, %Date{} = date} -> date
      {:unpinned, _reason} -> nil
    end
  end

  # A complete date needs no completing: the meeting said all three parts, so
  # the meeting date has no say, and the calendar's answer is final. A date it
  # does not hold — February the 30th, or the 29th of a year that has no 29th
  # — was misheard rather than declined: nothing was left for this module to
  # supply, so it has nothing to refuse.
  defp complete(year, month, day, %Date{}) when is_integer(year) and is_integer(month) do
    case Date.new(year, month, day) do
      {:ok, date} -> {:pinned, date}
      {:error, _reason} -> {:unpinned, :malformed}
    end
  end

  # "March the 3rd": the meeting's own year if that date is still ahead of it,
  # otherwise the next. Two years are the whole search, so the 29th of
  # February said in the run-up to two non-leap years pins nothing rather than
  # reaching out to a leap year nobody could have meant.
  defp complete(nil, month, day, %Date{} = meeting_date) when is_integer(month) do
    if real_day?(month, day) do
      [meeting_date.year, meeting_date.year + 1]
      |> Enum.map(&Date.new(&1, month, day))
      |> earliest_not_behind(meeting_date)
    else
      {:unpinned, :malformed}
    end
  end

  # "The 3rd": the first month from the meeting's own that both holds that day
  # and does not put it in the past. Two months on is the furthest the answer
  # can lie — the 30th, asked on the 31st of January, is March's, and no gap
  # in the calendar is longer than February's.
  defp complete(nil, nil, day, %Date{} = meeting_date) when day in 1..31 do
    0..2
    |> Enum.map(fn ahead ->
      candidate = add_months(meeting_date, ahead)
      Date.new(candidate.year, candidate.month, day)
    end)
    |> earliest_not_behind(meeting_date)
  end

  # A year without the month it belongs to, a day no month has, or a part of
  # the wrong type: the meeting date can supply what was left unsaid, but not
  # what came through malformed.
  defp complete(_year, _month, _day, %Date{}), do: {:unpinned, :malformed}

  # The first candidate completion the calendar holds and the meeting has not
  # already passed. When none of them qualifies the search has run out, and a
  # completion further out than that is a date no meeting meant — a decline,
  # because the parts were read and only the years searched were refused. Only
  # the month-known caller can run out: with the month unsaid too, no run of
  # three consecutive months lacks a day the calendar has.
  defp earliest_not_behind(candidates, %Date{} = meeting_date) do
    Enum.find_value(candidates, {:unpinned, :declined}, fn
      {:ok, %Date{} = date} -> if Date.compare(date, meeting_date) != :lt, do: {:pinned, date}
      {:error, _reason} -> nil
    end)
  end

  # Whether a month and day name a day the calendar has at all, in any year.
  # February the 29th does and February the 30th never will, and the two are
  # different findings: one is a real date out of the search's reach, the
  # other is an Extractor emitting a day nobody could have said. A leap year
  # holds every month-and-day pair there is, so it settles the question.
  defp real_day?(month, day), do: match?({:ok, _date}, Date.new(2024, month, day))

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
  # pins nothing: a month or quarter whose working days are already spent,
  # only reachable from a weekend meeting sitting past its last working day.
  # The language was read perfectly well and the rule refused its date, which
  # is exactly what `:declined` names.
  defp reject_past(%Date{} = resolved, %Date{} = meeting_date) do
    if Date.compare(resolved, meeting_date) == :lt,
      do: {:unpinned, :declined},
      else: {:pinned, resolved}
  end
end
