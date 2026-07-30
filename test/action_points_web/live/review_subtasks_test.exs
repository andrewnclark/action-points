defmodule ActionPointsWeb.ReviewSubtasksTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @transcript """
  Priya: The onboarding revamp — Alice takes the copy, Bob the new flow.
  Tom: I'll book the venue for the offsite too.
  """

  @nested_result {:ok,
                  [
                    %{title: "Revamp onboarding"},
                    %{title: "Rewrite the onboarding copy", parent: 1},
                    %{title: "Build the new flow", parent: 1},
                    %{title: "Book the offsite venue"}
                  ]}

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_extractor_result)
    end)
  end

  # Creates a succeeded Extraction owned by the conn's anonymous session and
  # opens its Review screen.
  defp open_review(conn, result \\ @nested_result) do
    stub_extractor(result)

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

  # The card's index in the rendered list — how the tests assert the
  # indented list's order without coupling to markup.
  defp rendered_index(review, action_point) do
    {index, _length} = :binary.match(render(review), ~s(id="#{dom_id(action_point)}"))
    index
  end

  test "Subtasks render indented beneath their parent, not in flat position order", %{
    conn: conn
  } do
    %{review: review, action_points: [parent, copy, flow, venue]} = open_review(conn)

    assert has_element?(review, "##{dom_id(copy)}[data-parent-id='#{parent.id}']")
    assert has_element?(review, "##{dom_id(flow)}[data-parent-id='#{parent.id}']")
    refute has_element?(review, "##{dom_id(parent)}[data-parent-id]")
    refute has_element?(review, "##{dom_id(venue)}[data-parent-id]")

    # Parent first, its Subtasks immediately beneath, the loose one last.
    assert rendered_index(review, parent) < rendered_index(review, copy)
    assert rendered_index(review, copy) < rendered_index(review, flow)
    assert rendered_index(review, flow) < rendered_index(review, venue)
  end

  test "a Subtask listed before its parent still renders beneath it", %{conn: conn} do
    %{review: review, action_points: [child, parent]} =
      open_review(
        conn,
        {:ok, [%{title: "Rewrite the onboarding copy", parent: 2}, %{title: "Revamp onboarding"}]}
      )

    assert rendered_index(review, parent) < rendered_index(review, child)
  end

  test "promoting a Subtask lifts it to top level with one click", %{conn: conn} do
    %{review: review, action_points: [_parent, copy, _flow, _venue]} = open_review(conn)

    review |> element("##{dom_id(copy)}-promote") |> render_click()

    refute has_element?(review, "##{dom_id(copy)}[data-parent-id]")
    assert has_element?(review, "##{dom_id(copy)}")
  end

  # ADR-0009: nesting is something the meeting did. Review can undo one the
  # model proposed (Promote), never draw one the meeting never drew.
  test "no card offers a control for nesting an Action Point", %{conn: conn} do
    %{review: review, action_points: action_points} = open_review(conn)

    for action_point <- action_points do
      refute has_element?(review, "#action-point-#{action_point.id}-parent-form")
      refute has_element?(review, "##{dom_id(action_point)} [data-role=parent-picker]")
    end
  end

  test "rejecting a parent promotes its Subtasks in the Review", %{conn: conn} do
    %{review: review, action_points: [parent, copy, flow, _venue]} = open_review(conn)

    review |> element("##{dom_id(parent)}-reject") |> render_click()

    assert has_element?(review, "##{dom_id(parent)}[data-status=rejected]")
    refute has_element?(review, "##{dom_id(copy)}[data-parent-id]")
    refute has_element?(review, "##{dom_id(flow)}[data-parent-id]")
    assert has_element?(review, "##{dom_id(copy)}[data-status=accepted]")
    assert has_element?(review, "##{dom_id(flow)}[data-status=accepted]")
  end

  test "a top-level card offers nothing to promote", %{conn: conn} do
    %{review: review, action_points: [parent, _copy, _flow, venue]} = open_review(conn)

    refute has_element?(review, "##{dom_id(parent)}-promote")
    refute has_element?(review, "##{dom_id(venue)}-promote")
  end

  test "a pushed Subtask offers no Promote — its place in the sink already exists", %{conn: conn} do
    %{conn: conn, path: path, action_points: [_parent, copy, flow, _venue]} = open_review(conn)

    Meetings.record_push!(copy, %{
      id: "issue-1",
      identifier: "ENG-1",
      url: "https://linear.app/fake/issue/ENG-1"
    })

    {:ok, review, _html} = live(conn, path)

    refute has_element?(review, "##{dom_id(copy)}-promote")
    assert has_element?(review, "##{dom_id(flow)}-promote")
  end

  # The indent says it. A chip repeating it only cost the metadata row its
  # alignment — see #93.
  test "a Subtask carries no chip; its position is the only marker", %{conn: conn} do
    %{review: review, action_points: [_parent, copy, _flow, _venue]} = open_review(conn)

    assert has_element?(review, "##{dom_id(copy)}[data-parent-id]")
    refute has_element?(review, "##{dom_id(copy)} [data-role=subtask]")
  end

  describe "with a connected Task Sink" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      {:ok, _connection} =
        Sinks.connect(scope, %{
          "api_key" => "lin_api_secret_key_abcd",
          "team_id" => "team-1",
          "team_name" => "Engineering"
        })

      :ok
    end

    test "a sink without the hierarchy capability is noted visibly at Review", %{conn: conn} do
      Application.put_env(:action_points, :fake_task_sink, supports_hierarchy: false)

      %{review: review} = open_review(conn)

      assert has_element?(review, "#hierarchy-unsupported-notice")
    end

    test "a hierarchy-capable sink shows no such notice", %{conn: conn} do
      %{review: review} = open_review(conn)

      refute has_element?(review, "#hierarchy-unsupported-notice")
    end

    test "a nesting-free Review never shows the notice, even on a flat sink", %{conn: conn} do
      Application.put_env(:action_points, :fake_task_sink, supports_hierarchy: false)

      %{review: review} = open_review(conn, {:ok, [%{title: "Book the offsite venue"}]})

      refute has_element?(review, "#hierarchy-unsupported-notice")
    end
  end
end
