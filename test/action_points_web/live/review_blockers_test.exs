defmodule ActionPointsWeb.ReviewBlockersTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @transcript """
  Priya: I'll migrate the database this week.
  Tom: Then I can deploy the new service once that's done.
  Sam: And I'll write up the runbook, separately.
  """

  # Deploy waits on the migration; the runbook is free-standing.
  @extractor_result [
    %{title: "Migrate the database"},
    %{title: "Deploy the new service", blocked_by: [1]},
    %{title: "Write the runbook"}
  ]

  setup do
    on_exit(fn -> Application.delete_env(:action_points, :fake_task_sink) end)
  end

  # Creates a succeeded Extraction owned by the conn's anonymous session and
  # opens its Review screen (the same pattern as ReviewCurationTest).
  defp open_review(conn, result \\ @extractor_result) do
    stub_extractor({:ok, result})

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    action_points = Meetings.get_extraction!(extraction.id, session_token).action_points

    path = ~p"/review/#{extraction}"
    {:ok, review, _html} = live(conn, path)
    %{review: review, conn: conn, path: path, action_points: action_points}
  end

  defp dom_id(action_point), do: "action_points-#{action_point.id}"
  defp chip(action_point), do: "##{dom_id(action_point)} [data-role=blocker]"
  defp picker_form(action_point), do: "#action-point-#{action_point.id}-blocker-form"
  defp picker(action_point), do: "#action-point-#{action_point.id}-blocker-picker"

  defp add_blocker(review, action_point, blocked_by) do
    review
    |> element(picker_form(action_point))
    |> render_change(%{"blocked_by_id" => to_string(blocked_by.id)})
  end

  test "a proposed relation renders as a blocked-by chip on the blocked Action Point", %{
    conn: conn
  } do
    %{review: review, action_points: [first, second, third]} = open_review(conn)

    assert has_element?(review, chip(second), "Migrate the database")
    refute has_element?(review, chip(first))
    refute has_element?(review, chip(third))

    # The capability note is for connected sinks that lack it — not the Demo.
    refute has_element?(review, "#relations-unsupported-notice")
  end

  test "removing a relation costs one click and survives a reload", %{conn: conn} do
    %{review: review, conn: conn, path: path, action_points: [_first, second, _third]} =
      open_review(conn)

    [blocker] = second.blockers
    review |> element("##{dom_id(second)}-blocker-#{blocker.id}-remove") |> render_click()

    refute has_element?(review, chip(second))

    {:ok, reloaded, _html} = live(conn, path)
    refute has_element?(reloaded, chip(second))
  end

  test "a relation can be added between any two of the Extraction's Action Points", %{
    conn: conn
  } do
    %{review: review, conn: conn, path: path, action_points: [first, _second, third]} =
      open_review(conn)

    add_blocker(review, third, first)

    assert has_element?(review, chip(third), "Migrate the database")

    {:ok, reloaded, _html} = live(conn, path)
    assert has_element?(reloaded, chip(third), "Migrate the database")
  end

  test "the picker offers neither the Action Point itself, its blockers, nor rejected ones", %{
    conn: conn
  } do
    %{review: review, action_points: [first, second, third]} = open_review(conn)

    refute has_element?(review, "#{picker(second)} option[value='#{second.id}']")
    refute has_element?(review, "#{picker(second)} option[value='#{first.id}']")
    assert has_element?(review, "#{picker(second)} option[value='#{third.id}']")

    review |> element("##{dom_id(third)}-reject") |> render_click()

    refute has_element?(review, "#{picker(second)} option[value='#{third.id}']")
  end

  test "rejecting an Action Point removes the chips pointing at it", %{conn: conn} do
    %{review: review, action_points: [first, second, _third]} = open_review(conn)

    review |> element("##{dom_id(first)}-reject") |> render_click()

    refute has_element?(review, chip(second))
  end

  test "an addition that would close a circle is refused with an explanation", %{conn: conn} do
    %{review: review, action_points: [first, second, _third]} = open_review(conn)

    # Deploy already waits on the migration; the reverse would be a circle.
    add_blocker(review, first, second)

    refute has_element?(review, chip(first))
    assert has_element?(review, "#flash-error", "block each other in a circle")
  end

  describe "the relation capability note" do
    setup :register_and_log_in_user

    defp connect_sink(scope) do
      {:ok, _connection} =
        Sinks.connect(scope, %{
          "api_key" => "lin_api_secret_key_abcd",
          "team_id" => "team-1",
          "team_name" => "Engineering"
        })

      :ok
    end

    test "a connected sink without the capability is called out at Review", %{
      conn: conn,
      scope: scope
    } do
      Application.put_env(:action_points, :task_sink, Sinks.FakeFlatTaskSink)

      on_exit(fn ->
        Application.put_env(:action_points, :task_sink, Sinks.FakeTaskSink)
      end)

      connect_sink(scope)

      %{review: review} = open_review(conn)

      assert has_element?(review, "#relations-unsupported-notice")
    end

    test "a sink with the capability gets no such note", %{conn: conn, scope: scope} do
      connect_sink(scope)

      %{review: review} = open_review(conn)

      refute has_element?(review, "#relations-unsupported-notice")
    end

    test "a Review with no Blockers has nothing to note", %{conn: conn, scope: scope} do
      Application.put_env(:action_points, :task_sink, Sinks.FakeFlatTaskSink)

      on_exit(fn ->
        Application.put_env(:action_points, :task_sink, Sinks.FakeTaskSink)
      end)

      connect_sink(scope)

      %{review: review} = open_review(conn, [%{title: "Migrate the database"}])

      refute has_element?(review, "#relations-unsupported-notice")
    end
  end
end
