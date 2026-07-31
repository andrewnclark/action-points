# Review is a dependency-ordered walk, not a list

Review presents one Action Point at a time, in an order derived from the relations the Extraction proposed, and requires an explicit decision on each before moving on. The walk ends on a summary that holds the set, its relations, and the Push. The list of stacked cards is replaced, not improved.

## Why the list could not be made to work

The card was asked to carry, at one weight and in one wrapping row, six things of four different kinds: facts from the meeting, values the application derived, edges to other Action Points, and controls. Every attempt to fix it — and there were several, across #88 and #93 — moved the same objects into a different arrangement of the same space. #93 helped materially by deleting two pickers, and the remaining problems survived it, which is the evidence that the problem was the container.

Three things the list could never do:

**It could not show what we send.** The description on a card is the model's prose. The description we push is that prose plus a `### From the meeting` section carrying the Grounding Quotes and the Timing Quote, composed at Push and never stored (`Sinks.compose_description/1`). Review therefore previewed a document that does not exist and hid the one that does. Rendering the real thing costs about ten lines per card, which twenty cards cannot afford and one screen can.

**It could not hold the two-sided model.** An assignee is two facts — the **Named Person** the meeting said, and the **Sink Member** they are in the workspace. So is a deadline: the Timing Quote is what was said, the due date is what we resolved it to. Two columns of comparable weight need width. On a card they became a compressed chip row; given a screen they become the shape of the thing.

**It could not make anyone decide.** Every Action Point arrived `:accepted` by default under a Push button, so eight tasks could be created in a colleague's workspace having been read by nobody. That is not a layout defect and no layout could have fixed it.

## The order

One rule, applied in both directions: **decide the dependencies first, and make the consequential decision last, when you know the most.**

**Blockers before the blocked.** The blocked Action Point's relation depends on the blocker existing, so the blocker is decided first. By the time the blocked one appears, its Blocker line is no longer a dangling reference to something offscreen — it is a statement about a decision already made: *"you accepted it, so this will be created blocked by it"*, or *"you rejected it, so this will be created unblocked"*.

**Children before parents.** Rejecting a parent promotes its surviving Subtasks, and that promotion is not reversible at Review (ADR-0009). An irreversible decision must be taken with the most information available, which means knowing which children survived. The parent is therefore visible throughout — a Subtask cannot be judged without knowing what it is part of — but is not decidable until its children are.

Because those two point in opposite directions through the graph, it is worth saying plainly that they are one rule and not two. A Blocker is a dependency of the thing it blocks. A Subtask is a dependency of its parent's decision. Both are decided from the leaves inward.

The order exists at all only because the graph is acyclic by construction: `Blocker.creates_cycle?/2` drops any edge that would close a cycle at finalise, so a topological order is always available and the walk can never deadlock. Ties break on `position`, which is the meeting's own order.

**A family is one screen**, not several. Nesting is never deeper than one level, so a family is bounded. The parent is shown in full — description, quotes, both columns — with its children below it and its own controls disabled until they are decided. The constraint is a property of the screen rather than a sentence printed on it.

## The decision, and what it commits

Accept and Reject are the only ways forward; nothing may be skipped. **Accept commits what is on the screen at that moment** — there is no separate save, and no state in which a change has been made but not committed.

This requires `status` to gain `:undecided` as its default. Without it, "accepted" cannot be distinguished from "not yet looked at", and strict decision is meaningless. Three things follow at no extra cost:

- `pushable?/1` already tests `status == :accepted`, so an undecided Action Point is not pushable and **a half-finished walk cannot Push anything nobody decided**. The safety property arrives with the enum, not with a new guard.
- The summary's counts describe decisions rather than defaults.
- The walk's position becomes derivable: *the first Action Point in dependency order that has not been decided*.

## No session state

The walk keeps nothing. There is no GenServer, no progress record, and nothing in the LiveView's assigns that matters after a disconnect. Position is a query over data that is already written, because every Accept and Reject already writes a row.

A process holding walk progress would be **less** durable than the database it duplicates — it dies with a deploy or a crash, which is precisely the case it would have been added to survive — and it would be a second source of truth able to disagree with the rows. Closing the tab, crashing, deploying, or coming back the next day all land on the same step, because the step is a consequence of the data rather than a memory of it.

## The two sides become an interaction rule

The layout claim — the meeting on the left, the workspace on the right — is enforced by what can be touched:

> **Nothing in the left column can be changed. The right column is the issue we will create.**

The left is a record. It cannot be wrong, because it is not a claim about the workspace; only the mapping can be wrong. This retires the free-text assignee field, which allowed the Named Person to be rewritten and, since the guess is also the Assignee Mapping key, silently re-keyed any mapping born from it.

Today the changeable part of the right column is the pills — the Sink Member and the due date — plus the existing removal of a quote. The title and description are right-column things that are **not yet** editable; that is a knowingly incomplete rule rather than a broken one, and a later ticket making them editable completes this design rather than extending it. Quotes remain removable and never editable: an edited quote is not evidence.

Edit disappears entirely. Its three fields have homes — due date and assignee are pills, title and description are deferred — and with it goes a third rendering of an Action Point that had to be kept in step with the other two.

## Consequences

- **Review is slower, deliberately.** Eight forced decisions cost more than one Push button. That is the point; the friction is answered at the summary, where the remainder can be accepted having been seen, not by weakening the walk.
- **The summary is load-bearing.** Push acts on a set, Blockers are edges only visible between Action Points, and the overdue warning is a property of the set. All three live there. The compact two-column card designed for the old list survives as the summary row, which is the one place density is right.
- **The Demo and the real app converge**, which was #88's original argument. The anonymous state differs by exactly one pill: the due date still resolves without a sink and the payload still previews, so only the Sink Member has nothing to say. It becomes an invitation to connect, and the harder ask waits for the summary, where the visitor has seen the whole set.
- **The relation preview is deferred.** The step shows a Blocker as the decision it depends on, not as the sink-side relation it will become. `blocks ACT-109` was prototyped and dropped; it needs identifiers that do not exist until Push.
- **This ADR assumes the current authentication and billing model** and is not blocked on changing either. Where the paywall sits (#102) and whether sign-in becomes an OAuth flow (#103) both alter the summary's call to action and nothing else.
- **Future controls get a second test**, alongside ADR-0009's. Not only *does this correct something we extracted rather than create something new*, but also *which column does it belong to* — because one of them is a record and cannot be touched.
