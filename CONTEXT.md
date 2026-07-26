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

### Commerce

**Credit**:
The unit of entitlement: one Credit is consumed by one successful Extraction. Failed Extractions consume nothing. Re-running the same Transcript consumes a new Credit.
_Avoid_: token, usage

**Pack**:
A one-off purchase of a fixed number of Credits. The only way to buy; there are no subscriptions.
_Avoid_: plan, subscription, tier

**Free Meeting**:
The single Credit granted to every new account so the first Extraction costs nothing.
_Avoid_: trial, free tier
