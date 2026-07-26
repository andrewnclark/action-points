defmodule ActionPointsWeb.PushTest do
  use ActionPointsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @api_key "lin_api_secret_key_abcd"

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  @extractor_result {:ok,
                     [
                       %{
                         title: "Send the Q3 report to finance",
                         description: "Priya committed to sending the Q3 report to finance.",
                         assignee_guess: "Priya",
                         due_date: ~D[2026-07-31]
                       },
                       %{
                         title: "Book the offsite venue",
                         description: "Tom will book the venue for the offsite.",
                         assignee_guess: "Tom",
                         due_date: nil
                       }
                     ]}

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_task_sink_pushes)
      Application.delete_env(:action_points, :fake_extractor_result)
    end)

    :ok
  end

  # Creates a succeeded Extraction owned by the conn's anonymous session and
  # opens its Review screen.
  defp open_review(conn) do
    Application.put_env(:action_points, :fake_extractor_result, @extractor_result)

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

  defp connect_sink(scope) do
    {:ok, _connection} =
      Sinks.connect(scope, %{
        "api_key" => @api_key,
        "team_id" => "team-1",
        "team_name" => "Engineering"
      })
  end

  defp push(review) do
    review |> element("#push-button") |> render_click()
    render_async(review)
  end

  describe "anonymous visitor" do
    test "the Push button reads as the signup gate", %{conn: conn} do
      %{review: review} = open_review(conn)

      assert has_element?(review, "#push-button", "Sign up to Push")
    end

    test "clicking Push routes to signup, keeping the Review", %{conn: conn} do
      %{review: review} = open_review(conn)

      review |> element("#push-button") |> render_click()

      assert_redirect(review, ~p"/users/register")
    end
  end

  describe "signed-in user without a sink connection" do
    setup :register_and_log_in_user

    test "clicking Push routes to sink settings", %{conn: conn} do
      %{review: review} = open_review(conn)

      review |> element("#push-button") |> render_click()

      assert_redirect(review, ~p"/settings/sink")
    end
  end

  describe "connected user" do
    setup :register_and_log_in_user

    setup %{scope: scope} do
      connect_sink(scope)
      :ok
    end

    test "Push creates the issues and the confirmation lists links to them", %{conn: conn} do
      %{review: review} = open_review(conn)

      push(review)

      assert has_element?(
               review,
               ~s{#push-confirmation a[href="https://linear.app/fake/issue/ENG-1"]},
               "ENG-1"
             )

      assert has_element?(
               review,
               ~s{#push-confirmation a[href="https://linear.app/fake/issue/ENG-2"]},
               "ENG-2"
             )

      assert [{"team-1", _first}, {"team-1", _second}] =
               Application.get_env(:action_points, :fake_task_sink_pushes, [])
    end

    test "pushed cards link to their issue and are no longer editable", %{conn: conn} do
      %{review: review, action_points: [first, _second]} = open_review(conn)

      push(review)

      assert has_element?(
               review,
               ~s{#action_points-#{first.id} a[data-role=sink-issue]},
               "ENG-1"
             )

      refute has_element?(review, "#action_points-#{first.id}-edit")
      refute has_element?(review, "#action_points-#{first.id}-reject")
      refute has_element?(review, "#push-button")
    end

    test "a mid-Push failure reports the split and retry creates only the missing ones", %{
      conn: conn
    } do
      Application.put_env(:action_points, :fake_task_sink, push: [:ok, {:error, :unavailable}])

      %{review: review} = open_review(conn)

      push(review)

      assert has_element?(review, "#push-failure", "1 created")
      assert has_element?(review, "#push-failure", "1 not created")
      assert has_element?(review, "#push-button", "Push 1")

      push(review)

      refute has_element?(review, "#push-failure")
      assert has_element?(review, "#push-confirmation a", "ENG-1")
      assert has_element?(review, "#push-confirmation a", "ENG-2")

      # Two sink tasks in total — the created one was never re-pushed.
      assert [_first, _second] = Application.get_env(:action_points, :fake_task_sink_pushes, [])
    end

    test "a Push that creates nothing says so instead of reporting a split", %{conn: conn} do
      Application.put_env(:action_points, :fake_task_sink,
        push: [{:error, :unavailable}, {:error, :unavailable}]
      )

      %{review: review} = open_review(conn)

      push(review)

      # "Stopped partway" is a claim about a Push that got somewhere. This one
      # never created a task, and saying otherwise makes the reader hunt Linear
      # for a task that isn't there.
      assert has_element?(review, "#push-failure", "nothing was created")
      refute has_element?(review, "#push-failure", "stopped partway")
      assert has_element?(review, "#push-button", "Push 2")
    end

    test "reloading after a Push keeps the confirmation and issue links", %{conn: conn} do
      %{review: review, conn: conn, path: path} = open_review(conn)

      push(review)

      {:ok, reloaded, _html} = live(conn, path)

      assert has_element?(reloaded, "#push-confirmation a", "ENG-1")
      assert has_element?(reloaded, "#action-points a[data-role=sink-issue]", "ENG-2")
      refute has_element?(reloaded, "#push-button")
    end
  end
end
