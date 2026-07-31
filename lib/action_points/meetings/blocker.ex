defmodule ActionPoints.Meetings.Blocker do
  @moduledoc """
  A Blocker: a blocked-by relation between two Action Points of the same
  Extraction, proposed by the Extraction and curated at Review (see
  CONTEXT.md). `action_point` is the blocked Action Point, `blocked_by` the
  one it waits on.

  Realised as a real relation in the Task Sink at Push; `sink_relation_id`
  records that moment, so a Push retry creates only the edges still missing —
  the same idempotent bookkeeping the created-issue reference gives issues.
  """

  use Ecto.Schema

  schema "blockers" do
    belongs_to :action_point, ActionPoints.Meetings.ActionPoint
    belongs_to :blocked_by, ActionPoints.Meetings.ActionPoint

    field :sink_relation_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Mechanical hygiene for the Extraction's proposed relations. Takes
  `{position, blocked_by_positions}` pairs — one per Action Point, in
  position order — and returns the `{blocked_position, blocking_position}`
  edges that could actually exist: self-references, references to positions
  outside the output, duplicate edges, and any edge that would close a cycle
  are dropped without failing the Extraction.

  Edges are considered in the order the Extraction proposed them, so a cycle
  is broken at the edge that closes it, not at an arbitrary one.

  `nesting` carries the Subtask relations the same Extraction proposed, as
  already-sanitised `{parent_position, child_position}` pairs. They are
  dependencies in exactly the same sense — Review decides a Subtask before its
  parent, and a Blocker before what it blocks (ADR-0010) — so they take part in
  the cycle check without ever being returned as Blockers. Without them a
  Blocker running from a parent down to its own Subtask would survive, and the
  loop it closes has no order for the walk to find. Nesting is checked, never
  dropped: hierarchy is settled before this runs, and a Blocker is the cheaper
  of the two to lose.
  """
  def sanitise(proposals, nesting \\ []) do
    count = length(proposals)

    {kept, _graph} =
      proposals
      |> Enum.flat_map(fn {position, blocked_by} -> Enum.map(blocked_by, &{position, &1}) end)
      |> Enum.reduce({[], nesting}, fn {blocked, blocker} = edge, {kept, graph} ->
        cond do
          not is_integer(blocker) or blocker not in 1..count//1 -> {kept, graph}
          blocked == blocker -> {kept, graph}
          edge in kept -> {kept, graph}
          creates_cycle?(graph, edge) -> {kept, graph}
          true -> {[edge | kept], [edge | graph]}
        end
      end)

    Enum.reverse(kept)
  end

  @doc """
  Whether adding `{blocked, blocking}` to the given `{blocked, blocking}`
  edges would close a cycle — that is, whether the blocking node already
  (transitively) waits on the blocked one. Works on any node ids, so the
  finalise hygiene uses it on positions and Review curation on row ids.
  """
  def creates_cycle?(edges, {blocked, blocking}) do
    blocked == blocking or waits_on?(edges, blocking, blocked, MapSet.new())
  end

  # The visited set keeps the walk total even over a graph that already holds
  # a cycle — concurrent Review adds can race one past the check (accepted for
  # the MVP, like the Credit gate's race), and a walk that never terminates
  # would turn that stored oddity into a crashed Review.
  defp waits_on?(edges, from, target, visited) do
    blockers = for {^from, blocking} <- edges, blocking not in visited, do: blocking

    target in blockers or
      Enum.any?(blockers, &waits_on?(edges, &1, target, MapSet.put(visited, from)))
  end
end
