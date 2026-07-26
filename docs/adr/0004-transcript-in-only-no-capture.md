# Input is transcripts only — we do not capture meetings

The product accepts an existing transcript (paste, or `.txt`/`.vtt`/`.srt` upload) and deliberately does no transcription or meeting capture. Zoom cloud recording, Teams, and Google Meet (Workspace) already export transcripts, so for most target users capture would rebuild — worse — something they already have.

The capture ladder was examined and consciously deferred, not overlooked:

- **Audio file upload + speech-to-text** (serves free-tier users who only have local recordings): cheapest credible option (~5–30p per meeting-hour via Whisper/Deepgram-class APIs); first thing to add after launch, priced at 2 Credits per audio meeting to protect margin. Diarization-capable providers preferred, since speaker labels improve assignee guessing.
- **Meeting bots** (Fireflies/Otter style): build is weeks of fragile, ToS-grey headless-browser work; renting (e.g. Recall.ai) charges per meeting-hour and destroys margin at current pack pricing. Roadmap only, and only if people pay.
- **Caption-scraping browser extension** (Tactiq style): separate codebase, store review takes days, breaks when the captions UI changes. Roadmap only.

## Consequences

- Capture, if it comes, bolts onto the front of the pipeline; Extraction and everything downstream are unaffected. That is why cutting it was cheap.
- Long-term, capture (not extraction, which is commoditised) is the likely moat — this ADR defers it, it does not reject it.
