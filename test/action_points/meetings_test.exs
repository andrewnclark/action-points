defmodule ActionPoints.MeetingsTest do
  use ActionPoints.DataCase, async: false

  import ActionPoints.AccountsFixtures
  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Billing
  alias ActionPoints.Billing.CreditTransaction
  alias ActionPoints.Meetings

  @transcript "Priya: I'll send the Q3 report to finance by Friday."

  defp consumption_rows do
    Repo.all(from t in CreditTransaction, where: t.kind == :extraction_consumption)
  end

  defp create_action_point(session_token) do
    {:ok, extraction} =
      Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

    Meetings.run_extraction(extraction)

    Meetings.get_extraction!(extraction.id, session_token).action_points |> hd()
  end

  # A transcript with a line break mid-sentence, so the whitespace-tolerance
  # test has a real seam to cross.
  @quoted_transcript """
  Priya: I'll send the Q3 report to finance by Friday.
  Tom: Remember the auditors need the draft first,
  so the numbers must be final by Thursday.
  """

  # Runs an Extraction whose single Action Point carries the given attrs
  # extras (e.g. quotes) and returns that Action Point as stored.
  defp extract_action_point(extra_attrs) do
    attrs =
      Map.merge(
        %{title: "Send the Q3 report", description: nil, assignee_guess: nil, due_date: nil},
        extra_attrs
      )

    stub_extractor({:ok, [attrs]})

    {:ok, extraction} =
      Meetings.create_extraction(nil, "session", %{"transcript_text" => @quoted_transcript})

    Meetings.run_extraction(extraction)
    Meetings.get_extraction!(extraction.id, "session").action_points |> hd()
  end

  describe "create_extraction/4" do
    test "normalises an uploaded .vtt so cue junk never reaches the Extractor" do
      vtt = """
      WEBVTT

      1
      00:00:03.600 --> 00:00:06.240
      Priya Sharma: I'll send the Q3 report to finance by Friday.

      2
      00:00:06.900 --> 00:00:10.170
      Tom Baker: Great. I'll book the venue for the offsite.
      """

      {:ok, extraction} =
        Meetings.create_extraction(nil, "session", %{
          "transcript_text" => vtt,
          "source_format" => :vtt
        })

      refute extraction.transcript_text =~ "WEBVTT"
      refute extraction.transcript_text =~ "-->"
      assert extraction.transcript_text =~ "Priya Sharma: I'll send the Q3 report"
    end

    test "rejects an over-cap transcript before any Extraction exists" do
      over_cap = String.duplicate("word ", 25_001)

      {:error, changeset} =
        Meetings.create_extraction(nil, "session", %{"transcript_text" => over_cap})

      assert "is over the 25,000-word cap for one meeting (this transcript is about 25,001 words) — trim it and try again" in errors_on(
               changeset
             ).transcript_text

      assert Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 0
    end

    test "the cap is measured after normalisation, so timestamp junk doesn't count" do
      # ~24k words of speech wrapped in .srt cues: the raw file is far over
      # the cap counted naively, but the speech itself is under it.
      cue = fn i ->
        "#{i}\n00:0#{rem(i, 10)}:00,000 --> 00:0#{rem(i, 10)}:05,000\n" <>
          String.duplicate("word ", 24) <> "\n"
      end

      srt = Enum.map_join(1..1_000, "\n", cue)

      assert {:ok, _extraction} =
               Meetings.create_extraction(nil, "session", %{
                 "transcript_text" => srt,
                 "source_format" => :srt
               })
    end

    test "rejects a trivially short input with a helpful message" do
      {:error, changeset} =
        Meetings.create_extraction(nil, "session", %{"transcript_text" => "buy milk"})

      assert "is too short to be a meeting transcript — paste the whole thing" in errors_on(
               changeset
             ).transcript_text
    end

    test "rejects whitespace-only input as blank" do
      {:error, changeset} =
        Meetings.create_extraction(nil, "session", %{"transcript_text" => "   \n\n  "})

      assert "can't be blank" in errors_on(changeset).transcript_text
    end

    test "a signed-in user's Extraction is recorded as theirs" do
      scope = user_scope_fixture()

      {:ok, extraction} =
        Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      assert extraction.user_id == scope.user.id
    end
  end

  describe "credit consumption" do
    test "a successful authed Extraction consumes exactly one Credit, in the ledger" do
      scope = user_scope_fixture()

      {:ok, extraction} =
        Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      Meetings.run_extraction(extraction)

      assert Billing.balance(scope) == 0

      assert [%CreditTransaction{amount: -1, extraction_id: extraction_id}] = consumption_rows()
      assert extraction_id == extraction.id
    end

    test "a failed Extraction consumes nothing" do
      stub_extractor({:error, :api_unavailable})
      scope = user_scope_fixture()

      {:ok, extraction} =
        Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      Meetings.run_extraction(extraction)

      assert Billing.balance(scope) == 1
      assert consumption_rows() == []
    end

    test "a crash inside the Extractor consumes nothing" do
      stub_extractor(:crash)
      scope = user_scope_fixture()

      {:ok, extraction} =
        Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      assert_raise RuntimeError, fn -> Meetings.run_extraction(extraction) end

      assert Billing.balance(scope) == 1
      assert consumption_rows() == []
    end

    test "an anonymous Extraction consumes nothing" do
      {:ok, extraction} =
        Meetings.create_extraction(nil, "session", %{"transcript_text" => @transcript})

      Meetings.run_extraction(extraction)

      assert consumption_rows() == []
    end

    test "retrying a failed Extraction consumes only on the eventual success" do
      stub_extractor({:error, :api_unavailable})
      scope = user_scope_fixture()

      {:ok, extraction} =
        Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      Meetings.run_extraction(extraction)
      assert Billing.balance(scope) == 1

      stub_extractor(
        {:ok, [%{title: "Follow up", description: nil, assignee_guess: nil, due_date: nil}]}
      )

      extraction = Meetings.get_extraction!(extraction.id, "session")
      Meetings.run_extraction(extraction)

      assert Billing.balance(scope) == 0
      assert [%CreditTransaction{amount: -1}] = consumption_rows()
    end
  end

  describe "zero-Credit gate" do
    test "a zero-Credit user is refused before any Extraction exists" do
      scope = user_scope_fixture()

      Repo.insert!(%CreditTransaction{
        user_id: scope.user.id,
        amount: -1,
        kind: :extraction_consumption
      })

      assert {:error, :out_of_credits} =
               Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      assert Repo.aggregate(ActionPoints.Meetings.Extraction, :count) == 0
    end

    test "a zero-Credit user cannot retry a failed Extraction — a retry is an attempt too" do
      stub_extractor({:error, :api_unavailable})
      scope = user_scope_fixture()

      {:ok, extraction} =
        Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      Meetings.run_extraction(extraction)

      Repo.insert!(%CreditTransaction{
        user_id: scope.user.id,
        amount: -1,
        kind: :extraction_consumption
      })

      extraction = Meetings.get_extraction!(extraction.id, "session")

      assert {:error, :out_of_credits} = Meetings.retry_extraction(extraction)
      assert Meetings.get_extraction!(extraction.id, "session").status == :failed
    end

    test "invalid input is reported as a changeset error even at zero Credits" do
      scope = user_scope_fixture()

      Repo.insert!(%CreditTransaction{
        user_id: scope.user.id,
        amount: -1,
        kind: :extraction_consumption
      })

      assert {:error, %Ecto.Changeset{}} =
               Meetings.create_extraction(scope, "session", %{"transcript_text" => ""})
    end
  end

  describe "anonymous rate limit" do
    test "the per-session limit blocks creation over the limit" do
      override_anon_limits(session: {2, :timer.hours(1)}, ip: {1_000, :timer.hours(1)})

      assert {:ok, _} =
               Meetings.create_extraction(nil, "anon-a", %{"transcript_text" => @transcript})

      assert {:ok, _} =
               Meetings.create_extraction(nil, "anon-a", %{"transcript_text" => @transcript})

      assert {:error, :rate_limited} =
               Meetings.create_extraction(nil, "anon-a", %{"transcript_text" => @transcript})

      # A different visitor is unaffected.
      assert {:ok, _} =
               Meetings.create_extraction(nil, "anon-b", %{"transcript_text" => @transcript})
    end

    test "the per-IP limit spans different anonymous sessions" do
      override_anon_limits(session: {1_000, :timer.hours(1)}, ip: {2, :timer.hours(1)})

      ip = {203, 0, 113, 7}

      assert {:ok, _} =
               Meetings.create_extraction(nil, "anon-a", %{"transcript_text" => @transcript},
                 ip: ip
               )

      assert {:ok, _} =
               Meetings.create_extraction(nil, "anon-b", %{"transcript_text" => @transcript},
                 ip: ip
               )

      assert {:error, :rate_limited} =
               Meetings.create_extraction(nil, "anon-c", %{"transcript_text" => @transcript},
                 ip: ip
               )

      # A different address is unaffected.
      assert {:ok, _} =
               Meetings.create_extraction(nil, "anon-d", %{"transcript_text" => @transcript},
                 ip: {198, 51, 100, 9}
               )
    end

    test "signed-in users are never rate-limited (Credits are their gate)" do
      override_anon_limits(session: {1, :timer.hours(1)}, ip: {1, :timer.hours(1)})
      scope = user_scope_fixture()

      assert {:ok, _} =
               Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})

      assert {:ok, _} =
               Meetings.create_extraction(scope, "session", %{"transcript_text" => @transcript})
    end
  end

  describe "Grounding Quotes" do
    test "quotes that appear in the Transcript are stored on the Action Point" do
      action_point =
        extract_action_point(%{quotes: ["I'll send the Q3 report to finance by Friday."]})

      assert action_point.quotes == ["I'll send the Q3 report to finance by Friday."]
    end

    test "an invented quote is silently dropped and the Extraction still succeeds" do
      action_point =
        extract_action_point(%{
          quotes: [
            "We agreed to cancel the audit entirely.",
            "I'll send the Q3 report to finance by Friday."
          ]
        })

      assert action_point.quotes == ["I'll send the Q3 report to finance by Friday."]

      assert Meetings.get_extraction!(action_point.extraction_id, "session").status ==
               :succeeded
    end

    test "whitespace differences never fail verification" do
      # The quote crosses the transcript's line break with a single space.
      action_point =
        extract_action_point(%{
          quotes: ["the auditors need the draft first, so the numbers must be final"]
        })

      assert action_point.quotes == [
               "the auditors need the draft first, so the numbers must be final"
             ]
    end

    test "at most three quotes survive, whatever the Extractor returns" do
      action_point =
        extract_action_point(%{
          quotes: [
            "I'll send the Q3 report",
            "the auditors need the draft first",
            "final by Thursday.",
            "Priya: I'll send the Q3 report to finance by Friday."
          ]
        })

      assert action_point.quotes == [
               "I'll send the Q3 report",
               "the auditors need the draft first",
               "final by Thursday."
             ]
    end

    test "an Extractor result with no quotes stores an empty list" do
      assert extract_action_point(%{}).quotes == []
    end

    test "removing a quote at Review deletes exactly that quote" do
      action_point =
        extract_action_point(%{
          quotes: ["I'll send the Q3 report", "final by Thursday."]
        })

      updated = Meetings.remove_action_point_quote(action_point, 0)

      assert updated.quotes == ["final by Thursday."]
    end
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

  describe "session_review_pushable_count/1" do
    defp run_demo(session_token) do
      {:ok, extraction} =
        Meetings.create_extraction(nil, session_token, %{"transcript_text" => @transcript})

      Meetings.run_extraction(extraction)
      extraction
    end

    test "counts the Action Points waiting to Push on this session's Demo Review" do
      run_demo("visitor-session")

      assert Meetings.session_review_pushable_count("visitor-session") == 1
    end

    test "counts the most recent Review when the visitor ran the Demo twice" do
      run_demo("visitor-session")
      latest = run_demo("visitor-session")

      [action_point] = Meetings.get_extraction!(latest.id, "visitor-session").action_points
      Meetings.set_action_point_status(action_point, :rejected)

      assert Meetings.session_review_pushable_count("visitor-session") == 0
    end

    test "answers nothing for a session that never ran the Demo" do
      run_demo("visitor-session")

      refute Meetings.session_review_pushable_count("other-session")
      refute Meetings.session_review_pushable_count(nil)
    end

    test "answers nothing once the Extraction belongs to an account" do
      run_demo("visitor-session")
      Meetings.claim_session_extractions(user_fixture(), "visitor-session")

      refute Meetings.session_review_pushable_count("visitor-session")
    end

    test "answers nothing while the Extraction has not succeeded" do
      {:ok, _extraction} =
        Meetings.create_extraction(nil, "visitor-session", %{"transcript_text" => @transcript})

      refute Meetings.session_review_pushable_count("visitor-session")
    end
  end
end
