defmodule ActionPoints.MeetingsTest do
  use ActionPoints.DataCase, async: false

  alias ActionPoints.Meetings

  @transcript "Priya: I'll send the Q3 report to finance by Friday."

  defp create_action_point(session_token) do
    {:ok, extraction} =
      Meetings.create_extraction(session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)

    Meetings.get_extraction!(extraction.id, session_token).action_points |> hd()
  end

  describe "get_action_point!/2" do
    test "returns the Action Point for the owning session" do
      action_point = create_action_point("owner-session")

      assert Meetings.get_action_point!(action_point.id, "owner-session").id == action_point.id
    end

    test "raises for any other session, so no one curates another visitor's Review" do
      action_point = create_action_point("owner-session")

      assert_raise Ecto.NoResultsError, fn ->
        Meetings.get_action_point!(action_point.id, "other-session")
      end
    end
  end
end
