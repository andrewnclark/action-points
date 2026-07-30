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

  describe "unpinnable and not-yet-resolved kinds" do
    test "vague produces no due date" do
      assert Timing.resolve(%{kind: :vague}, @tuesday) == nil
    end

    test "no classification produces no due date" do
      assert Timing.resolve(nil, @tuesday) == nil
    end

    test "span_end and duration are later tickets and resolve to nothing for now" do
      assert Timing.resolve(%{kind: :span_end, modifier: :this, unit: :week}, @tuesday) == nil
      assert Timing.resolve(%{kind: :duration, unit: :week, count: 2}, @tuesday) == nil
    end
  end

  defp weekday(day, modifier \\ nil), do: %{kind: :weekday, weekday: day, modifier: modifier}
end
