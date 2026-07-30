# The model classifies timing; the application resolves dates

Due dates used to be the model's to compute: the prompt asked for an ISO date and told it to "resolve relative dates against the transcript's context if possible, otherwise leave null". In practice the headline case — "have it ready for review by Wednesday" — produced no due date at all, because weekday-relative calendar arithmetic is exactly what a language model is unreliable at. We split the job along what each side is good at: the Extractor reports a Timing Classification — a tagged union naming the kind of timing language it heard (`absolute`, `weekday`, `relative_day`, `span_end`, `duration`, `vague`) and its parts, never a computed date — and `ActionPoints.Meetings.Timing`, a pure module with no repo, clock, or API dependency, resolves the classification against the Meeting Date when the Extraction finalises.

The boundary is structural, not asked for in prose: `vague` has nowhere to put a date, so the model cannot emit one for "soon" even if it wanted to. And because classification is anchor-independent — "next Wednesday" is the same classification whenever it was said — the prompt is given no current date, meeting date, time, or timezone.

## Consequences

- Every resolution rule is deterministic, unit-tested, and fixable in code without touching the prompt; new timing rules land in `Timing`, never as prompt prose asking the model to do arithmetic.
- The prompt stays static: cacheable, and evaluation fixtures give the same classification regardless of when they are run.
- The resolved due date is an ordinary due date from birth — stored on the Action Point, edited or cleared at Review, pushed to the Task Sink exactly as a hand-entered one.
- The union landed whole, but only `weekday`, `relative_day`, and complete `absolute` dates resolve so far; `span_end`, `duration`, and partial dates resolve to nothing until their tickets land the rules.
