# Assignment resolves at Review; Push does no matching

Assignee resolution used to happen silently at Push time — a best-effort name match against the sink's user list, invisible to the user and, in practice, broken (Linear handles like `@clark.andrew` never match a guessed "Andrew", so issues landed unassigned every time with no trace of why). We moved resolution to Review: each guessed name resolves through a stored Assignee Mapping or a visible suggestion, the user sees exactly who will be assigned before pushing, and picking a user saves the mapping for good. Push sends the sink user id that Review resolved and performs no matching of its own.

The trade-off is deliberate: silent matching was convenient when it worked, but unaccountable when it didn't. Review is already the product's curation moment (ADR-0005), so the resolution belongs on screen there — what you saw in Review is exactly what the Task Sink gets, in both directions. A wrong suggestion the user never looked at can still be pushed; that is the same residual risk as before, minus the invisibility.

## Consequences

- Assignee Mappings are scoped to the Sink Connection and cascade-delete with it — sink user ids are meaningless outside their workspace, so reconnecting starts the mappings from zero by design.
- The sink's member list is always fetched live (the picker never goes stale and nobody enters users by hand); only confirmed mappings are stored.
- Do not reintroduce matching at Push "for robustness" — an Action Point with no resolved sink user id pushes unassigned, visibly, full stop.
