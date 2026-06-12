# Scribe

An iOS app that turns recordings into **Apple Calendar events** and **Reminders** using AI.

Record a meeting or voice note (or import an audio file), and Scribe transcribes it
**on your device**, sends the text to a small backend that asks **Claude** to pull out the
events and to-dos, then lets you review and add them to Calendar and Reminders with a tap.

> **Working name "Scribe" — rename freely** (the bundle id `com.example.scribe`, the
> XcodeGen `name`, and the display name in `ios/Resources/Info.plist`).

## Important: what iOS does and doesn't allow

This started as "record my phone calls and read my WhatsApp/Messages." **iOS makes those
impossible** for a normal App-Store app — see [`docs/ios-constraints.md`](docs/ios-constraints.md)
for the full explanation. The short version:

- ❌ Apps **cannot** record native phone calls (no API for the call audio stream).
- ❌ Apps **cannot** read WhatsApp / iMessage / SMS (sandbox + encryption).
- ✅ Apps **can** transcribe audio you record/import and write to Calendar & Reminders.
- ✅ Messages can be brought in only by **you tapping Share** into the app (Phase 2 Share Extension).

## Architecture

```
Record / import audio ─▶ on-device transcript (Apple Speech)
        │
        └─▶ POST /extract {transcript, now, timeZone} ─▶ backend ─▶ Claude (claude-opus-4-8)
                                                                    {events:[…], reminders:[…]}
        ◀───────────────────────────────────────────────────────────────────────────────────
   Review & edit ─▶ EventKit ─▶ Apple Calendar + Reminders
```

- **`ios/`** — SwiftUI app (iOS 17+). Audio capture, on-device transcription, review UI, EventKit.
- **`backend/`** — Node + TypeScript service holding the Anthropic API key; one endpoint, `POST /extract`.
- **`docs/`** — the iOS-constraints write-up.

## Quick start

### 1. Backend (works on macOS or Linux)

```bash
cd backend
npm install
cp .env.example .env          # add your real ANTHROPIC_API_KEY
npm run build && npm test     # tests pass without a key (the live test is skipped)
npm start                     # http://localhost:8787
```

Deploy it somewhere with HTTPS (Render/Railway/Fly/Docker) and note the URL. See
[`backend/README.md`](backend/README.md).

### 2. iOS app (requires a Mac with Xcode)

```bash
cd ios
brew install xcodegen         # one-time
xcodegen generate             # writes Scribe.xcodeproj from project.yml
open Scribe.xcodeproj
```

In Xcode: set your Development Team (Signing & Capabilities), then run on a device or
simulator. Open **Settings (gear)** in the app and paste your backend's base URL. Record a
short clip, confirm the transcript, review the proposed events/reminders, and add them.

## Roadmap

- **Phase 1 (here):** record/import → transcribe → AI extract → review → Calendar & Reminders.
- **Phase 2:** Share Extension so a WhatsApp/Messages thread shared into Scribe runs the same pipeline.

## Notes

- Audio is transcribed on-device; only the **text** transcript is sent to your backend.
- The backend exists so the Anthropic key never ships inside the app. Consider adding your own
  auth to the backend before exposing it publicly so it isn't an open proxy to your key.
- Recording other people may require their consent depending on your jurisdiction.
