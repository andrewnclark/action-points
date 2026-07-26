# Task Sinks are pluggable; Linear ships first, via personal API key

All destinations sit behind a single Elixir behaviour (a `TaskSink`: roughly `validate_credentials/1` and `push_tasks/2`), so Trello, GitHub Issues, etc. can be added later without touching the pipeline. Linear is the only implementation at launch: one GraphQL endpoint, personal API keys as a first-class feature, and an audience likely to pay for workflow tooling. Slack was rejected outright — it is a notification surface, not a task manager.

Users connect by pasting a personal API key rather than OAuth. OAuth is the right eventual answer but costs app registration, callback handling, and token refresh — non-demo work the launch-night early adopter doesn't need.

## Considered Options

- Multiple integrations at launch — rejected: one done well beats three half-wired, and "for teams who run their meetings into Linear" is crisper positioning.
- OAuth from day one — rejected for launch; revisit when the audience is less tolerant of pasting API keys.
