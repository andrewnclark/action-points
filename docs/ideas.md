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
