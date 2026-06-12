import * as z from "zod/v4";

/**
 * Single source of truth for the extraction payload shape.
 *
 * This MUST stay in sync with the Swift `Proposal` models in
 * `scribe/ios/Sources/Models/Proposal.swift`. If you change a field here,
 * change it there too.
 *
 * Date/time fields are ISO-8601 *local* date-times WITHOUT a timezone suffix,
 * e.g. "2026-06-16T12:00:00". The model resolves relative phrases
 * ("next Tuesday", "in two weeks") against the caller-supplied `now` and
 * `timeZone`, then emits wall-clock local times. The iOS client interprets
 * them in the device's current calendar/timezone.
 *
 * Note on JSON-Schema constraints: Anthropic structured outputs do not support
 * numeric/length constraints (min/max, minLength) — the SDK strips them and
 * validates client-side. Keep the schema to types + enums + descriptions.
 */

const localDateTime = z
  .string()
  .describe('ISO-8601 local date-time with no timezone suffix, e.g. "2026-06-16T12:00:00".');

export const reminderPriority = z.enum(["none", "low", "medium", "high"]);
export type ReminderPriority = z.infer<typeof reminderPriority>;

export const proposedEventSchema = z.object({
  title: z.string().describe("Short title for the calendar event."),
  start: localDateTime.describe("Event start. For all-day events use 00:00:00."),
  end: localDateTime
    .nullable()
    .describe("Event end. Null if unknown; client defaults to start + 1 hour."),
  allDay: z.boolean().describe("True for all-day events with no specific time."),
  location: z.string().nullable().describe("Location text, or null."),
  notes: z.string().nullable().describe("Extra context from the transcript, or null."),
});
export type ProposedEvent = z.infer<typeof proposedEventSchema>;

export const proposedReminderSchema = z.object({
  title: z.string().describe("Short title for the reminder / to-do."),
  dueDate: localDateTime
    .nullable()
    .describe("When it is due, or null if no due date was mentioned."),
  notes: z.string().nullable().describe("Extra context from the transcript, or null."),
  priority: reminderPriority.describe("Priority inferred from the transcript; default 'none'."),
});
export type ProposedReminder = z.infer<typeof proposedReminderSchema>;

export const extractionResultSchema = z.object({
  events: z.array(proposedEventSchema).describe("Calendar events found. Empty array if none."),
  reminders: z
    .array(proposedReminderSchema)
    .describe("Reminders / to-dos found. Empty array if none."),
});
export type ExtractionResult = z.infer<typeof extractionResultSchema>;

/** Shape of the request body the iOS app sends to POST /extract. */
export const extractionRequestSchema = z.object({
  transcript: z.string(),
  /** Caller's current time as an ISO-8601 string (with offset), used to resolve relative dates. */
  now: z.string(),
  /** IANA timezone identifier, e.g. "America/New_York". */
  timeZone: z.string(),
});
export type ExtractionRequest = z.infer<typeof extractionRequestSchema>;
