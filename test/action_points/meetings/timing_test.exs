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

    test "a partial date (no year) is not yet resolved" do
      # Year inference is a later ticket; until then a partial date pins nothing.
      assert Timing.resolve(%{kind: :absolute, year: nil, month: 3, day: 3}, @tuesday) == nil
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

  describe "unpinnable and not-yet-resolved kinds" do
    test "vague produces no due date" do
      assert Timing.resolve(%{kind: :vague}, @tuesday) == nil
    end

    test "no classification produces no due date" do
      assert Timing.resolve(nil, @tuesday) == nil
    end

    test "duration is a later ticket and resolves to nothing for now" do
      assert Timing.resolve(%{kind: :duration, unit: :week, count: 2}, @tuesday) == nil
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
      assert Timing.resolve(%{kind: :absolute, year: 2026, month: 13, day: 40}, @tuesday) == nil
      assert Timing.resolve(%{kind: :absolute, year: 2026, month: "07", day: 1}, @tuesday) == nil
      assert Timing.resolve(%{kind: :span_end}, @tuesday) == nil

      assert Timing.resolve(%{kind: :span_end, modifier: :this, unit: :fortnight}, @tuesday) ==
               nil

      assert Timing.resolve(%{kind: :duration}, @tuesday) == nil
    end
  end

  defp weekday(day, modifier \\ nil), do: %{kind: :weekday, weekday: day, modifier: modifier}

  defp span(modifier, unit), do: %{kind: :span_end, modifier: modifier, unit: unit}
end
