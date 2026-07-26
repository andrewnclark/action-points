# Action Points always pass human Review before Push

Extraction never writes directly to a Task Sink. Every run lands on a Review screen where the user rejects, accepts, and edits Action Points before pushing. Auto-push was rejected: the model will occasionally extract "we should probably look into that" as a task, and unfiltered output landing in someone's real Linear workspace reads as spam — a fatal first impression.

Review is load-bearing beyond safety: it is the product's face (the moment rambling speech becomes clean tasks), it doubles as the no-signup landing-page demo (same component with Push gated behind signup), and it lowers the bar for extraction quality because a human filters the output.

Do not "streamline" this away — a future one-click or fully automatic mode must remain opt-in per user, never the default.
