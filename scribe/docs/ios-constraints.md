# Why Scribe works the way it does (iOS platform constraints)

The original request was: *"record my phone calls, use AI to read the transcripts,
add things to my Calendar and Reminders, and do the same for WhatsApp and Messages."*

Most of that is **not possible** in a normal App-Store iOS app — not because of effort,
but because Apple's platform forbids it. This document records exactly what's blocked
and what the legitimate alternatives are, so the constraint lives in the repo, not just
in a conversation.

## What iOS blocks

| Requested capability | Possible? | Why not |
|---|---|---|
| Record native cellular phone calls | ❌ | There is **no public API** to access the audio of the system Phone app's calls. App-Store "call recorder" apps don't tap the real call — they place a **3-way call to a recording bridge** (a telephony backend like Twilio) that records the conference server-side. On-device interception is only possible on a jailbroken phone. |
| Automatically read WhatsApp messages | ❌ | The iOS **app sandbox** isolates every app's data, and WhatsApp is **end-to-end encrypted**. No API lets one app read another app's messages. |
| Automatically read iMessage / SMS | ❌ | There is **no API** for reading your Messages history. The Messages framework only supports iMessage *app extensions* (stickers/interactive messages) inside the Messages app — it cannot read conversations. |
| Create Calendar events | ✅ | The **EventKit** framework supports this with user permission. |
| Create Reminders | ✅ | EventKit again. |
| AI transcription + extraction | ✅ | On audio/text the app legitimately has (recorded/imported audio, or shared message text). |

Processing **your own** data is perfectly legitimate. The blocker is purely the sandbox,
which an App-Store app cannot circumvent.

## What Scribe does instead

1. **Capture audio the app is allowed to have:** record in-app (meetings, voice notes) or
   import an existing audio file (e.g. a recording from a call-recording *service*).
2. **Transcribe on-device** with Apple's Speech framework — raw audio never leaves the phone.
3. **Extract** events and reminders by sending only the **text transcript** to a small
   backend that calls Claude.
4. **Write** the approved items into Apple Calendar and Reminders via EventKit.

### Messaging (Phase 2): Share Extension

The only legitimate way to get WhatsApp/Messages content into an app is **user-initiated
sharing**: you open a thread, tap **Share**, and pick Scribe. A Share Extension target
(planned for Phase 2) receives that shared text and runs it through the **same**
extract → review → EventKit pipeline. There is no automatic or background reading — by design.

### A note on transcription

Claude is a text/vision model; it does not transcribe audio. Scribe transcribes
**on-device** (Apple Speech): free, private, and no second vendor. If you ever want
fully-cloud transcription instead (e.g. Whisper/Deepgram), add a transcription endpoint to
the backend — at the cost of uploading raw audio and adding another API key.

### Legal note

Recording conversations involving other people may require their consent depending on your
jurisdiction (e.g. all-party-consent states/countries). Scribe surfaces this in the app; it's
your responsibility to record lawfully.
