defmodule ActionPoints.Meetings.SampleMeetingTest do
  @moduledoc """
  The sample meeting is authored, so what it demonstrates is a promise rather
  than a hope: these tests are that promise written down. They assert the
  states the Review screen must show a visitor who has never seen the product
  — and that showing them costs no model call and no Credit.
  """

  use ActionPoints.DataCase, async: false

  import ActionPoints.AccountsFixtures
  import ActionPoints.ExtractionHelpers

  alias ActionPoints.Accounts.Scope
  alias ActionPoints.Billing
  alias ActionPoints.Meetings
  alias ActionPoints.Meetings.ActionPoint
  alias ActionPoints.Meetings.Blocker
  alias ActionPoints.Meetings.SampleMeeting
  alias ActionPoints.Repo

  defp create_sample(opts \\ []) do
    extraction =
      Meetings.create_sample_extraction(
        opts[:scope],
        opts[:session_token] || "sample-session",
        local_date: opts[:local_date]
      )

    Meetings.get_extraction!(extraction.id, extraction.session_token)
  end

  describe "the sample Extraction" do
    test "succeeds without ever calling the Extractor" do
      # The double raises on any call, so a model call here would fail the test
      # rather than pass silently.
      stub_extractor(:crash)

      extraction = create_sample()

      assert extraction.status == :succeeded
      assert extraction.sample
      assert extraction.transcript_text == String.trim(SampleMeeting.transcript())
      assert length(extraction.action_points) == 8
    end

    test "is identical on every visit, bar the anchor its dates are counted from" do
      first = create_sample(session_token: "one", local_date: ~D[2026-04-15])
      second = create_sample(session_token: "two", local_date: ~D[2026-04-15])

      assert Enum.map(first.action_points, &summarise/1) ==
               Enum.map(second.action_points, &summarise/1)
    end

    test "consumes no Credit, even for a signed-in visitor" do
      user = user_fixture()
      scope = Scope.for_user(user)
      before = Billing.balance(scope)

      create_sample(scope: scope)

      assert Billing.balance(scope) == before
    end

    test "is anchored a few days behind the visitor's own date" do
      extraction = create_sample(local_date: ~D[2026-04-15])

      assert extraction.meeting_date == Date.add(~D[2026-04-15], -SampleMeeting.days_ago())
      assert extraction.meeting_date_source == :assumed
    end
  end

  describe "the states the sample puts on the Review screen" do
    setup do
      %{extraction: create_sample(local_date: ~D[2026-04-15])}
    end

    test "two Blockers, one of them on an Action Point that also has a Subtask", %{
      extraction: extraction
    } do
      blocked = Enum.filter(extraction.action_points, &(&1.blockers != []))

      assert length(Repo.all(Blocker)) >= 2
      assert length(blocked) >= 2

      parent_ids = MapSet.new(extraction.action_points, & &1.parent_id)
      assert Enum.any?(blocked, &MapSet.member?(parent_ids, &1.id))
    end

    test "a nested pair", %{extraction: extraction} do
      assert [subtask] = Enum.filter(extraction.action_points, & &1.parent_id)
      assert Enum.any?(extraction.action_points, &(&1.id == subtask.parent_id))
    end

    test "a Timing Quote beside a resolved date, and one standing on its own", %{
      extraction: extraction
    } do
      quoted = Enum.filter(extraction.action_points, & &1.timing_quote)

      assert Enum.any?(quoted, & &1.due_date)
      assert Enum.any?(quoted, &is_nil(&1.due_date))
    end

    # Whatever day the sample is read on: "today", said three days ago, is
    # three days gone. How many others are past due moves with the weekday —
    # that is a real meeting behaving realistically — but the past-due flag is
    # never absent from the sample, which is the state it is there to show.
    test "a due date that has already passed, whatever day the sample is read on" do
      for offset <- 0..6 do
        today = Date.add(~D[2026-04-13], offset)
        extraction = create_sample(session_token: "day-#{offset}", local_date: today)

        assert Enum.any?(extraction.action_points, fn action_point ->
                 action_point.due_date && Date.before?(action_point.due_date, today)
               end),
               "nothing is past due for a visitor arriving on #{today}"
      end
    end

    test "an Action Point the meeting named nobody for, among a spread of names", %{
      extraction: extraction
    } do
      names = Enum.map(extraction.action_points, & &1.assignee_guess)

      assert nil in names
      assert names |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length() >= 3
    end

    test "every authored quote is really in the Transcript", %{extraction: extraction} do
      authored = SampleMeeting.result().action_points

      Enum.zip(authored, extraction.action_points)
      |> Enum.each(fn {authored, stored} ->
        assert length(stored.quotes) == length(authored.quotes),
               "a Grounding Quote on #{stored.title} does not appear in the sample Transcript"

        assert stored.timing_quote,
               "the Timing Quote on #{stored.title} does not appear in the sample Transcript"
      end)
    end

    test "every authored timing classification resolves as intended", %{extraction: extraction} do
      # The one deliberate exception is the vague classification, which pins no
      # date on purpose — its Timing Quote is the whole signal.
      assert Enum.count(extraction.action_points, &is_nil(&1.due_date)) == 1
    end
  end

  defp summarise(%ActionPoint{} = action_point) do
    Map.take(action_point, [
      :position,
      :title,
      :description,
      :assignee_guess,
      :quotes,
      :timing_quote
    ])
  end
end
