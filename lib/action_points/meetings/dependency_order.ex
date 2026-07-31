defmodule ActionPoints.Meetings.DependencyOrder do
  @moduledoc """
  The order Review walks an Extraction's Action Points in (ADR-0010).

  One rule, applied in both directions — *decide the dependencies first, and
  make the consequential decision last, when you know the most*:

    * every Action Point a given one is blocked by comes before it, so its
      Blocker line is a statement about a decision already made rather than a
      dangling reference to something offscreen;
    * every Subtask comes before its parent, because rejecting a parent
      irreversibly promotes the survivors (ADR-0009) and that decision needs
      to know which children survived.

  Ties break on `position`, the meeting's own order, and on `id` after that,
  so the order is total and deterministic for any Extraction — including one
  with no relations at all, where it is simply position order.

  A tie is between two Action Points neither of which depends on the other, and
  the rule reads *at every step, take the earliest thing the meeting said that
  is ready to be decided* — never *pull a prerequisite forward past something
  already decidable*. So of three unrelated-looking Action Points where the
  first waits on the third, the walk runs 2, 3, 1: the first is deferred rather
  than the third promoted, because deferring respects a stated dependency
  while promoting would only be a guess at which tie mattered more.

  ## The acyclicity invariant

  The graph is acyclic by construction: `Blocker.sanitise/2` drops any edge
  that would close a loop when the Extraction finalises, and it is handed the
  proposed nesting along with the proposed Blockers precisely so that the loop
  it looks for is the one this module walks — a Blocker running from a parent
  down to its own Subtask closes a cycle just as surely as one between two
  siblings.

  This module assumes that invariant rather than defending against a cycle a
  second time: it breaks no edges and picks no arbitrary winner. A cycle
  reaching here would mean the hygiene upstream is broken, so `sort/1` says so
  and raises rather than inventing an order or looping forever.
  """

  alias ActionPoints.Meetings.ActionPoint

  @doc """
  Orders Action Points as Review walks them.

  Pure: feed it loaded `ActionPoint` structs with `blockers` preloaded. Every
  Action Point given is returned exactly once. Relations pointing outside the
  given list are ignored, so a subset orders as sensibly as a whole
  Extraction.
  """
  def sort([]), do: []

  def sort([_ | _] = action_points) do
    keys = Map.new(action_points, &{&1.id, {&1.position, &1.id}})
    ids = MapSet.new(action_points, & &1.id)

    edges = Enum.flat_map(action_points, &prerequisite_edges(&1, ids))

    successors = Enum.group_by(edges, &elem(&1, 0), &elem(&1, 1))
    waiting = Enum.frequencies_by(edges, &elem(&1, 1))
    ready = for %{id: id} <- action_points, not is_map_key(waiting, id), do: id

    by_id = Map.new(action_points, &{&1.id, &1})

    ready
    |> queue(keys)
    |> walk(waiting, successors, keys, [])
    |> Enum.map(&Map.fetch!(by_id, &1))
  end

  # The edges this Action Point contributes, each `{decided first, decided
  # after}`: the Action Points it waits on, and itself before its parent.
  defp prerequisite_edges(%ActionPoint{} = action_point, ids) do
    blocked_by =
      for blocker <- action_point.blockers,
          blocker.blocked_by_id in ids,
          do: {blocker.blocked_by_id, action_point.id}

    if action_point.parent_id in ids,
      do: [{action_point.id, action_point.parent_id} | blocked_by],
      else: blocked_by
  end

  # Everything decidable now, in the order it would be decided.
  defp queue(ids, keys), do: Enum.sort_by(ids, &Map.fetch!(keys, &1))

  defp walk([], waiting, _successors, _keys, decided) when waiting == %{} do
    Enum.reverse(decided)
  end

  defp walk([], _waiting, _successors, _keys, _decided) do
    raise "a cycle in the Extraction's relations reached DependencyOrder.sort/1, " <>
            "which the finalise-time hygiene in Blocker.sanitise/2 is supposed to make impossible"
  end

  defp walk([id | rest], waiting, successors, keys, decided) do
    {freed, waiting} =
      successors
      |> Map.get(id, [])
      |> Enum.reduce({[], waiting}, &release/2)

    (rest ++ freed)
    |> queue(keys)
    |> walk(waiting, successors, keys, [id | decided])
  end

  defp release(id, {freed, waiting}) do
    case Map.fetch!(waiting, id) - 1 do
      0 -> {[id | freed], Map.delete(waiting, id)}
      remaining -> {freed, Map.put(waiting, id, remaining)}
    end
  end
end
