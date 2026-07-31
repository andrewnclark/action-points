defmodule ActionPoints.Sinks.DescriptionPartsTest do
  @moduledoc """
  `Sinks.description_parts/1` is the same document as `compose_description/1`,
  cut where Review needs to hang a control. The contract is that concatenating
  the parts reproduces the pushed description byte for byte — Review's whole
  claim since ADR-0010 is that what is on screen is what Push sends, and this
  is the seam that claim rests on.
  """

  use ExUnit.Case, async: true

  alias ActionPoints.Sinks

  defp action_point(attrs) do
    Map.merge(%{description: nil, quotes: [], timing_quote: nil}, Map.new(attrs))
  end

  defp concatenated(action_point) do
    action_point |> Sinks.description_parts() |> Enum.map_join("", & &1.text)
  end

  describe "the parts concatenate to the pushed description" do
    for {name, attrs} <- [
          {"prose alone", [description: "Priya will send the report."]},
          {"quotes alone", [quotes: ["I'll send it", "by Friday"]]},
          {"prose and quotes",
           [description: "Priya will send the report.", quotes: ["I'll send it"]]},
          {"a Timing Quote of its own",
           [description: "Priya will send the report.", timing_quote: "by Friday"]},
          {"a Timing Quote already inside a Grounding Quote",
           [quotes: ["I'll send it by Friday"], timing_quote: "by Friday"]},
          {"empty prose with quotes", [description: "", quotes: ["I'll send it"]]}
        ] do
      test name do
        action_point = action_point(unquote(attrs))

        assert concatenated(action_point) == Sinks.compose_description(action_point)
      end
    end
  end

  # Nothing at all is not the same document as an empty one: a task created
  # with no description is different from one created with a blank body.
  test "an Action Point with neither prose nor quotes has no parts and no description" do
    action_point = action_point([])

    assert Sinks.description_parts(action_point) == []
    assert Sinks.compose_description(action_point) == nil
  end

  # The index is what the removal control sends back, so it has to be the
  # position in `quotes` that `remove_action_point_quote/2` deletes from.
  test "only Grounding Quotes carry an index, and it is their position in quotes" do
    parts =
      Sinks.description_parts(
        action_point(
          description: "Priya will send the report.",
          quotes: ["first quote", "second quote"],
          timing_quote: "by Friday"
        )
      )

    indexed = for part <- parts, part.quote_index, do: {part.quote_index, part.text}

    assert [{0, first}, {1, second}] = indexed
    assert first =~ "first quote"
    assert second =~ "second quote"

    timing = Enum.find(parts, &(&1.text =~ "by Friday"))
    assert timing.quote_index == nil
  end
end
