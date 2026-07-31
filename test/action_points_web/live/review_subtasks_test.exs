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
  defp open_review(conn, result \\ @nested_result, opts \\ []) do
    stub_extractor(result)

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)
    extraction = Meetings.get_extraction!(extraction.id, session_token)
    action_points = extraction.action_points

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

  # The titles the walk visits, in order — how these tests assert the ordering
  # rule without coupling to markup.
  defp walk_order(extraction) do
    extraction.id
    |> Meetings.list_action_points_in_dependency_order()
    |> Enum.map(& &1.title)
  end

  # ADR-0010: children before parents, because rejecting a parent promotes its
  # survivors irreversibly and that decision needs to know which survived.
  test "the walk decides Subtasks before their parent", %{conn: conn} do
    %{review: review, extraction: extraction, action_points: [parent, copy, _flow, _venue]} =
      open_review(conn)

    assert walk_order(extraction) == [
             "Rewrite the onboarding copy",
             "Build the new flow",
             "Revamp onboarding",
             "Book the offsite venue"
           ]

    assert has_element?(review, "##{step_id(copy)}")
    refute has_element?(review, "##{step_id(parent)}")
  end

  test "a Subtask listed before its parent is still decided first", %{conn: conn} do
    %{extraction: extraction} =
      open_review(
        conn,
        {:ok, [%{title: "Rewrite the onboarding copy", parent: 2}, %{title: "Revamp onboarding"}]}
      )

    assert walk_order(extraction) == ["Rewrite the onboarding copy", "Revamp onboarding"]
  end

  test "the step names the parent an Action Point belongs to", %{conn: conn} do
    %{review: review, action_points: [parent, copy, _flow, _venue]} = open_review(conn)

    assert has_element?(review, "##{step_id(copy)}[data-parent-id='#{parent.id}']")
  end

  test "promoting a Subtask lifts it to top level with one click", %{conn: conn} do
    %{review: review, action_points: [_parent, copy, _flow, _venue]} = open_review(conn)

    review |> element("[data-role=step] [data-role=promote]") |> render_click()

    refute has_element?(review, "##{step_id(copy)}[data-parent-id]")
    assert has_element?(review, "##{step_id(copy)}")
  end

  # ADR-0009: nesting is something the meeting did. Review can undo one the
  # model proposed (Promote), never draw one the meeting never drew.
  test "the step offers no control for nesting an Action Point", %{conn: conn} do
    %{review: review, action_points: [_parent, copy, _flow, _venue]} = open_review(conn)

    refute has_element?(review, "#action-point-#{copy.id}-parent-form")
    refute has_element?(review, "##{step_id(copy)} [data-role=parent-picker]")
  end

  test "rejecting a parent promotes its Subtasks in the Review", %{conn: conn} do
    %{review: review, extraction: extraction, action_points: [parent, copy, flow, _venue]} =
      open_review(conn, @nested_result, walk_to: 0)

    assert has_element?(review, "##{step_id(parent)}")

    review |> element("[data-role=step] [data-role=reject]") |> render_click()

    assert has_element?(review, "#review-toolbar", "1 rejected")
    assert has_element?(review, "#review-toolbar", "2 accepted")

    promoted =
      extraction.id
      |> Meetings.get_extraction!(extraction.session_token)
      |> Map.fetch!(:action_points)
      |> Enum.filter(&(&1.id in [copy.id, flow.id]))

    assert Enum.all?(promoted, &is_nil(&1.parent_id))
    assert Enum.all?(promoted, &(&1.status == :accepted))
  end

  test "a top-level Action Point offers nothing to promote", %{conn: conn} do
    %{review: review, action_points: [_parent, _copy, _flow, venue]} =
      open_review(conn, @nested_result, walk_to: 3)

    assert has_element?(review, "##{step_id(venue)}")
    refute has_element?(review, "[data-role=step] [data-role=promote]")
  end

  test "a pushed Subtask offers no Promote — its place in the sink already exists", %{conn: conn} do
    %{conn: conn, path: path, action_points: [_parent, copy, _flow, _venue]} = open_review(conn)

    Meetings.record_push!(copy, %{
      id: "issue-1",
      identifier: "ENG-1",
      url: "https://linear.app/fake/issue/ENG-1"
    })

    {:ok, review, _html} = live(conn, path)

    assert has_element?(review, "##{step_id(copy)}")
    refute has_element?(review, "[data-role=step] [data-role=promote]")
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
