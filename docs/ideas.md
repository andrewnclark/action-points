# Ideas parking lot

Raw ideas awaiting a proper grilling session before they become issues.
Captured as prompts, not designs — nothing here is committed roadmap.

## User sync

Sync the Linear workspace's users to the ActionPoints account, so pushed
tasks land on the right people rather than relying on per-Push best-effort
name matching (today: unambiguous full-name or first-name match, else
unassigned).

Questions to grill:

- What does "sync" buy over the current per-Push `list_users` call — a
  stored mapping the user can correct? Speaker-name → Linear-user mapping
  learned per account?
- Where does the user curate the mapping — Review screen, sink settings?
- Does this stay behind the Task Sink port (ADR-0002) when a second sink
  arrives with its own user model?

## The working week as a user setting

Today "working day" is Monday to Friday, hard-coded, and it only ever
bites on a span end ("by the end of the month" never lands on a Sunday).
Let the user say which days they work, so a Sunday–Thursday week, or a
four-day week, resolves span ends onto a day that person actually works.

Questions to grill:

- Does it change the Timing Classification, or only the resolution? The
  claim to test: only resolution. "End of the week" is the same spoken
  language whoever hears it, so the prompt stays static and stays
  cacheable (ADR-0008, and #28's "the extraction prompt is not given the
  current date, the meeting date, or a time"). If that holds, this never
  touches the prompt or the evaluation fixtures.
- Does the setting change what "the week" *is*, as well as which of its
  days are working ones? A Sunday–Thursday worker saying "next week"
  probably does not mean the week beginning Monday.
- Where does it live — the account? Then what does the Demo use, where
  there is no account, and does a signup at Push re-resolve dates the
  visitor already reviewed under the default?
- Is a per-Extraction override needed, or is one setting per account
  right? The meeting's own working week may not be the user's.
- Is the cheapest honest version a no-op — leave Monday to Friday, and
  spend the build elsewhere until someone outside it actually asks?

## Blocking issues

Let pushed issues carry blocked-by / blocking relations — either between
Action Points from the same meeting, or against existing issues in the
sink.

Questions to grill:

- Can an Extraction even detect dependencies reliably, or is this a
  Review-screen curation affordance?
- Linear supports issue relations; is this expressible through the
  TaskSink behaviour without leaking Linear specifics?
- Does the MVP need it, or is it post-launch (spec is deliberately
  transcript → tasks, one meeting at a time)?
