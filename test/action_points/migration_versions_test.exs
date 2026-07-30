defmodule ActionPoints.MigrationVersionsTest do
  use ExUnit.Case, async: true

  # Ecto records applied migrations by version prefix alone, so two files
  # sharing one version means the second is silently skipped — fresh
  # databases then miss a table. Two parallel agents produced exactly this
  # once (both generated 20260730090000); this makes the union suite say so.
  test "no two migration files share a version" do
    versions =
      Path.wildcard(Path.join([File.cwd!(), "priv", "repo", "migrations", "*.exs"]))
      |> Enum.map(fn path -> path |> Path.basename() |> String.split("_", parts: 2) |> hd() end)

    duplicates = versions -- Enum.uniq(versions)

    assert duplicates == [],
           "duplicate migration versions #{inspect(duplicates)} — ecto will silently skip one file; renumber it (see docs/agents/lifecycle.md)"
  end
end
