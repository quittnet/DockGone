# Scribe backend

A tiny HTTP service that takes a transcript and returns the calendar events and
reminders found in it, using the Claude API. It exists so the **Anthropic API key
never ships inside the iOS app** (a distributed app's secrets are extractable). The
app talks only to this service over HTTPS.

- Model: `claude-opus-4-8` with adaptive thinking and structured outputs.
- One real endpoint: `POST /extract`. Plus `GET /health`.

## Run locally

```bash
cd scribe/backend
npm install
cp .env.example .env       # then put your real ANTHROPIC_API_KEY in .env
npm run build
npm run start:local        # loads .env, listens on http://localhost:8787 (override with PORT)
```

`start:local` reads `.env` via Node's `--env-file`. In production (Render/Fly/etc.) use
`npm start` and set the env vars in the host's config instead. You can also export directly:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
npm start
```

> **Testing from the iOS Simulator:** point the app's Settings at `http://localhost:8787`.
> The Simulator shares your Mac's network, and the app already allows plain-HTTP to
> localhost for development (`NSAllowsLocalNetworking`). A **physical iPhone** can't reach
> your Mac's `localhost` — deploy the backend (HTTPS) and use that URL, or use your Mac's
> LAN IP with an ATS exception.

### Try it

```bash
curl -s localhost:8787/health

curl -s -XPOST localhost:8787/extract \
  -H 'content-type: application/json' \
  -d '{
    "transcript": "Lunch with Sam next Tuesday at noon at Joe'\''s Diner. Remind me to send the invoice Friday.",
    "now": "2026-06-12T09:00:00-04:00",
    "timeZone": "America/New_York"
  }'
```

Returns:

```json
{
  "events": [
    { "title": "Lunch with Sam", "start": "2026-06-16T12:00:00", "end": null,
      "allDay": false, "location": "Joe's Diner", "notes": null }
  ],
  "reminders": [
    { "title": "Send the invoice", "dueDate": "2026-06-19T09:00:00", "notes": null, "priority": "none" }
  ]
}
```

## Test

```bash
npm test
```

Runs schema/parse/route tests with a fake model client (no network, no key). One
test — `live: extract against the real model` — is **skipped unless
`ANTHROPIC_API_KEY` is set**; set it to exercise the real API end to end.

## API

### `POST /extract`

Request body:

| Field        | Type   | Notes |
|--------------|--------|-------|
| `transcript` | string | The recording transcript. Empty/whitespace returns empty arrays without calling the model. |
| `now`        | string | Caller's current time, ISO-8601 with offset (e.g. `2026-06-12T09:00:00-04:00`). Used to resolve relative dates. |
| `timeZone`   | string | IANA id, e.g. `America/New_York`. |

Response: `{ events: ProposedEvent[], reminders: ProposedReminder[] }` — see
`src/schema.ts` (the single source of truth, mirrored by the Swift
`Proposal.swift` models). Date-times are ISO-8601 **local** (no timezone suffix).

Errors: `400` invalid body, `502` extraction failed (model error / missing key).

## Deploy

Any Node host works. Set `ANTHROPIC_API_KEY` (and optionally `PORT`) in the host's
secret/env config — never commit it.

- **Docker:** `docker build -t scribe-backend . && docker run -p 8787:8787 -e ANTHROPIC_API_KEY=sk-ant-... scribe-backend`
- **Render / Railway / Fly.io:** build command `npm install && npm run build`, start command `npm start`, add `ANTHROPIC_API_KEY` as a secret.

Then point the iOS app's **Settings → Backend URL** at the deployed `https://…` base URL.
Put the service behind HTTPS; consider adding your own auth (e.g. a shared bearer
token header) before exposing it publicly so it isn't an open proxy to your key.
