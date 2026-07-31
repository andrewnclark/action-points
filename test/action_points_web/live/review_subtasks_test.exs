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
  defp subtask_id(action_point), do: "subtask-#{action_point.id}"

  defp reload(extraction, id) do
    extraction.id
    |> Meetings.get_extraction!(extraction.session_token)
    |> Map.fetch!(:action_points)
    |> Enum.find(&(&1.id == id))
  end

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
    %{extraction: extraction} = open_review(conn)

    assert walk_order(extraction) == [
             "Rewrite the onboarding copy",
             "Build the new flow",
             "Revamp onboarding",
             "Book the offsite venue"
           ]
  end

  test "a Subtask listed before its parent is still decided first", %{conn: conn} do
    %{extraction: extraction} =
      open_review(
        conn,
        {:ok, [%{title: "Rewrite the onboarding copy", parent: 2}, %{title: "Revamp onboarding"}]}
      )

    assert walk_order(extraction) == ["Rewrite the onboarding copy", "Revamp onboarding"]
  end

  # A family is one screen: reaching a Subtask puts the whole family on it,
  # because a Subtask cannot be judged without the thing it belongs to.
  test "reaching a Subtask puts its parent on the screen in full", %{conn: conn} do
    %{review: review, action_points: [parent, copy, flow, _venue]} = open_review(conn)

    assert has_element?(review, "##{step_id(parent)}[data-family]")
    assert has_element?(review, "##{step_id(parent)} [data-role=step-title]", parent.title)

    # The parent renders in full — both columns, its quotes, the payload we
    # would send — and not as a title in a header. Scoped to the parent's own
    # panel, or the children's columns would satisfy this on their own.
    assert has_element?(review, "[data-role=step-panel] [data-role=meeting-column]")
    assert has_element?(review, "[data-role=step-panel] [data-role=named-person]")
    assert has_element?(review, "[data-role=step-panel] [data-role=issue-column]")
    assert has_element?(review, "[data-role=step-panel] [data-role=payload-description]")

    # Its children stand beneath it, each in the compressed rendering.
    assert has_element?(review, "##{subtask_id(copy)} [data-role=subtask-title]", copy.title)
    assert has_element?(review, "##{subtask_id(flow)} [data-role=subtask-title]", flow.title)
  end

  test "each child is decidable in place, in the same layout as the parent", %{conn: conn} do
    %{review: review, extraction: extraction, action_points: [_parent, copy, flow, _venue]} =
      open_review(conn)

    # The compressed panel is the same panel: both columns and the pills.
    assert has_element?(review, "##{subtask_id(copy)} [data-role=meeting-column]")
    assert has_element?(review, "##{subtask_id(copy)} [data-role=issue-column]")
    assert has_element?(review, "##{subtask_id(copy)} [data-role=payload-description]")

    review |> element("##{subtask_id(copy)} [data-role=accept]") |> render_click()
    review |> element("##{subtask_id(flow)} [data-role=reject]") |> render_click()

    assert reload(extraction, copy.id).status == :accepted
    assert reload(extraction, flow.id).status == :rejected
  end

  # The screen's constraint, in the markup: an irreversible decision is taken
  # last, knowing what survived (ADR-0009).
  test "the parent cannot be decided while any Subtask is undecided", %{conn: conn} do
    %{review: review, action_points: [parent, copy, _flow, _venue]} = open_review(conn)

    assert has_element?(review, "##{step_id(parent)}-accept[disabled]")
    assert has_element?(review, "##{step_id(parent)}-reject[disabled]")

    assert has_element?(
             review,
             "[data-role=step-decision] [data-role=decision-locked]",
             "2 Subtasks still to decide"
           )

    review |> element("##{subtask_id(copy)} [data-role=accept]") |> render_click()

    assert has_element?(review, "##{step_id(parent)}-accept[disabled]")

    assert has_element?(
             review,
             "[data-role=step-decision] [data-role=decision-locked]",
             "1 Subtask still to decide"
           )

    assert has_element?(
             review,
             "[data-role=step-decision] [data-role=decision-locked]",
             "rejecting it would promote whatever survives to top level, and that can't be undone"
           )
  end

  test "the parent's controls unlock once every Subtask is decided", %{conn: conn} do
    %{review: review, action_points: [parent, _copy, _flow, _venue]} =
      open_review(conn, @nested_result, walk_to: 0)

    assert has_element?(review, "##{step_id(parent)}-accept")
    refute has_element?(review, "##{step_id(parent)}-accept[disabled]")
    refute has_element?(review, "[data-role=decision-locked]")
  end

  # The parent's Reject is taken knowing what survived, so the screen has to
  # say which Subtasks did — not merely record it in the database.
  test "a decided Subtask says on the screen which way it went", %{conn: conn} do
    %{review: review, action_points: [_parent, copy, flow, _venue]} = open_review(conn)

    review |> element("##{subtask_id(copy)} [data-role=accept]") |> render_click()
    review |> element("##{subtask_id(flow)} [data-role=reject]") |> render_click()

    assert has_element?(
             review,
             "##{subtask_id(copy)} [data-role=decision-made][data-decision=accepted]",
             "Accepted"
           )

    assert has_element?(
             review,
             "##{subtask_id(flow)} [data-role=decision-made][data-decision=rejected]",
             "Rejected"
           )

    # And a decision is one-way out of Undecided, as everywhere else: the
    # rejection can still be turned into an acceptance, never the reverse.
    refute has_element?(review, "##{subtask_id(copy)} [data-role=reject]")
    assert has_element?(review, "##{subtask_id(flow)} [data-role=accept]")

    review |> element("##{subtask_id(flow)} [data-role=accept]") |> render_click()

    assert has_element?(review, "##{subtask_id(flow)} [data-decision=accepted]")
  end

  # The other half of the ordering rule, which a family screen can otherwise
  # break: a sibling further down the walk may still be waiting on a Blocker.
  test "a Subtask waiting on an undecided Blocker cannot be decided yet", %{conn: conn} do
    %{review: review, extraction: extraction, action_points: [_parent, copy, flow]} =
      open_review(
        conn,
        {:ok,
         [
           %{title: "Revamp onboarding"},
           %{title: "Rewrite the onboarding copy", parent: 1},
           %{title: "Build the new flow", parent: 1, blocked_by: [2]}
         ]}
      )

    assert has_element?(review, "##{subtask_id(flow)}-accept[disabled]")

    assert has_element?(
             review,
             "##{subtask_id(flow)} [data-role=decision-locked]",
             "blocks this and hasn't been decided yet"
           )

    # Refused on the wire too, not only in the markup.
    render_click(review, "accept", %{"id" => to_string(flow.id)})
    assert reload(extraction, flow.id).status == :undecided

    review |> element("##{subtask_id(copy)} [data-role=accept]") |> render_click()

    refute has_element?(review, "##{subtask_id(flow)}-accept[disabled]")
  end

  # The disabled attribute is the screen's answer; this is the server's, for a
  # stale tab or a forged event.
  test "a decision on a locked parent is refused, not merely un-clickable", %{conn: conn} do
    %{review: review, extraction: extraction, action_points: [parent, _copy, _flow, _venue]} =
      open_review(conn)

    render_click(review, "reject", %{"id" => to_string(parent.id)})
    assert reload(extraction, parent.id).status == :undecided

    render_click(review, "accept", %{"id" => to_string(parent.id)})
    assert reload(extraction, parent.id).status == :undecided
  end

  test "rejecting the parent promotes exactly the Subtasks that survived", %{conn: conn} do
    %{review: review, extraction: extraction, action_points: [parent, copy, flow, _venue]} =
      open_review(conn)

    review |> element("##{subtask_id(copy)} [data-role=accept]") |> render_click()
    review |> element("##{subtask_id(flow)} [data-role=reject]") |> render_click()
    review |> element("[data-role=step-decision] [data-role=reject]") |> render_click()

    survivor = reload(extraction, copy.id)
    assert is_nil(survivor.parent_id)
    assert Meetings.ActionPoint.pushable?(survivor)

    # The rejected Subtask is not resurrected by the promotion: it reaches top
    # level as a rejection, which creates nothing.
    refused = reload(extraction, flow.id)
    assert refused.status == :rejected
    refute Meetings.ActionPoint.pushable?(refused)

    assert reload(extraction, parent.id).status == :rejected
    assert has_element?(review, "#review-toolbar", "1 accepted")
    assert has_element?(review, "#review-toolbar", "2 rejected")
  end

  # The counter promises Action Points, and the header above it promised a
  # number of Action Points — a family is one step and several of them.
  test "the progress counter counts Action Points decided, not steps", %{conn: conn} do
    %{review: review, action_points: [_parent, copy, _flow, _venue]} = open_review(conn)

    assert has_element?(review, "[data-role=step]", "0 of 4 decided")

    review |> element("##{subtask_id(copy)} [data-role=accept]") |> render_click()

    assert has_element?(review, "[data-role=step]", "1 of 4 decided")
  end

  test "an Action Point with no Subtasks renders as an ordinary step", %{conn: conn} do
    %{review: review, action_points: [_parent, _copy, _flow, venue]} =
      open_review(conn, @nested_result, walk_to: 3)

    assert has_element?(review, "##{step_id(venue)}")
    refute has_element?(review, "##{step_id(venue)}[data-family]")
    refute has_element?(review, "[data-role=family]")
    refute has_element?(review, "[data-role=family-subtask]")
    refute has_element?(review, "[data-role=parent-locked]")
    refute has_element?(review, "[data-role=step-decision] [data-role=accept][disabled]")
  end

  test "promoting a Subtask lifts it out of the family with one click", %{conn: conn} do
    %{review: review, extraction: extraction, action_points: [parent, copy, _flow, _venue]} =
      open_review(conn)

    review |> element("##{subtask_id(copy)} [data-role=promote]") |> render_click()

    assert is_nil(reload(extraction, copy.id).parent_id)
    refute has_element?(review, "##{subtask_id(copy)}")

    # It is now the walk's own step, decided on its own terms.
    assert has_element?(review, "##{step_id(copy)}")
    refute has_element?(review, "##{step_id(parent)}")
  end

  # ADR-0009: nesting is something the meeting did. Review can undo one the
  # model proposed (Promote), never draw one the meeting never drew.
  test "the family offers no control for nesting an Action Point", %{conn: conn} do
    %{review: review, action_points: [_parent, copy, _flow, _venue]} = open_review(conn)

    refute has_element?(review, "#action-point-#{copy.id}-parent-form")
    refute has_element?(review, "[data-role=step] [data-role=parent-picker]")
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

    assert has_element?(review, "##{subtask_id(copy)}")
    refute has_element?(review, "##{subtask_id(copy)} [data-role=promote]")
    assert has_element?(review, "##{subtask_id(copy)} [data-role=sink-issue]")
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
