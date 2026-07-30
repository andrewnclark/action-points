defmodule ActionPoints.Meetings.TimingTest do
  use ExUnit.Case, async: true

  alias ActionPoints.Meetings.Timing

  # Anchors, one per weekday position that matters:
  #   Mon 2026-07-27  Tue 2026-07-28  Wed 2026-07-29  Fri 2026-07-31
  @monday ~D[2026-07-27]
  @tuesday ~D[2026-07-28]
  @wednesday ~D[2026-07-29]
  @friday ~D[2026-07-31]

  describe "bare weekday" do
    test "resolves to the next occurrence strictly after the meeting date" do
      assert Timing.resolve(weekday(:wednesday), @tuesday) == ~D[2026-07-29]
      assert Timing.resolve(weekday(:friday), @tuesday) == ~D[2026-07-31]
    end

    test "a weekday earlier in the week than the meeting lands in the following week" do
      assert Timing.resolve(weekday(:monday), @friday) == ~D[2026-08-03]
      assert Timing.resolve(weekday(:wednesday), @friday) == ~D[2026-08-05]
    end

    test "the meeting's own weekday resolves seven days out, never same-day" do
      assert Timing.resolve(weekday(:wednesday), @wednesday) == ~D[2026-08-05]
      assert Timing.resolve(weekday(:sunday), ~D[2026-08-02]) == ~D[2026-08-09]
    end

    test "a `this` modifier behaves as the bare form" do
      assert Timing.resolve(weekday(:wednesday, :this), @tuesday) == ~D[2026-07-29]
      assert Timing.resolve(weekday(:wednesday, :this), @wednesday) == ~D[2026-08-05]
    end
  end

  describe "`next` modifier" do
    test "resolves to that weekday in the calendar week after the meeting's week" do
      # "Next Wednesday" said on a Tuesday never means tomorrow.
      assert Timing.resolve(weekday(:wednesday, :next), @tuesday) == ~D[2026-08-05]
      assert Timing.resolve(weekday(:friday, :next), @monday) == ~D[2026-08-07]
    end

    test "weeks start Monday: next Monday said on a Sunday is the very next day" do
      assert Timing.resolve(weekday(:monday, :next), ~D[2026-08-02]) == ~D[2026-08-03]
    end

    test "agrees with the bare form when the meeting falls late in the week" do
      for day <- [:monday, :wednesday] do
        assert Timing.resolve(weekday(day, :next), @friday) ==
                 Timing.resolve(weekday(day), @friday)
      end
    end

    test "diverges from the bare form when the meeting falls early in the week" do
      assert Timing.resolve(weekday(:wednesday), @tuesday) == ~D[2026-07-29]
      assert Timing.resolve(weekday(:wednesday, :next), @tuesday) == ~D[2026-08-05]
    end
  end

  describe "relative day" do
    test "resolves as an offset from the meeting date" do
      assert Timing.resolve(%{kind: :relative_day, offset: 0}, @tuesday) == @tuesday
      assert Timing.resolve(%{kind: :relative_day, offset: 1}, @tuesday) == ~D[2026-07-29]
    end
  end

  describe "absolute" do
    test "a complete stated date resolves to itself, whatever the anchor" do
      classification = %{kind: :absolute, year: 2026, month: 3, day: 3}
      assert Timing.resolve(classification, @tuesday) == ~D[2026-03-03]
      assert Timing.resolve(classification, @friday) == ~D[2026-03-03]
    end

    test "an impossible date resolves to nothing rather than crashing the Extraction" do
      assert Timing.resolve(%{kind: :absolute, year: 2026, month: 2, day: 30}, @tuesday) == nil
    end

    test "a stated date is taken at its word, weekend or past" do
      # 2026-03-07 is a Saturday, and both dates are behind the anchor. A date
      # said aloud is the speaker's choice, not the application's to move.
      assert Timing.resolve(%{kind: :absolute, year: 2026, month: 3, day: 7}, @tuesday) ==
               ~D[2026-03-07]
    end
  end

  describe "absolute: no year said" do
    test "completes to the meeting's own year when that date is still ahead" do
      assert Timing.resolve(partial(9, 3), @tuesday) == ~D[2026-09-03]
    end

    test "completes to the following year when the meeting's own year has passed it" do
      # "March the 3rd", said in July, is next March — not four months back.
      assert Timing.resolve(partial(3, 3), @tuesday) == ~D[2027-03-03]
    end

    test "the meeting's own date completes to itself, not a year on" do
      assert Timing.resolve(partial(7, 28), @tuesday) == @tuesday
    end

    test "a date neither year can hold pins nothing" do
      # The 29th of February, said in a run of non-leap years, is nearly two
      # years out — far past anything a meeting could have meant, so it pins
      # nothing rather than reaching for a date nobody said.
      assert Timing.resolve(partial(2, 29), @tuesday) == nil

      # Reached from a year that does hold it, it resolves like any other date.
      assert Timing.resolve(partial(2, 29), ~D[2028-01-05]) == ~D[2028-02-29]
    end

    test "an impossible day pins nothing" do
      assert Timing.resolve(partial(2, 30), @tuesday) == nil
      assert Timing.resolve(partial(13, 1), @tuesday) == nil
    end
  end

  describe "absolute: no month or year said" do
    test "completes to the meeting's own month when that day is still ahead" do
      assert Timing.resolve(day_only(31), @tuesday) == ~D[2026-07-31]
    end

    test "completes to the next month when the meeting's own month has passed it" do
      assert Timing.resolve(day_only(3), @tuesday) == ~D[2026-08-03]
    end

    test "the meeting's own day completes to itself" do
      assert Timing.resolve(day_only(28), @tuesday) == @tuesday
    end

    test "completion crosses the year boundary" do
      # Said on the 20th of December, "the 3rd" is January's.
      assert Timing.resolve(day_only(3), ~D[2026-12-20]) == ~D[2027-01-03]
    end

    test "skips months too short to hold the day" do
      # "The 31st", said in April, cannot be April's.
      assert Timing.resolve(day_only(31), ~D[2026-04-15]) == ~D[2026-05-31]
      assert Timing.resolve(day_only(30), ~D[2027-02-15]) == ~D[2027-03-30]
    end

    test "an impossible day pins nothing" do
      assert Timing.resolve(day_only(32), @tuesday) == nil
      assert Timing.resolve(day_only(0), @tuesday) == nil
    end
  end

  describe "span end: week" do
    test "this week is the Friday of the meeting's own week" do
      assert Timing.resolve(span(:this, :week), @monday) == ~D[2026-07-31]
      assert Timing.resolve(span(:this, :week), @tuesday) == ~D[2026-07-31]
      assert Timing.resolve(span(:this, :week), @friday) == ~D[2026-07-31]
    end

    test "next week is the Friday of the week after the meeting's" do
      assert Timing.resolve(span(:next, :week), @monday) == ~D[2026-08-07]
      assert Timing.resolve(span(:next, :week), @friday) == ~D[2026-08-07]
    end

    test "a weekend meeting means the working week ahead, never a Friday already past" do
      # Said on Saturday the 1st, "by the end of the week" cannot mean the
      # Friday that has been and gone.
      assert Timing.resolve(span(:this, :week), ~D[2026-08-01]) == ~D[2026-08-07]
      assert Timing.resolve(span(:this, :week), ~D[2026-08-02]) == ~D[2026-08-07]
    end

    test "a weekend meeting's `next week` is unshifted, and the two forms collapse" do
      # The weekend is the tail of the week it ends, so "next week" said on a
      # Saturday already names the week beginning Monday. The two forms
      # collapsing is the same behaviour the bare and `next` weekday forms show
      # when the meeting falls late in the week.
      assert Timing.resolve(span(:next, :week), ~D[2026-08-01]) == ~D[2026-08-07]
      assert Timing.resolve(span(:next, :week), ~D[2026-08-02]) == ~D[2026-08-07]

      for anchor <- [~D[2026-08-01], ~D[2026-08-02]] do
        assert Timing.resolve(span(:next, :week), anchor) ==
                 Timing.resolve(span(:this, :week), anchor)
      end
    end
  end

  describe "span end: month" do
    test "this month is the last working day of the meeting's month" do
      # July 2026 ends on a Friday; May 2026 ends on a Sunday.
      assert Timing.resolve(span(:this, :month), @tuesday) == ~D[2026-07-31]
      assert Timing.resolve(span(:this, :month), ~D[2026-05-12]) == ~D[2026-05-29]
    end

    test "next month is the last working day of the month after" do
      assert Timing.resolve(span(:next, :month), ~D[2026-05-12]) == ~D[2026-06-30]
      assert Timing.resolve(span(:next, :month), ~D[2026-09-15]) == ~D[2026-10-30]
    end

    test "next month crosses the year boundary" do
      assert Timing.resolve(span(:next, :month), ~D[2026-12-15]) == ~D[2027-01-29]
    end
  end

  describe "span end: quarter" do
    test "this quarter is the last working day of the meeting's quarter" do
      # Q3 2026 (Jul–Sep) ends Wednesday the 30th.
      assert Timing.resolve(span(:this, :quarter), @tuesday) == ~D[2026-09-30]
      assert Timing.resolve(span(:this, :quarter), ~D[2026-09-30]) == ~D[2026-09-30]
      # Q3 2028 ends on a Saturday.
      assert Timing.resolve(span(:this, :quarter), ~D[2028-08-10]) == ~D[2028-09-29]
    end

    test "every month of a quarter shares that quarter's end" do
      for month <- [1, 2, 3] do
        assert Timing.resolve(span(:this, :quarter), Date.new!(2026, month, 15)) ==
                 ~D[2026-03-31]
      end
    end

    test "next quarter is the last working day of the quarter after" do
      assert Timing.resolve(span(:next, :quarter), @tuesday) == ~D[2026-12-31]
      assert Timing.resolve(span(:next, :quarter), ~D[2028-08-10]) == ~D[2028-12-29]
    end

    test "next quarter crosses the year boundary" do
      assert Timing.resolve(span(:next, :quarter), ~D[2026-11-02]) == ~D[2027-03-31]
    end
  end

  describe "a span with no working day left in it" do
    test "this month, said on a weekend after the month's last working day, pins nothing" do
      # Saturday 31 October 2026: October's working days are spent, and
      # "the end of the month" cannot mean yesterday.
      assert Timing.resolve(span(:this, :month), ~D[2026-10-31]) == nil
    end

    test "this quarter, said on a weekend after the quarter's last working day, pins nothing" do
      # Saturday 30 September 2028 closes Q3 2028.
      assert Timing.resolve(span(:this, :quarter), ~D[2028-09-30]) == nil
    end

    test "the next span is unaffected — it still has working days in it" do
      assert Timing.resolve(span(:next, :month), ~D[2026-10-31]) == ~D[2026-11-30]
      assert Timing.resolve(span(:next, :quarter), ~D[2028-09-30]) == ~D[2028-12-29]
    end

    test "a weekend meeting mid-span resolves normally — only a spent span declines" do
      # Saturday 1 August 2026: August's working days are all still ahead.
      assert Timing.resolve(span(:this, :month), ~D[2026-08-01]) == ~D[2026-08-31]
      assert Timing.resolve(span(:this, :quarter), ~D[2026-08-01]) == ~D[2026-09-30]
    end

    test "the two weekend rules differ, and differ deliberately" do
      # Saturday 31 October 2026 shows both at once: the week span reinterprets
      # (the weekend belongs ambiguously to either side of a week, so the
      # working week ahead is what was meant), the month span declines (a
      # Saturday sits squarely inside October, whose work is simply finished).
      assert Timing.resolve(span(:this, :week), ~D[2026-10-31]) == ~D[2026-11-06]
      assert Timing.resolve(span(:this, :month), ~D[2026-10-31]) == nil
    end
  end

  describe "every span end is a working day, on or after the meeting" do
    test "across every span, every modifier, and four years of anchors" do
      anchors = Enum.map(0..(4 * 365), &Date.add(~D[2026-01-01], &1))

      for anchor <- anchors,
          modifier <- [:this, :next],
          unit <- [:week, :month, :quarter] do
        case Timing.resolve(span(modifier, unit), anchor) do
          nil ->
            :ok

          resolved ->
            assert Date.day_of_week(resolved) <= 5,
                   "#{modifier} #{unit} from #{anchor} resolved to #{resolved}, a weekend"

            assert Date.compare(resolved, anchor) != :lt,
                   "#{modifier} #{unit} from #{anchor} resolved to #{resolved}, before the meeting"
        end
      end
    end

    test "only a weekend meeting can fail to pin a span end" do
      anchors = Enum.map(0..(4 * 365), &Date.add(~D[2026-01-01], &1))

      for anchor <- anchors,
          Date.day_of_week(anchor) <= 5,
          modifier <- [:this, :next],
          unit <- [:week, :month, :quarter] do
        assert Timing.resolve(span(modifier, unit), anchor),
               "#{modifier} #{unit} from working day #{anchor} pinned nothing"
      end
    end
  end

  describe "duration" do
    test "days count on from the meeting date" do
      assert Timing.resolve(duration(:day, 1), @tuesday) == ~D[2026-07-29]
      assert Timing.resolve(duration(:day, 10), @tuesday) == ~D[2026-08-07]
    end

    test "weeks count on from the meeting date, landing on its own weekday" do
      assert Timing.resolve(duration(:week, 1), @tuesday) == ~D[2026-08-04]
      assert Timing.resolve(duration(:week, 2), @tuesday) == ~D[2026-08-11]
    end

    test "months count on by the calendar, not by thirty days" do
      assert Timing.resolve(duration(:month, 1), @tuesday) == ~D[2026-08-28]
      assert Timing.resolve(duration(:month, 2), @tuesday) == ~D[2026-09-28]
    end

    test "a month from a day the next month does not have lands on that month's last" do
      assert Timing.resolve(duration(:month, 1), ~D[2026-01-31]) == ~D[2026-02-28]
    end

    test "durations cross the year boundary" do
      assert Timing.resolve(duration(:month, 3), ~D[2026-11-15]) == ~D[2027-02-15]
      assert Timing.resolve(duration(:week, 4), ~D[2026-12-15]) == ~D[2027-01-12]
    end

    test "a resolved duration is left where it falls, weekend or not" do
      # Unlike a span end, a duration names a length rather than a stretch of
      # calendar: "in two weeks" said on a Saturday means that Saturday, and
      # nudging it would be answering a question nobody asked.
      assert Timing.resolve(duration(:week, 2), ~D[2026-08-01]) == ~D[2026-08-15]
    end
  end

  # The lexicon is closed — one entry — so that every quantifier the
  # application decodes can be named in a test. An open instruction to read
  # quantifiers sensibly could not be: "a few" would be three, or four, or
  # five, and the number would be the model's invention rather than the
  # meeting's word.
  describe "the closed quantifier lexicon" do
    test "every quantifier in the lexicon decodes, and the lexicon is one entry long" do
      # The list is the enumeration the closed lexicon promises: whatever it
      # holds, each entry pins a date. The length is asserted because an entry
      # added without a test of its own is precisely what "closed" forbids.
      assert Timing.quantifiers() == [:couple]

      for quantifier <- Timing.quantifiers() do
        assert Timing.resolve(duration(:week, quantifier), @tuesday)
      end
    end

    test "`a couple` decodes as two, in every unit" do
      for unit <- [:day, :week, :month] do
        assert Timing.resolve(duration(unit, :couple), @tuesday) ==
                 Timing.resolve(duration(unit, 2), @tuesday)
      end
    end

    test "no other quantifier decodes" do
      # "A few", "several", "some" and "a while" are the model's to classify as
      # vague. Should one arrive as a duration anyway, it pins nothing here:
      # the lexicon is the only door, and it has one entry.
      for quantifier <- [:few, :several, :some, :while, :couple_of_dozen] do
        assert Timing.resolve(duration(:week, quantifier), @tuesday) == nil
      end
    end
  end

  describe "the classification union" do
    test "every kind that can pin a date pins one" do
      # The union is closed, so it can be enumerated: no kind of timing
      # language the model can report is left waiting on a later ticket.
      for classification <- pinning_classifications() do
        assert %Date{} = Timing.resolve(classification, @tuesday)
      end
    end
  end

  describe "unpinnable kinds" do
    test "vague produces no due date" do
      assert Timing.resolve(%{kind: :vague}, @tuesday) == nil
    end

    test "no classification produces no due date" do
      assert Timing.resolve(nil, @tuesday) == nil
    end
  end

  # The resolver, not its callers, owns the guarantee that a malformed
  # classification costs the user nothing. `Extractor` is a port: a second
  # adapter must inherit that guarantee without having to reimplement the
  # Claude adapter's sanitising.
  describe "malformed classifications" do
    test "an unrecognised weekday pins nothing rather than raising" do
      assert Timing.resolve(weekday(:someday), @tuesday) == nil
      assert Timing.resolve(weekday(:someday, :this), @tuesday) == nil
      assert Timing.resolve(weekday(:someday, :next), @tuesday) == nil
      assert Timing.resolve(%{kind: :weekday}, @tuesday) == nil
      assert Timing.resolve(%{kind: :weekday, weekday: "monday"}, @tuesday) == nil
    end

    test "a negative relative day offset pins nothing rather than raising" do
      assert Timing.resolve(%{kind: :relative_day, offset: -1}, @tuesday) == nil
      assert Timing.resolve(%{kind: :relative_day, offset: :tomorrow}, @tuesday) == nil
      assert Timing.resolve(%{kind: :relative_day}, @tuesday) == nil
    end

    test "an unrecognised kind pins nothing rather than raising" do
      assert Timing.resolve(%{kind: :fortnight_end}, @tuesday) == nil
      assert Timing.resolve(%{kind: "weekday", weekday: :monday}, @tuesday) == nil
      assert Timing.resolve(%{kind: nil}, @tuesday) == nil
    end

    test "an unrecognised modifier reads as the bare form rather than pinning nothing" do
      # `modifier` is the one field read for a value rather than validated: an
      # unrecognised one loses the user nothing but the shift it asked for.
      assert Timing.resolve(weekday(:wednesday, "next"), @tuesday) ==
               Timing.resolve(weekday(:wednesday), @tuesday)

      for unit <- [:week, :month, :quarter] do
        assert Timing.resolve(%{kind: :span_end, modifier: :soon, unit: unit}, @tuesday) ==
                 Timing.resolve(span(:this, unit), @tuesday)
      end
    end

    test "a kind missing the fields it needs pins nothing rather than raising" do
      assert Timing.resolve(%{kind: :absolute}, @tuesday) == nil
      assert Timing.resolve(%{kind: :absolute, year: 2026}, @tuesday) == nil

      # An absent part is not an unsaid one: completion reads the nulls an
      # adapter put there, never a field it forgot to send.
      assert Timing.resolve(%{kind: :absolute, day: 3}, @tuesday) == nil

      assert Timing.resolve(%{kind: :absolute, year: 2026, month: 13, day: 40}, @tuesday) == nil
      assert Timing.resolve(%{kind: :absolute, year: 2026, month: "07", day: 1}, @tuesday) == nil
      assert Timing.resolve(%{kind: :absolute, year: nil, month: 3, day: "3"}, @tuesday) == nil

      # A year without the month it belongs to completes nothing: the missing
      # part is the one the meeting date cannot supply.
      assert Timing.resolve(%{kind: :absolute, year: 2027, month: nil, day: 3}, @tuesday) == nil
      assert Timing.resolve(%{kind: :span_end}, @tuesday) == nil

      assert Timing.resolve(%{kind: :span_end, modifier: :this, unit: :fortnight}, @tuesday) ==
               nil

      assert Timing.resolve(%{kind: :duration}, @tuesday) == nil
      assert Timing.resolve(duration(:fortnight, 1), @tuesday) == nil
      assert Timing.resolve(duration(:week, 0), @tuesday) == nil
      assert Timing.resolve(duration(:week, -2), @tuesday) == nil
      assert Timing.resolve(duration(:week, "2"), @tuesday) == nil
    end
  end

  # A `nil` due date used to mean four different things at once. `pin/2` is
  # where they are told apart: the four reasons are the whole of the answer,
  # and each is a different fact about the meeting.
  describe "why nothing was pinned" do
    test "no timing language at all is unspoken" do
      assert Timing.pin(nil, @tuesday) == {:unpinned, :unspoken}
    end

    test "language too vague to pin is vague" do
      assert Timing.pin(%{kind: :vague}, @tuesday) == {:unpinned, :vague}
    end

    test "a classification the resolver cannot read is malformed" do
      # Every one of these says the same thing about the Extractor rather than
      # about the meeting: it emitted something no meeting could have said.
      unreadable = [
        %{kind: :fortnight_end},
        %{kind: nil},
        %{kind: "weekday", weekday: :monday},
        weekday(:someday),
        %{kind: :weekday},
        %{kind: :weekday, weekday: "monday"},
        %{kind: :relative_day, offset: -1},
        %{kind: :relative_day, offset: :tomorrow},
        %{kind: :relative_day},
        %{kind: :absolute},
        %{kind: :absolute, day: 3},
        %{kind: :absolute, year: 2026},
        %{kind: :absolute, year: 2027, month: nil, day: 3},
        %{kind: :absolute, year: 2026, month: 13, day: 40},
        %{kind: :absolute, year: nil, month: 3, day: "3"},
        partial(2, 30),
        partial(13, 1),
        day_only(32),
        day_only(0),
        %{kind: :span_end},
        %{kind: :span_end, modifier: :this, unit: :fortnight},
        %{kind: :duration},
        duration(:fortnight, 1),
        duration(:week, 0),
        duration(:week, "2"),
        duration(:week, :few)
      ]

      for classification <- unreadable do
        assert Timing.pin(classification, @tuesday) == {:unpinned, :malformed},
               "#{inspect(classification)} was not reported malformed"
      end
    end

    test "a date the meeting stated in full and the calendar does not hold is malformed" do
      # Every part was said, so there is nothing for the resolver to supply and
      # nothing for it to decline: February the 30th, and February the 29th of
      # a year that has no such day, are dates the model got wrong.
      assert Timing.pin(%{kind: :absolute, year: 2026, month: 2, day: 30}, @tuesday) ==
               {:unpinned, :malformed}

      assert Timing.pin(%{kind: :absolute, year: 2026, month: 2, day: 29}, @tuesday) ==
               {:unpinned, :malformed}
    end

    test "a span whose working days are already spent is declined" do
      # Saturday 31 October 2026 and Saturday 30 September 2028: the language
      # was read perfectly well, and the rule refused the date it would pin.
      assert Timing.pin(span(:this, :month), ~D[2026-10-31]) == {:unpinned, :declined}
      assert Timing.pin(span(:this, :quarter), ~D[2028-09-30]) == {:unpinned, :declined}
    end

    test "a completion outside the search's forward reach is declined" do
      # "The 29th of February", said in the run-up to two non-leap years. The
      # day is a real one and the model heard it right — the resolver simply
      # will not reach past the year ahead for it. That is a decline, not a
      # defect, and the distinction is the whole point of the two reasons.
      assert Timing.pin(partial(2, 29), @tuesday) == {:unpinned, :declined}
      assert Timing.pin(partial(2, 29), ~D[2028-01-05]) == {:pinned, ~D[2028-02-29]}
    end

    test "every kind that pins a date reports it pinned" do
      for classification <- pinning_classifications() do
        assert {:pinned, %Date{}} = Timing.pin(classification, @tuesday)
      end
    end
  end

  # Callers that only need "is there a date" keep asking for one, and never
  # have to learn the reasons.
  describe "resolve/2, for callers that only need a date" do
    test "every reason collapses to nil, whichever of the four it is" do
      # Named one at a time rather than derived from `pin/2`, so that a reason
      # that stopped collapsing would fail here rather than agree with itself.
      unpinned = [
        {nil, @tuesday},
        {%{kind: :vague}, @tuesday},
        {%{kind: :fortnight_end}, @tuesday},
        {weekday(:someday), @tuesday},
        {partial(2, 30), @tuesday},
        {partial(2, 29), @tuesday},
        {span(:this, :month), ~D[2026-10-31]}
      ]

      for {classification, anchor} <- unpinned do
        assert Timing.resolve(classification, anchor) == nil,
               "#{inspect(classification)} from #{anchor} resolved to a date"
      end
    end

    test "a pinned date arrives bare, exactly as pin/2 pinned it" do
      for classification <- pinning_classifications() do
        {:pinned, date} = Timing.pin(classification, @tuesday)
        assert Timing.resolve(classification, @tuesday) == date
      end
    end
  end

  defp pinning_classifications do
    [
      %{kind: :absolute, year: 2027, month: 3, day: 3},
      partial(3, 3),
      day_only(3),
      weekday(:wednesday),
      weekday(:wednesday, :next),
      %{kind: :relative_day, offset: 1},
      span(:this, :week),
      span(:next, :month),
      span(:this, :quarter),
      duration(:day, 10),
      duration(:week, :couple),
      duration(:month, 1)
    ]
  end

  defp partial(month, day), do: %{kind: :absolute, year: nil, month: month, day: day}

  defp day_only(day), do: %{kind: :absolute, year: nil, month: nil, day: day}

  defp weekday(day, modifier \\ nil), do: %{kind: :weekday, weekday: day, modifier: modifier}

  defp span(modifier, unit), do: %{kind: :span_end, modifier: modifier, unit: unit}

  defp duration(unit, count), do: %{kind: :duration, unit: unit, count: count}
end
