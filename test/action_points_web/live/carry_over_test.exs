defmodule ActionPointsWeb.CarryOverTest do
  use ActionPointsWeb.ConnCase, async: false

  import ActionPoints.ExtractionHelpers
  import Phoenix.LiveViewTest

  alias ActionPoints.Accounts
  alias ActionPoints.AccountsFixtures
  alias ActionPoints.Meetings
  alias ActionPoints.Repo
  alias ActionPoints.Sinks

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
      Application.delete_env(:action_points, :fake_task_sink_pushes)
    end)

    :ok
  end

  # Runs the anonymous Demo on the given conn: paste → Review, Extraction
  # succeeded. Returns the conn (carrying the anonymous session cookie),
  # the Review path, and the Extraction id.
  defp run_anonymous_demo(conn) do
    stub_extractor(@extractor_result)

    conn = get(conn, ~p"/")
    {:ok, home, _html} = live(conn)

    result =
      home
      |> form("#transcript-form", extraction: %{transcript_text: @transcript})
      |> render_submit()

    {:ok, review, _html} = follow_redirect(result, conn)

    eventually(fn ->
      assert has_element?(review, "#action-points li", "Send the Q3 report to finance")
    end)

    {:error, {:live_redirect, %{to: review_path}}} = result
    "/review/" <> extraction_id = review_path
    %{conn: conn, review: review, review_path: review_path, extraction_id: extraction_id}
  end

  # Registers through the real registration screen on the same conn, then logs
  # in through the magic-link controller action — the request whose session
  # renewal must not lose the anonymous Review.
  defp sign_up_and_log_in(conn, email) do
    {:ok, registration, _html} = live(conn, ~p"/users/register")

    registration
    |> form("#registration_form", user: %{email: email})
    |> render_submit()

    user = Accounts.get_user_by_email(email)
    {token, _hashed} = AccountsFixtures.generate_user_magic_link_token(user)

    {user, post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})}
  end

  test "anonymous Review survives signup and can then be Pushed without re-running",
       %{conn: conn} do
    %{conn: conn, review: review, review_path: review_path, extraction_id: extraction_id} =
      run_anonymous_demo(conn)

    # Curate before signing up — this Review state must carry over too.
    [_kept, rejected] =
      Meetings.get_extraction!(extraction_id, get_session(conn, :anon_session_token)).action_points

    review |> element("#action_points-#{rejected.id}-reject") |> render_click()

    # Anonymous Push is the signup gate.
    review |> element("#push-button") |> render_click()
    assert_redirect(review, ~p"/users/register")

    {user, conn} = sign_up_and_log_in(conn, "carryover@example.com")

    # Login lands straight back on the carried-over Review.
    assert redirected_to(conn) == review_path

    # The Extraction now belongs to the account.
    assert Repo.get!(Meetings.Extraction, extraction_id).user_id == user.id

    # Push works on the very same Extraction — no re-run.
    {:ok, _connection} =
      Sinks.connect(Accounts.Scope.for_user(user), %{
        "api_key" => "lin_api_secret_key_abcd",
        "team_id" => "team-1",
        "team_name" => "Engineering"
      })

    conn = get(conn, review_path)
    {:ok, review, _html} = live(conn)

    # The pre-signup rejection carried over: only the kept Action Point pushes.
    assert has_element?(review, "#push-button", "Push 1 Action Point")

    review |> element("#push-button") |> render_click()
    render_async(review)

    assert has_element?(review, "#push-confirmation a", "ENG-1")
    assert [{"team-1", task}] = Application.get_env(:action_points, :fake_task_sink_pushes, [])
    assert task.title == "Send the Q3 report to finance"
    assert Repo.aggregate(Meetings.Extraction, :count) == 1
  end

  test "the signup screens say the Review is being kept", %{conn: conn} do
    %{conn: conn, review: review} = run_anonymous_demo(conn)

    review |> element("#push-button") |> render_click()
    assert_redirect(review, ~p"/users/register")

    # The promise the Push button made is restated by the page it lands on,
    # counting what is actually waiting.
    {:ok, registration, _html} = live(conn, ~p"/users/register")
    assert has_element?(registration, "#review-kept", "2 Action Points")

    registration
    |> form("#registration_form", user: %{email: "waiting@example.com"})
    |> render_submit()

    # And again on the last click of the signup — the magic link's landing page.
    user = Accounts.get_user_by_email("waiting@example.com")
    {token, _hashed} = AccountsFixtures.generate_user_magic_link_token(user)

    {:ok, confirmation, _html} = live(conn, ~p"/users/log-in/#{token}")
    assert has_element?(confirmation, "#review-kept")
  end

  test "a Review with everything rejected is kept without promising a Push", %{conn: conn} do
    %{conn: conn, review: review, extraction_id: extraction_id} = run_anonymous_demo(conn)

    for action_point <-
          Meetings.get_extraction!(extraction_id, get_session(conn, :anon_session_token)).action_points do
      review |> element("#action_points-#{action_point.id}-reject") |> render_click()
    end

    {:ok, registration, html} = live(conn, ~p"/users/register")

    assert has_element?(registration, "#review-kept")
    refute html =~ "Create an account to Push"
  end

  test "the signup screens say nothing about a Review when there is none", %{conn: conn} do
    {:ok, registration, _html} = live(conn, ~p"/users/register")

    refute has_element?(registration, "#review-kept")
  end

  test "logging in without a Demo Extraction keeps the normal redirect", %{conn: conn} do
    conn = get(conn, ~p"/")
    {_user, conn} = sign_up_and_log_in(conn, "no-demo@example.com")

    assert redirected_to(conn) == ~p"/"
  end

  test "another account's Extraction is not claimed at login", %{conn: conn} do
    %{conn: conn, extraction_id: extraction_id} = run_anonymous_demo(conn)

    # A different user already owns an Extraction under an unrelated token —
    # it must be untouched by this login.
    other_user = AccountsFixtures.user_fixture()

    {:ok, other_extraction} =
      Meetings.create_extraction(
        Accounts.Scope.for_user(other_user),
        "someone-elses-session",
        %{"transcript_text" => @transcript}
      )

    {user, _conn} = sign_up_and_log_in(conn, "claims@example.com")

    assert Repo.get!(Meetings.Extraction, extraction_id).user_id == user.id
    assert Repo.get!(Meetings.Extraction, other_extraction.id).user_id == other_user.id
  end
end
