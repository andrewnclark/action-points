defmodule ActionPoints.Meetings.SampleMeeting do
  @moduledoc """
  The sample meeting: a fictional Transcript and the Extraction result that
  goes with it, both authored here rather than sampled from the model.

  The sample exists to show the product working, and a live run shows only
  whatever the model felt like that day — an Extraction with no Blockers, no
  nesting and four clean dates demonstrates none of the things that make
  Review worth having. So the result is written down: every state the Review
  screen can show is on the page at once, every visitor sees the same one, and
  a curious visitor costs neither a model call nor a Credit (issue #94).

  This is the one demo surface we can honestly author. A pasted Transcript is
  the visitor's own words about their own colleagues and we can promise
  nothing about it; the sample meeting is our fiction end to end.

  The result speaks the `ActionPoints.Meetings.Extractor` port's own shape, so
  it goes through the same finalising as a real Extraction: the quotes below
  are verified against the Transcript like any others, the Blockers and the
  nesting are sanitised, and the due dates are `Timing`'s arithmetic over the
  classifications rather than dates typed in here. A sample that bypassed that
  path could demonstrate a product that does not exist.

  ## Dates

  The classifications resolve against a Meeting Date `days_ago/0` behind the
  visitor's own date. That is the one thing about the sample that is not
  frozen — and it has to move, because a frozen Meeting Date would either sit
  months in the past (with every due date already gone, so the past-due flag
  says nothing) or drift into a future the fiction cannot survive being read
  in. The Extraction itself — its words, its structure, its timing language —
  is identical on every visit.

  What the anchor guarantees is *at least* one Action Point already past due:
  "today", said three days ago, is three days gone whatever day it is read on.
  How many others join it moves with the weekday, because a weekday
  classification counts forward from the meeting rather than from the reader —
  a sample read on a Friday has its Thursday deadline behind it too. That is
  the product being honest about a real meeting three days old, so it is left
  alone; what is fixed is that the flag is never absent.
  """

  @days_ago 3

  @transcript """
  Maya: Right, launch check-in — quick one. Dan, where's the landing page?
  Dan: Close. I'll have the whole page shipped by the end of next week. The pricing table is the piece still missing, and I'll have that finished by Thursday.
  Maya: Nothing goes live until legal have signed off the updated terms, mind.
  Dan: I've emailed Sofia in legal already. I'll get a yes or no out of her by Friday.
  Maya: Good — the landing page waits on that answer either way.
  Priya: Onboarding emails are drafted. I'll send the final versions over for sign-off in a week.
  Maya: Please do.
  Priya: One more thing: the signup form still breaks on Safari.
  Jonas: That one's mine. I'm out for a bit, so I'll have a fix in a couple of weeks.
  Priya: And Dan can't close out the pricing table until somebody settles the Pack price.
  Maya: That's me. I'll pin the Pack price down today and drop the number in the doc.
  Maya: We still need the launch announcement drafted, and I'm not going to pick a name for it here — it wants writing in the next few weeks, that's all I'll say.
  Maya: I'll book the go/no-go call for Monday morning. Anything else? No? Thanks all.
  """

  @doc """
  How far behind the visitor's own date the sample meeting happened. Far
  enough that something said "today" in it is now overdue, close enough that
  the meeting still reads as this week's.
  """
  def days_ago, do: @days_ago

  @doc """
  The sample Transcript — a plausible product-team check-in, and the haystack
  every quote below is verified against.
  """
  def transcript, do: @transcript

  @doc """
  The authored Extraction result, in the Extractor port's own shape.

  Between them these eight Action Points put the whole Review screen on one
  page: two Blockers (one of them on an Action Point that also has a Subtask),
  a nested pair, a Timing Quote that resolves to a date and one that resolves
  to nothing, a due date already past, an Action Point the meeting named
  nobody for, and four different names for the assignee slot to work on.
  """
  def result do
    %{
      meeting_date: nil,
      action_points: [
        %{
          title: "Ship the launch landing page",
          description:
            "Dan owns the page end to end; it goes live once legal have cleared the terms.",
          assignee_guess: "Dan",
          timing: %{kind: :span_end, modifier: :next, unit: :week},
          timing_quote: "by the end of next week",
          quotes: [
            "I'll have the whole page shipped by the end of next week.",
            "the landing page waits on that answer either way"
          ],
          blocked_by: [3],
          parent: nil
        },
        %{
          title: "Finish the pricing table",
          description: "The last piece of the landing page, waiting on the Pack price.",
          assignee_guess: "Dan",
          timing: %{kind: :weekday, weekday: :thursday, modifier: nil},
          timing_quote: "I'll have that finished by Thursday",
          quotes: [
            "The pricing table is the piece still missing, and I'll have that finished by Thursday."
          ],
          blocked_by: [6],
          parent: 1
        },
        %{
          title: "Get legal's yes or no on the updated terms",
          description: "Dan is chasing Sofia in legal for a decision either way.",
          assignee_guess: "Dan",
          timing: %{kind: :weekday, weekday: :friday, modifier: nil},
          timing_quote: "by Friday",
          quotes: ["I'll get a yes or no out of her by Friday."],
          blocked_by: [],
          parent: nil
        },
        %{
          title: "Send the final onboarding emails for sign-off",
          description: "Priya has them drafted and sends the final versions to Maya.",
          assignee_guess: "Priya",
          timing: %{kind: :duration, unit: :week, count: 1},
          timing_quote: "in a week",
          quotes: ["I'll send the final versions over for sign-off in a week."],
          blocked_by: [],
          parent: nil
        },
        %{
          title: "Fix the signup form on Safari",
          description: "Jonas picks it up when he is back from leave.",
          assignee_guess: "Jonas",
          timing: %{kind: :duration, unit: :week, count: :couple},
          timing_quote: "I'll have a fix in a couple of weeks",
          quotes: [
            "the signup form still breaks on Safari",
            "I'll have a fix in a couple of weeks"
          ],
          blocked_by: [],
          parent: nil
        },
        %{
          title: "Pin down the Pack price",
          description:
            "Maya settles the number and puts it in the doc, unblocking the pricing table.",
          assignee_guess: "Maya",
          timing: %{kind: :relative_day, offset: 0},
          timing_quote: "I'll pin the Pack price down today",
          quotes: ["I'll pin the Pack price down today and drop the number in the doc."],
          blocked_by: [],
          parent: nil
        },
        %{
          title: "Draft the launch announcement",
          description: "The meeting agreed it needs writing but named nobody to write it.",
          assignee_guess: nil,
          timing: %{kind: :vague},
          timing_quote: "it wants writing in the next few weeks",
          quotes: ["We still need the launch announcement drafted"],
          blocked_by: [],
          parent: nil
        },
        %{
          title: "Book the go/no-go call",
          description: "Maya sends the invite round for Monday morning.",
          assignee_guess: "Maya",
          timing: %{kind: :weekday, weekday: :monday, modifier: nil},
          timing_quote: "for Monday morning",
          quotes: ["I'll book the go/no-go call for Monday morning."],
          blocked_by: [],
          parent: nil
        }
      ]
    }
  end
end
