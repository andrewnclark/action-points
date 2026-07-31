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
  defp open_review(conn, result \\ @extractor_result, opts \\ []) do
    stub_extractor({:ok, result})

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    extraction = Meetings.get_extraction!(extraction.id, session_token)
    action_points = extraction.action_points

    # A Blocker is decided before the Action Point it blocks, so a test about
    # the blocked one has to walk there — which is the whole point of the
    # order: by the time it shows, its Blocker line is a decision already made.
    case Keyword.get(opts, :walk_to) do
      nil -> :ok
      index -> walk_to(extraction.id, Enum.at(action_points, index))
    end

    path = ~p"/review/#{extraction}"
    {:ok, review, _html} = live(conn, path)

    %{
      review: review,
      conn: conn,
      path: path,
      extraction: extraction,
      action_points: action_points
    }
  end

  defp step_id(action_point), do: "step-#{action_point.id}"
  defp chip(action_point), do: "##{step_id(action_point)} [data-role=blocker]"

  test "the blocked Action Point states the relation, and the blocker never does", %{conn: conn} do
    %{review: review, action_points: [first, second, _third]} = open_review(conn)

    # The walk opens on the Blocker itself, which carries no relation of its own.
    assert has_element?(review, "##{step_id(first)}")
    refute has_element?(review, chip(first))

    # The capability note is for connected sinks that lack it — not the Demo.
    refute has_element?(review, "#relations-unsupported-notice")

    review |> element("[data-role=step] [data-role=accept]") |> render_click()

    assert has_element?(review, "##{step_id(second)}")
    assert has_element?(review, chip(second), "Migrate the database")
  end

  test "a free-standing Action Point carries no relation", %{conn: conn} do
    %{review: review, action_points: [_first, _second, third]} =
      open_review(conn, @extractor_result, walk_to: 2)

    assert has_element?(review, "##{step_id(third)}")
    refute has_element?(review, chip(third))
  end

  test "removing a relation costs one click and survives a reload", %{conn: conn} do
    %{review: review, conn: conn, path: path, action_points: [_first, second, _third]} =
      open_review(conn, @extractor_result, walk_to: 1)

    [blocker] = second.blockers
    review |> element("#blocker-#{blocker.id}-remove") |> render_click()

    refute has_element?(review, chip(second))

    {:ok, reloaded, _html} = live(conn, path)
    refute has_element?(reloaded, chip(second))
  end

  # ADR-0009: a relation is an edge the meeting either drew or did not. Review
  # can take one away; it cannot put one there.
  test "the step offers no control for authoring a relation", %{conn: conn} do
    %{review: review, action_points: [first, _second, _third]} = open_review(conn)

    refute has_element?(review, "#action-point-#{first.id}-blocker-form")
    refute has_element?(review, "##{step_id(first)} [data-role=blocker-picker]")
  end

  test "rejecting an Action Point removes the relations pointing at it", %{conn: conn} do
    %{review: review, action_points: [_first, second, _third]} = open_review(conn)

    review |> element("[data-role=step] [data-role=reject]") |> render_click()

    assert has_element?(review, "##{step_id(second)}")
    refute has_element?(review, chip(second))
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
