# ActionPoints

Turns meeting transcripts into curated tasks in the user's project-management tool. The user supplies a transcript, reviews the extracted action points, and pushes the ones they accept.

## Language

### Pipeline

**Transcript**:
The text record of a meeting, pasted or uploaded by the user. The sole input to the product.
_Avoid_: recording, meeting (the meeting is the event; the transcript is its record)

**Extraction**:
A single run of the model over one Transcript, producing Action Points. Either succeeds or fails as a whole.
_Avoid_: processing, analysis, run

**Action Point**:
A task candidate produced by an Extraction — title, description, assignee guess, optional due date. It is a proposal, not yet real; it becomes a task only when pushed.
_Avoid_: task (reserved for what exists in the Task Sink), todo, item, suggestion

**Review**:
The step where the user curates Action Points — accepting, rejecting, and editing them — before any Push. Nothing reaches a Task Sink without passing Review.
_Avoid_: preview, confirmation

**Push**:
Sending the accepted Action Points from a Review into the user's Task Sink, creating real tasks there.
_Avoid_: sync, export, send

**Task Sink**:
A destination system that receives pushed Action Points as tasks (Linear, and later others). Each sink is a pluggable adapter behind one interface.
_Avoid_: integration, destination, provider

**Demo**:
The anonymous run of the pipeline from the landing page: a real Extraction and Review, keyed to the visitor's session instead of an account. Rate-limited rather than charged; signup is required only at Push, and the Demo's Review carries over through it.
_Avoid_: preview, free preview, trial

**Assignee Mapping**:
A remembered link from a guessed name to one Task Sink user, scoped to a Sink Connection (it dies with the connection). Born during Review the first time a name is resolved; thereafter that name resolves automatically. Push assigns only what Review resolved — nothing is matched silently at Push.
_Avoid_: user sync, alias, name matching

**Meeting Date**:
The day the meeting happened, recorded on the Extraction and stated at Review. Every relative deadline ("by Friday") resolves against it. Taken from the best evidence available — a date stated in the Transcript, then an unambiguous date in the uploaded filename — and otherwise assumed to be the visitor's own local date.
_Avoid_: date, timestamp, upload date (the upload date is only ever the assumed fallback)

**Timing Classification**:
The Extraction's report of what kind of timing language the meeting used about an Action Point's deadline — a named weekday, a stated date, "tomorrow", "soon" — never a computed date. The model classifies; the application resolves the classification against the Meeting Date into a due date, or into none — when the language pins no date ("vague"), or when a resolution rule declines because the date it would pin is not one a deliverable can have. Language naming a stretch of calendar rather than a day ("by the end of the month") resolves to the last _working day_, Monday to Friday, that the stretch contains: these are work deliverables, and a task dated to a Sunday is visibly a machine's answer. Language naming a day — a weekday, "tomorrow", "in two weeks" — is taken at its word and lands where it falls, weekend or not; the speaker chose that day, so it is not the application's to move. A date stated only in part — "the 12th", "March the 3rd" — is completed from the Meeting Date, and always forward: a meeting cannot set a deadline in its own past, so the earliest completion that is not behind the Meeting Date is the one it meant. That search runs out at the year ahead — a completion further out than that is a date no meeting meant, so it pins nothing. When none is pinned the application knows which of four reasons it was: nothing was said about timing at all, the language was vague, the classification was malformed, or a resolution rule declined the date it would have pinned. They are different facts about a meeting — "nobody mentioned when" is the meeting's, "the classification could not be read" is the Extractor's — and only the first means nothing was said. The reason is not stored on the Action Point.
_Avoid_: deadline (the language spoken in the meeting), due date (the resolved result)

**Quantifier Lexicon**:
The enumerated set of spoken quantifiers a Timing Classification may count in instead of a number, and what each one counts as. Closed — today a single entry, "a couple", counting as 2 — so that every quantifier the application decodes can be named and tested; vaguer quantifiers ("a few", "several", "some", "a while") are vague language and pin no date, because the number would be the model's invention rather than the meeting's word.
_Avoid_: number words, fuzzy durations, quantifier mapping

**Grounding Quote**:
A short verbatim excerpt from the Transcript attached to an Action Point as evidence, verified to actually appear in the Transcript. Travels with the Action Point into the Task Sink.
_Avoid_: citation, snippet, source

**Timing Quote**:
A short verbatim excerpt from the Transcript recording what was said about _when_ an Action Point is due, verified to actually appear in the Transcript. Present whenever the meeting expressed timing, with or without a resolved due date — so language that pins no date ("in a few weeks") still reaches the assignee. Shown at Review beside the due date and travelling with the Action Point into the Task Sink.
_Avoid_: deadline text, date quote, due date phrase

**Blocker**:
A blocked-by relation between two Action Points of the same Extraction, proposed by the Extraction and curated at Review; realised as a real relation in the Task Sink at Push. Curated means removed: a Blocker the Extraction got wrong can be taken off at Review, but one the meeting never stated cannot be put on there — an edge between two Action Points is the meeting's to draw, not the user's ([ADR-0009](docs/adr/0009-review-corrects-the-extraction-it-does-not-author-structure.md)). A dependency the meeting stated but the Extraction missed is added in the Task Sink. Relations to pre-existing tasks in the sink are out of scope.
_Avoid_: dependency, linked issue

**Subtask**:
An Action Point nested one level under a parent Action Point from the same Extraction — proposed only when the meeting itself broke a deliverable into pieces, never deeper than one level. Review can undo a nesting the Extraction proposed but cannot create one ([ADR-0009](docs/adr/0009-review-corrects-the-extraction-it-does-not-author-structure.md)); nesting is something the meeting did. Rejecting the parent promotes its Subtasks, and that promotion is not reversible at Review. Blockers and nesting are orthogonal.
_Avoid_: child issue, sub-issue, checklist item

### Commerce

**Credit**:
The unit of entitlement: one Credit is consumed by one successful Extraction. Failed Extractions consume nothing. Re-running the same Transcript consumes a new Credit.
_Avoid_: token, usage

**Pack**:
A one-off purchase of a fixed number of Credits. The only way to buy; there are no subscriptions.
_Avoid_: plan, subscription, tier

Wherever a Pack is being sold, its size may be given in _meetings_ — "a Pack of 15 meetings" —
because a visitor who has not yet met the product cannot price a Credit. That is the only
sanctioned use of _meeting_ as a unit, and it is scoped to the size of a Pack: the unit of
entitlement is always the Credit, so a balance, a gate, and Review all count in Credits even
when the same sentence goes on to size a Pack in meetings ("You're out of Credits — a Pack
covers your next 15 meetings"). Settled 26 July 2026 in the facelift copy pass; the
alternative, sizing a Pack in Credits everywhere, was rejected as too abstract at the point
of sale.

**Free Meeting**:
The single Credit granted to every new account so the first Extraction costs nothing.
_Avoid_: trial, free tier
