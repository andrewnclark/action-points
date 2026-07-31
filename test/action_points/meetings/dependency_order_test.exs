defmodule ActionPoints.Meetings.DependencyOrderTest do
  @moduledoc """
  The walk's order, tested on structs rather than rows: `sort/1` is pure, and
  the relations it reads are the ones the Extraction already persisted.
  """

  use ExUnit.Case, async: true

  alias ActionPoints.Meetings.ActionPoint
  alias ActionPoints.Meetings.Blocker
  alias ActionPoints.Meetings.DependencyOrder

  # An Action Point as `sort/1` sees one: an id, a position, an optional
  # parent, and the ids it is blocked by.
  defp action_point(id, opts \\ []) do
    %ActionPoint{
      id: id,
      position: Keyword.get(opts, :position, id),
      parent_id: Keyword.get(opts, :parent_id),
      blockers:
        for blocked_by_id <- Keyword.get(opts, :blocked_by, []) do
          %Blocker{action_point_id: id, blocked_by_id: blocked_by_id}
        end
    }
  end

  defp order(action_points), do: Enum.map(DependencyOrder.sort(action_points), & &1.id)

  describe "an Extraction with no relations" do
    test "is walked in position order" do
      assert order([
               action_point(7, position: 3),
               action_point(8, position: 1),
               action_point(9, position: 2)
             ]) == [8, 9, 7]
    end

    test "orders an empty Extraction and a single Action Point" do
      assert DependencyOrder.sort([]) == []
      assert order([action_point(1)]) == [1]
    end
  end

  describe "Blockers before the blocked" do
    test "the Action Point waited on is decided first, whatever its position" do
      # 1 waits on 3, so it cannot come first; 2 and 3 are tied and 2 is the
      # meeting's earlier word. The walk defers 1 rather than pulling 3
      # forward past 2.
      assert order([
               action_point(1, position: 1, blocked_by: [3]),
               action_point(2, position: 2),
               action_point(3, position: 3)
             ]) == [2, 3, 1]
    end

    test "a chain unwinds from its far end" do
      assert order([
               action_point(1, position: 1, blocked_by: [2]),
               action_point(2, position: 2, blocked_by: [3]),
               action_point(3, position: 3)
             ]) == [3, 2, 1]
    end

    test "an Action Point waiting on two is decided after both" do
      assert order([
               action_point(1, position: 1, blocked_by: [2, 3]),
               action_point(2, position: 2),
               action_point(3, position: 3)
             ]) == [2, 3, 1]
    end

    test "a Blocker pointing outside the given set is ignored" do
      assert order([action_point(1, blocked_by: [99]), action_point(2)]) == [1, 2]
    end
  end

  describe "children before parents" do
    test "a parent is decided after its Subtasks, knowing which survived" do
      assert order([
               action_point(1, position: 1),
               action_point(2, position: 2, parent_id: 1),
               action_point(3, position: 3, parent_id: 1)
             ]) == [2, 3, 1]
    end

    test "a family is walked before a later unrelated Action Point" do
      assert order([
               action_point(1, position: 1),
               action_point(2, position: 2, parent_id: 1),
               action_point(3, position: 3)
             ]) == [2, 1, 3]
    end
  end

  describe "the two rules together" do
    test "a parent waits for its children and for what they wait on" do
      # 1 is the parent of 2; 2 is blocked by 3, which sits last by position.
      assert order([
               action_point(1, position: 1),
               action_point(2, position: 2, parent_id: 1, blocked_by: [3]),
               action_point(3, position: 3)
             ]) == [3, 2, 1]
    end
  end

  describe "ties" do
    test "break on position, so the meeting's own order survives" do
      assert order([
               action_point(1, position: 2, blocked_by: [3]),
               action_point(2, position: 1, blocked_by: [3]),
               action_point(3, position: 3)
             ]) == [3, 2, 1]
    end

    test "break on id when two Action Points share a position" do
      assert order([action_point(6, position: 1), action_point(5, position: 1)]) == [5, 6]
    end

    test "give the same order however the input is shuffled" do
      action_points = [
        action_point(1, position: 1, blocked_by: [4]),
        action_point(2, position: 2, parent_id: 1),
        action_point(3, position: 3),
        action_point(4, position: 4)
      ]

      for _ <- 1..25 do
        assert order(Enum.shuffle(action_points)) == order(action_points)
      end
    end
  end

  describe "totality and the edge property" do
    # Every Action Point comes back exactly once, and every relation is
    # respected. The graphs are generated rather than written out — see
    # `generated_graph/0` for how they are kept acyclic — and seeded, so a
    # failure is reproducible without a property-testing dependency.
    test "every edge's tail is decided before its head, over generated graphs" do
      for seed <- 1..200 do
        :rand.seed(:exsss, {seed, seed, seed})
        action_points = generated_graph()
        ordered = DependencyOrder.sort(action_points)
        places = Map.new(Enum.with_index(ordered), fn {ap, i} -> {ap.id, i} end)

        assert map_size(places) == length(action_points),
               "seed #{seed}: the order dropped or duplicated an Action Point"

        for {tail, head} <- edges(action_points) do
          assert places[tail] < places[head],
                 "seed #{seed}: #{tail} must be decided before #{head}"
        end
      end
    end
  end

  describe "the acyclicity invariant" do
    test "a cycle reaching sort/1 is reported as the broken invariant it is" do
      cycle = [action_point(1, blocked_by: [2]), action_point(2, blocked_by: [1])]

      assert_raise RuntimeError, ~r/cycle/, fn -> DependencyOrder.sort(cycle) end
    end
  end

  # A random acyclic graph. Acyclicity comes for free: ids are shuffled into a
  # labelling, and every relation is drawn so that its `decided first` end sits
  # earlier in that labelling than its `decided after` end. A Blocker therefore
  # comes from behind and a parent goes on ahead — the two rules pointing in
  # opposite directions through the graph, which is the whole point of them.
  defp generated_graph do
    count = Enum.random(1..9)
    ids = Enum.shuffle(1..count)

    for {id, index} <- Enum.with_index(ids) do
      action_point(id,
        position: Enum.random(1..count),
        parent_id: maybe_one(Enum.drop(ids, index + 1)),
        blocked_by: Enum.filter(Enum.take(ids, index), fn _ -> Enum.random(1..3) == 1 end)
      )
    end
  end

  defp maybe_one([]), do: nil

  defp maybe_one(candidates) do
    if Enum.random(1..3) == 1, do: Enum.random(candidates)
  end

  # Every relation as a `{decided first, decided after}` pair.
  defp edges(action_points) do
    Enum.flat_map(action_points, fn action_point ->
      parent =
        if action_point.parent_id, do: [{action_point.id, action_point.parent_id}], else: []

      parent ++ for b <- action_point.blockers, do: {b.blocked_by_id, action_point.id}
    end)
  end
end
