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

    {:ok, review, _html} = live(conn, ~p"/review/#{extraction}")
    %{review: review, action_points: action_points}
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

  test "the parent picker nests a top-level Action Point under another", %{conn: conn} do
    %{review: review, action_points: [parent, _copy, _flow, venue]} = open_review(conn)

    review
    |> element("#action-point-#{venue.id}-parent-form")
    |> render_change(%{"parent_id" => to_string(parent.id)})

    assert has_element?(review, "##{dom_id(venue)}[data-parent-id='#{parent.id}']")
    assert rendered_index(review, parent) < rendered_index(review, venue)
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

  test "a Subtask card offers no parent picker; a pushed card offers no restructuring", %{
    conn: conn
  } do
    %{review: review, action_points: [parent, copy, _flow, _venue]} = open_review(conn)

    refute has_element?(review, "#action-point-#{copy.id}-parent-form")
    refute has_element?(review, "##{dom_id(parent)}-promote")
  end

  test "a flat Review shows no parent picker when there is nothing to nest under", %{conn: conn} do
    %{review: review, action_points: [only]} =
      open_review(conn, {:ok, [%{title: "Book the offsite venue"}]})

    refute has_element?(review, "#action-point-#{only.id}-parent-form")
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
