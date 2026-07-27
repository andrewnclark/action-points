# Competitor scan: who else turns meetings into tasks, and what do they charge?

Research for [#43](https://github.com/andrewnclark/action-points/issues/43) (part of the #41 map). Searches and vendor pages read 2026-07-27; primary sources only (vendors' own pricing/feature pages, Linear's official integrations directory). Prices as listed on vendor sites — most are USD per user/month.

## Question

Who competes with ActionPoints (meeting transcript → tasks, especially into Linear), what do they charge, and is the curated-Review positioning actually differentiated?

## Comparison table

| Vendor | Capture model | Tasks into Linear? | Cheapest tier with Linear | Free tier covers transcript→Linear? | Accepts pasted/uploaded transcript? | Human review before task creation? |
|---|---|---|---|---|---|---|
| **Fireflies.ai** | Bot joins calls; audio/video upload on all tiers | Yes — "automatically syncs… action items from Fireflies meetings into Linear" | Pro, **$10/u/mo annual** ($18 monthly) — integrations are Pro+ | No — Free has unlimited transcription + 400 min storage but integrations locked | Audio/video upload yes; pasted text transcript no | No — auto-creates |
| **Otter.ai** | Bot; file imports | **No Linear integration** (Salesforce, HubSpot, Zapier only); action items stay in-app | n/a | No | 3 lifetime file imports free; 10/mo on Pro ($8.33/u/mo annual) | n/a |
| **Fellow** | Bot recordings | Yes — Linear among Team-tier PM integrations | Team, **$7/u/mo annual** ($11 monthly) | No — Free is 5 AI notes + 5 recordings *lifetime* | No paste; recording-centric | Action items editable in notes, but no approve-before-push gate |
| **Circleback** | Bot (audio upload secondary) | Yes — "Automatically create issues from meetings", plus agentic Linear search/update | Individual, **$20.83/u/mo** (Team $25) | No free tier — trial only | Not surfaced as a workflow | No — "automatically captured, assigned, and organized" |
| **tl;dv** | Bot recorder | Yes — syncs to Linear via paid integrations | Pro, ~**$18/u/mo monthly** (Business ~$59; page is JS-only, prices corroborated via tl;dv's own help center + third parties) | No — Free = unlimited recordings/transcripts but ~10 AI notes/mo and no integrations | No paste | No — auto-sync |
| **Granola** | Desktop app captures system audio (no bot) | **No native Linear** — Business ($14/u/mo) gets Zapier/MCP/API | n/a natively | No | No — lives off live meeting audio | Notes are editable, but no task-push product |
| **Spinach AI** | Bot | Yes — auto-creates Jira/Linear tickets | Pro, **$2.90/meeting-hour**, or Business **$19/u/mo annual** ($29 monthly); pricing page JS-only, corroborated across multiple secondary sources | Unverified — one secondary source claims free Starter includes ticket creation; not confirmable on a primary page | No paste | No — auto-creates |
| **Tactiq** | **Chrome extension reads captions; meeting-file upload** — no bot | Yes — "Automatically create detailed Linear issues from meeting transcripts" (AI Workflow) | Team, **£11.67/u/mo annual** (GBP-localised pricing page; Free/Pro £5.83/Business £21.75 tiers) | No — Free = 10 transcripts + 5 AI credits/mo, workflows are Team+ | File upload yes; paste not offered | No — workflow is automatic |
| **Also in Linear's directory** | Read.ai, Sembly, TeamRetro all list official Linear integrations for meeting action items | — | — | — | — | All auto-create |
| **ActionPoints** (this product) | **Paste or upload .txt/.vtt/.srt** — never joins calls | Yes — Push after Review | **£5 for 15 Extractions** (~£0.33/meeting), 1 free credit, no subscription | — | **Yes — it's the whole input model** | **Yes — the Review screen is the product** |

Linear itself has no native meeting/transcript ingestion; meetings enter Linear only through these third-party integrations. Its directory pages (linear.app/integrations/{fireflies-ai, fellow, tactiq, …}) are how the category is found.

Sources: [Fireflies pricing](https://fireflies.ai/pricing) · [Otter pricing](https://otter.ai/pricing) · [Fellow pricing](https://fellow.ai/pricing/) · [Circleback](https://circleback.ai/) + [pricing](https://circleback.ai/pricing) · [tl;dv help center](https://intercom.help/tldv/en/articles/6082483-what-is-tl-dv-s-pricing) · [Granola pricing](https://www.granola.ai/pricing) · [Spinach pricing](https://www.spinach.ai/pricing) · [Tactiq pricing](https://www.tactiq.io/pricing) · [Linear × Fireflies](https://linear.app/integrations/fireflies-ai) · [Linear × Tactiq](https://linear.app/integrations/tactiq)

## Differentiation verdict

**The curated-Review positioning is real.** Every incumbent that reaches Linear does it *automatically* — Fireflies, Tactiq, Circleback, Spinach, and Read.ai all describe the flow as auto-create/auto-sync, and none of their marketing or docs surfaces an approve-each-task gate. The closest thing anywhere is post-hoc editing of notes (Fellow, Granola). Nobody sells "a human curates AI-proposed tasks before they hit your tracker" as the product.

**The input model is equally differentiated.** No surveyed vendor accepts a *pasted* transcript. Their capture models are call bots (Fireflies, Otter, Fellow, Circleback, tl;dv, Spinach), a caption-reading extension (Tactiq), or desktop audio (Granola). Several take audio/video *file* uploads, but text-transcript-in is unserved — which also means ActionPoints works for meetings the user didn't attend, transcripts from any source, and users who refuse bots in their calls.

**The price shape is the third wedge.** Incumbents are per-seat subscriptions ($7–$25/u/mo to unlock Linear). ActionPoints' £5/15 credits (~£0.33 per meeting) undercuts every one of them for occasional use, and only Spinach's $2.90/meeting-hour Pro even shares the consumption-pricing shape.

**Caveat:** each wedge is feature-sized. Any incumbent could add a "review before push" toggle or a paste box in a sprint. The defensible version of the position is the *combination* — paste-anything input + curation-as-the-product + no subscription — moved fast and named clearly, not any single piece.

## SEO landscape

Sweep run 2026-07-27 across the query families the map's distribution assumption depends on.

### Contested — do not fight head-on

Every natural phrasing containing both "meeting" and "Linear" is owned by incumbent money pages:

- **"meeting action items to Linear"** — Read.ai help docs, fellow.ai and Fellow help-center, linear.app/integrations/fellow, Spinach blog (twice), linear.app/integrations/fireflies-ai, linear.app/integrations/teamretro.
- **"AI meeting notes Linear integration"** — wall-to-wall purpose-built landing pages: fellow.ai, fireflies.ai, linear.app/integrations/fireflies-ai, Tactiq help docs, sembly.ai/automations/linear, plus a meetingnotes.com listicle ("15 Best AI Tools That Integrate With Linear").
- **"turn meeting notes into Linear issues"** — Tactiq (help doc + programmatic workflow page), fellow.ai, fireflies.ai, three linear.app/integrations slots, Spinach.
- **"AI meeting notetaker Linear"** — contested *and* the wrong fight: the query implies a bot-joins-your-call notetaker, which ActionPoints deliberately is not.

Fellow, Fireflies, Tactiq, Spinach, Read.ai, and Sembly each maintain a dedicated `/integrations/linear` (or equivalent) landing page. On every Linear-adjacent SERP, **linear.app's own integrations directory takes 2–3 slots** — Linear's directory is a ranking machine, so a listing there is likely the single highest-leverage placement in this space, worth more than trying to outrank it.

### Winnable — realistic organic entry points

1. **"extract action items from transcript" family** — page one is prompt-template blogs (BrassTranscripts ×3), SEO template farms (Relevance AI ×2), dev docs (Instructor), a patent listing, and low-authority consulting blogs. No product on page one does paste-transcript → curated tasks. Clearest gap, though the query has no Linear intent — it catches people earlier in the funnel.
2. **"Paste transcript" phrasings** — unclaimed. Every incumbent assumes their bot recorded the call; nobody targets the paste-a-transcript workflow explicitly. This is ActionPoints' actual differentiator and an unowned phrase.
3. **Review/curation-intent queries** ("review AI action items before creating tickets") — only listicles and how-tos rank; the auto-push-vs-curate distinction exists in content but no vendor page owns it.
4. **Long-tail DIY queries** (transcript → tasks with ChatGPT/Claude prompts, n8n templates, Gumroad prompt packs) — held by Substack posts and Gumroad listings, i.e., beatable authority. This DIY content is exactly the behaviour ActionPoints productizes.

Semi-contested middle: the literal query "meeting transcript to Linear tasks" has Tactiq/Fellow/Linear up top but a thin bottom half — a GitHub markdown file, a Mistral AI cookbook, and TaskExtract (task-extract.com), a micro-product nearly the same shape as ActionPoints, showing small players can rank here.

**SEO verdict:** cede the "X to Linear" head terms; build for the extract/paste/review long tail; pursue a linear.app integrations directory listing as the priority distribution move.

Key sources: [linear.app/integrations/fellow](https://linear.app/integrations/fellow) · [linear.app/integrations/fireflies-ai](https://linear.app/integrations/fireflies-ai) · [linear.app/integrations/tactiq](https://linear.app/integrations/tactiq) · [fellow.ai/integrations/linear](https://fellow.ai/integrations/linear) · [fireflies.ai Linear page](https://fireflies.ai/integrations/project-management/linear) · [Tactiq help](https://help.tactiq.io/en/articles/12085070-automatically-create-linear-issues-from-meeting-transcripts) · [Spinach blog](https://www.spinach.ai/blog/sync-meeting-action-items-to-linear) · [Read.ai help](https://support.read.ai/hc/en-us/articles/47812994290451-Creating-Linear-issues-from-your-action-items) · [Sembly](https://www.sembly.ai/automations/linear/) · [BrassTranscripts](https://brasstranscripts.com/blog/meeting-transcript-action-items-ai-prompt) · [TaskExtract](https://task-extract.com/) · [Mistral cookbook](https://docs.mistral.ai/cookbooks/mistral-agents-non_framework-transcript_linearticket_agent-transcripttolinearticketagent)

## Conclusions

1. **Crowded category, empty niche.** "AI meeting notes → Linear" is served by at least eight funded products, but all of them are call-attending, per-seat, auto-creating notetakers. Paste-a-transcript → curated Review → push is not offered by anyone surveyed; the nearest neighbours are Tactiq (transcript-file upload, but auto-workflow, per-seat) and micro-product TaskExtract.
2. **No free tier covers the use case.** Getting action items into Linear is behind a paywall at every vendor (Fireflies Pro $10, Fellow Team $7, Tactiq Team ~£12, tl;dv paid, Circleback $20.83, Spinach Pro $2.90/hr) — annual per-seat commitments of roughly £70–£250/user/year versus ActionPoints' £5 pack. The one unverified exception is Spinach's Starter tier (secondary-source claim only).
3. **Differentiation verdict: yes, with a shelf life.** Curation-as-the-product and paste-anything input are both genuinely unoccupied, but neither is technically hard to copy. Treat them as a positioning head start, not a moat.
4. **Distribution: don't fight the head terms.** Every "meeting + Linear" SERP is owned by incumbent money pages plus 2–3 linear.app directory slots. Realistic organic entry: the "extract action items from transcript" family, "paste transcript" phrasings, and review/curation-intent queries — all currently held by prompt blogs, forums, and thin content. The single highest-leverage move is a listing in Linear's own integrations directory, which outranks every vendor on every relevant query.
