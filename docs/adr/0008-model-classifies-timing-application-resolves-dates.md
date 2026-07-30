# The model classifies timing; the application resolves dates

Due dates used to be the model's to compute: the prompt asked for an ISO date and told it to "resolve relative dates against the transcript's context if possible, otherwise leave null". In practice the headline case — "have it ready for review by Wednesday" — produced no due date at all, because weekday-relative calendar arithmetic is exactly what a language model is unreliable at. We split the job along what each side is good at: the Extractor reports a Timing Classification — a tagged union naming the kind of timing language it heard (`absolute`, `weekday`, `relative_day`, `span_end`, `duration`, `vague`) and its parts, never a computed date — and `ActionPoints.Meetings.Timing`, a pure module with no repo, clock, or API dependency, resolves the classification against the Meeting Date when the Extraction finalises.

The boundary is structural, not asked for in prose: `vague` has nowhere to put a date, so the model cannot emit one for "soon" even if it wanted to. And because classification is anchor-independent — "next Wednesday" is the same classification whenever it was said — the prompt is given no current date, meeting date, time, or timezone.

## Consequences

- Every resolution rule is deterministic, unit-tested, and fixable in code without touching the prompt; new timing rules land in `Timing`, never as prompt prose asking the model to do arithmetic.
- The prompt stays static: cacheable, and evaluation fixtures give the same classification regardless of when they are run.
- The resolved due date is an ordinary due date from birth — stored on the Action Point, edited or cleared at Review, pushed to the Task Sink exactly as a hand-entered one.
- The union landed whole, but the rules arrive ticket by ticket: `weekday`, `relative_day`, complete `absolute` dates, `span_end` and `duration` resolve so far; partial dates resolve to nothing until their ticket lands.
- A resolution rule may decline. `span_end` resolves to the last *working* day of the span, and when a weekend meeting sits past its own span's last working day there is no such day to give, so it pins nothing rather than a date behind the meeting that set it.
- Weekend meetings get two different answers from `span_end`, and the difference is deliberate: "this week" reinterprets to the working week ahead, because Saturday and Sunday sit at a week's boundary and belong ambiguously to either side of it, while "this month" and "this quarter" decline, because a weekend day sits squarely inside the month whose work is simply finished. Said on Saturday 31 October, "end of the week" is 6 November and "end of the month" is nothing at all.
