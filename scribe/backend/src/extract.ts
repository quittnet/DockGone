import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import {
  extractionResultSchema,
  type ExtractionRequest,
  type ExtractionResult,
} from "./schema.js";

export const MODEL = "claude-opus-4-8";

export const SYSTEM_PROMPT = `You extract calendar events and reminders from a transcript of a recording (a meeting, voice note, or imported call).

The transcript may be messy speech-to-text. Pull out only concrete, actionable items the user would want on their calendar or in their reminders:
- Calendar events: things that happen at a time/place (meetings, lunches, calls, appointments, flights).
- Reminders: tasks/to-dos the user should do ("remind me to...", "I need to...", "don't forget to...").

Rules:
- Resolve every relative date/time ("tomorrow", "next Tuesday", "in two weeks", "Friday at 3") against the provided current time and timezone, and output absolute ISO-8601 LOCAL date-times with NO timezone suffix (e.g. 2026-06-16T12:00:00).
- If an event has a time but no end, set end to null (the app defaults to one hour).
- Use allDay=true only when no specific time is given for an event (e.g. "her birthday is on the 20th").
- Infer reminder priority from urgency words ("urgent", "asap" -> high); otherwise "none".
- Do NOT invent items. If the transcript has no actionable events or reminders, return empty arrays.
- Keep titles short and human; put extra detail in notes.
- Deduplicate: if the same item is mentioned twice, emit it once.`;

export function buildUserContent(req: ExtractionRequest): string {
  return [
    `Current time: ${req.now}`,
    `Timezone: ${req.timeZone}`,
    "",
    "Transcript:",
    '"""',
    req.transcript.trim(),
    '"""',
  ].join("\n");
}

/**
 * Minimal structural type so tests can inject a fake client without pulling in
 * the whole SDK surface. The real `Anthropic` client satisfies this.
 */
export interface ParsingClient {
  messages: {
    parse(body: unknown): Promise<{ parsed_output: ExtractionResult | null; stop_reason?: string | null }>;
  };
}

export async function extract(
  req: ExtractionRequest,
  client: ParsingClient,
): Promise<ExtractionResult> {
  const response = await client.messages.parse({
    model: MODEL,
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content: buildUserContent(req) }],
    output_config: {
      format: zodOutputFormat(extractionResultSchema),
    },
  });

  if (response.stop_reason === "refusal") {
    throw new Error("Model declined to process this transcript.");
  }
  if (!response.parsed_output) {
    throw new Error("Model returned no parseable structured output.");
  }
  // Defensive re-validation (parse() already validated, but the schema is the contract).
  return extractionResultSchema.parse(response.parsed_output);
}

/** Construct the real Anthropic client. Reads ANTHROPIC_API_KEY from the env. */
export function createClient(): ParsingClient {
  return new Anthropic() as unknown as ParsingClient;
}
