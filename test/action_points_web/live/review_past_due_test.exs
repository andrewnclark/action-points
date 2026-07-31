defmodule ActionPointsWeb.ReviewPastDueTest do
  @moduledoc """
  A resolved due date that has already passed is flagged at Review, against
  the visitor's own today — never against the Meeting Date, and never taken
  from it. The flag informs; it never clears the date and never blocks a Push.
  """

  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Meetings
  alias ActionPoints.Sinks

  @transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Great. I'll book the venue for the offsite, no rush on that one.
  """

  setup do
    on_exit(fn ->
      Application.delete_env(:action_points, :fake_task_sink)
      Application.delete_env(:action_points, :fake_task_sink_pushes)
    end)

    :ok
  end

  # Creates a succeeded Extraction whose Action Points carry the given stated
  # dates (one Action Point per `due_date`), anchored to the given Meeting
  # Date, and opens its Review as a visitor whose browser reports `local_date`.
  defp open_review(conn, opts) do
    meeting_date = Keyword.fetch!(opts, :meeting_date)
    due_dates = Keyword.get(opts, :due_dates, [Keyword.get(opts, :due_date)])

    stub_extractor(
      {:ok,
       %{
         meeting_date: meeting_date,
         action_points:
           for {due_date, index} <- Enum.with_index(due_dates, 1) do
             %{
               title: "Send the Q#{index} report to finance",
               description: "Priya committed to sending the Q#{index} report to finance.",
               assignee_guess: "Priya",
               timing: timing_for(due_date)
             }
           end
       }}
    )

    conn = get(conn, ~p"/")
    session_token = Plug.Conn.get_session(conn, :anon_session_token)

    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)

    # The past-due flag is a property of an accepted Action Point, and since
    # ADR-0010 nothing arrives accepted — so these tests state the acceptance
    # they stand on, which also walks the Review to its end. An undecided
    # Action Point is unflagged for the same reason a rejected one is: it is
    # not going anywhere. `decided: false` is for the tests about the step
    # itself, where the date is corrected before Accept commits it.
    action_points = extraction_action_points(extraction, session_token)

    [action_point | _] =
      action_points =
      if Keyword.get(opts, :decided, true),
        do: accept_action_points(action_points),
        else: action_points

    # The connect params must be put on the conn that actually opens the
    # Review: `live/2` with a path recycles the conn, dropping them.
    conn = get(conn, ~p"/review/#{extraction}")

    conn =
      case Keyword.fetch(opts, :local_date) do
        {:ok, local_date} -> put_connect_params(conn, %{"local_date" => to_string(local_date)})
        :error -> conn
      end

    {:ok, review, _html} = live(conn)

    %{
      review: review,
      action_point: action_point,
      action_points: action_points,
      session_token: session_token,
      conn: conn
    }
  end

  defp extraction_action_points(extraction, session_token) do
    Meetings.get_extraction!(extraction.id, session_token).action_points
  end

  defp timing_for(nil), do: nil

  defp timing_for(%Date{} = date),
    do: %{kind: :absolute, year: date.year, month: date.month, day: date.day}

  # A decided Action Point's row, which is where a flag is readable: the walk
  # only flags what a Push would act on, and nothing is accepted until it has
  # been decided.
  defp row_id(action_point), do: "decided-#{action_point.id}"
  defp step_id(action_point), do: "step-#{action_point.id}"

  defp flagged?(review, action_point) do
    has_element?(review, "##{row_id(action_point)} [data-role=due-date][data-past-due]")
  end

  defp due_date_chip(review, action_point) do
    review |> element("##{row_id(action_point)} [data-role=due-date]") |> render()
  end

  describe "the flag" do
    test "a resolved due date earlier than today is flagged, and says so in words",
         %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-07-24],
          local_date: ~D[2026-07-30]
        )

      assert flagged?(review, action_point)
      assert due_date_chip(review, action_point) =~ "already passed"
      # The date itself is still shown — flagging is not hiding.
      assert due_date_chip(review, action_point) =~ "24 Jul 2026"
    end

    test "a due date today is not flagged", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-07-30],
          local_date: ~D[2026-07-30]
        )

      refute flagged?(review, action_point)
      assert due_date_chip(review, action_point) =~ "30 Jul 2026"
    end

    test "a due date later than today is not flagged", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-08-14],
          local_date: ~D[2026-07-30]
        )

      refute flagged?(review, action_point)
    end

    test "an Action Point with no due date is not flagged", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn, meeting_date: ~D[2026-07-20], local_date: ~D[2026-07-30])

      refute flagged?(review, action_point)
      assert has_element?(review, "##{row_id(action_point)} [data-role=no-due-date]")
    end
  end

  describe "what today means" do
    test "the comparison is against today, not against the meeting date", %{conn: conn} do
      # Comfortably after a three-week-old meeting, and still behind today:
      # unremarkable from the meeting's point of view, overdue from the
      # visitor's — and it is the visitor's that matters.
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: ~D[2026-07-06],
          due_date: ~D[2026-07-17],
          local_date: ~D[2026-07-30]
        )

      assert flagged?(review, action_point)
    end

    test "a date in the future is unflagged however old the meeting is", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: ~D[2026-05-04],
          due_date: ~D[2026-08-31],
          local_date: ~D[2026-07-30]
        )

      refute flagged?(review, action_point)
    end

    test "today is the visitor's local date, not the server's", %{conn: conn} do
      # The server's own date would leave this untouched; the visitor's
      # calendar, days ahead, is what flags it.
      due_date = Date.add(Date.utc_today(), 3)

      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: Date.utc_today(),
          due_date: due_date,
          local_date: Date.add(Date.utc_today(), 10)
        )

      assert flagged?(review, action_point)
    end

    test "without connect params, today falls back to the server's date", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: Date.add(Date.utc_today(), -10),
          due_date: Date.add(Date.utc_today(), -1)
        )

      assert flagged?(review, action_point)
    end

    test "the server's own today is not flagged when connect params are absent", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: Date.add(Date.utc_today(), -10),
          due_date: Date.utc_today()
        )

      refute flagged?(review, action_point)
    end

    test "a browser date that isn't a date falls back to the server's own", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: Date.add(Date.utc_today(), -10),
          due_date: Date.add(Date.utc_today(), -1),
          local_date: "sometime today"
        )

      assert flagged?(review, action_point)
    end
  end

  describe "the notice above the cards" do
    test "says why a passed deadline matters when one is accepted", %{conn: conn} do
      %{review: review} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-07-24],
          local_date: ~D[2026-07-30]
        )

      assert has_element?(review, "#past-due-notice", "already passed")
    end

    test "is absent when nothing accepted is past due", %{conn: conn} do
      %{review: review} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-08-14],
          local_date: ~D[2026-07-30]
        )

      refute has_element?(review, "#past-due-notice")
    end

    test "counts the passed deadlines it is warning about", %{conn: conn} do
      %{review: review} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_dates: [~D[2026-07-24], ~D[2026-07-27], ~D[2026-08-14]],
          local_date: ~D[2026-07-30]
        )

      assert has_element?(review, "#past-due-notice", "2 accepted Action Points have due dates")
      assert has_element?(review, "#past-due-notice", "Change or clear the dates")
    end

    # Rejecting is a step control, and by the time a flag can appear the step
    # has been left behind — returning to a decided one is #108's. The rule
    # under test is the flag's, so the decision is made through the context
    # and the Review re-read.
    test "goes once the flagged Action Point is rejected, and so does the flag", %{conn: conn} do
      %{action_point: action_point, session_token: session_token, conn: conn} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-07-24],
          local_date: ~D[2026-07-30]
        )

      Meetings.set_action_point_status(action_point, :rejected)
      {:ok, review, _html} = live(conn)

      refute has_element?(review, "#past-due-notice")
      # A rejected Action Point creates nothing, so there is nothing to warn
      # about — the date is still shown, just no longer flagged.
      refute flagged?(review, action_point)
      assert due_date_chip(review, action_point) =~ "24 Jul 2026"
      assert Meetings.get_action_point!(action_point.id, session_token).due_date == ~D[2026-07-24]
    end
  end

  # A date the meeting got wrong is corrected at its own step, before Accept
  # commits it — which is what deleting Edit had to leave intact.
  describe "the user decides" do
    test "a due date is changed from its pill, and the corrected date is unflagged",
         %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-07-24],
          local_date: ~D[2026-07-30],
          decided: false
        )

      assert has_element?(review, "##{step_id(action_point)} [data-role=due-date]", "24 Jul 2026")

      review
      |> form("#action-point-#{action_point.id}-due-date-form", %{"due_date" => "2026-08-14"})
      |> render_change()

      review |> element("[data-role=step] [data-role=accept]") |> render_click()

      refute flagged?(review, action_point)
      assert due_date_chip(review, action_point) =~ "14 Aug 2026"
      refute has_element?(review, "#past-due-notice")
    end

    test "a due date is cleared from its pill, with no Edit to do it in",
         %{conn: conn} do
      %{review: review, action_point: action_point, session_token: session_token} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-07-24],
          local_date: ~D[2026-07-30],
          decided: false
        )

      review |> element("#action-point-#{action_point.id}-due-date-clear") |> render_click()
      review |> element("[data-role=step] [data-role=accept]") |> render_click()

      refute flagged?(review, action_point)
      assert has_element?(review, "##{row_id(action_point)} [data-role=no-due-date]")
      assert Meetings.get_action_point!(action_point.id, session_token).due_date == nil
    end
  end

  describe "the Push" do
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

    test "a flagged due date does not block the Push, and pushes as it stands", %{conn: conn} do
      %{review: review, action_point: action_point} =
        open_review(conn,
          meeting_date: ~D[2026-07-20],
          due_date: ~D[2026-07-24],
          local_date: ~D[2026-07-30]
        )

      assert flagged?(review, action_point)
      refute review |> element("#push-button") |> render() =~ "disabled"

      review |> element("#push-button") |> render_click()
      render_async(review)

      assert has_element?(review, "#push-confirmation", "ENG-1")

      assert [{"team-1", task}] = Application.get_env(:action_points, :fake_task_sink_pushes, [])
      assert task.due_date == ~D[2026-07-24]

      # Once the task exists in the sink the warning has nothing left to
      # prevent, so the flag and its notice stand down.
      refute flagged?(review, action_point)
      refute has_element?(review, "#past-due-notice")
    end
  end
end
