# Develop locally against Docker; deploy only at the end

The original build order (product brief, 2026-07-26) had the walking skeleton deployed to Fly.io as step 1, with every subsequent ticket shipping to a live instance. Reversed: no remote instances run until the product is something we're actually happy to deploy. All development happens on the local machine, with Docker Compose providing Postgres (and any other backing services); the app itself runs locally via `mix phx.server` / `mix test` against those containers. No coding on remote servers.

Fly.io remains the deployment target — ADR-0001's stack choice stands untouched. What changes is timing: deployment is the *last* ticket, done once, when the product works end-to-end locally.

## Why

- Running a live instance during development costs money and attention for zero feedback benefit — everything the build needs to verify is verifiable locally.
- A public URL serving half-built software is a liability (abuse of the anonymous demo, half-wired Stripe webhooks), not an asset.
- "Deploy pain while fresh" was the old rationale; a Dockerised app makes the eventual Fly deploy predictable enough that front-loading it buys nothing.

## Consequences

- Ticket 01 becomes a *local* walking skeleton: Phoenix + Postgres via `docker compose`, green `mix test`, placeholder page on `localhost` — no Fly, no public URL.
- A new final ticket owns the single deploy to Fly (Dockerfile, `fly.toml`, secrets, attached Postgres), blocked by the rest of the build.
- Stripe webhooks are exercised locally (Stripe CLI forwarding / fake provider in tests) rather than against a live URL.
