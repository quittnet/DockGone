import { test } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";

import { extractionResultSchema, type ExtractionResult } from "../src/schema.js";
import { buildUserContent, extract, type ParsingClient } from "../src/extract.js";
import { createServer } from "../src/server.js";

const SAMPLE_NOW = "2026-06-12T09:00:00-04:00";
const SAMPLE_TZ = "America/New_York";
const SAMPLE_TRANSCRIPT =
  "Lunch with Sam next Tuesday at noon at Joe's Diner. Also remind me to send the invoice on Friday.";

const CANNED_RESULT: ExtractionResult = {
  events: [
    {
      title: "Lunch with Sam",
      start: "2026-06-16T12:00:00",
      end: null,
      allDay: false,
      location: "Joe's Diner",
      notes: null,
    },
  ],
  reminders: [
    {
      title: "Send the invoice",
      dueDate: "2026-06-19T09:00:00",
      notes: null,
      priority: "none",
    },
  ],
};

function fakeClient(result: ExtractionResult | null, stopReason: string | null = null): ParsingClient {
  return {
    messages: {
      async parse() {
        return { parsed_output: result, stop_reason: stopReason };
      },
    },
  };
}

test("schema accepts a well-formed result", () => {
  const parsed = extractionResultSchema.parse(CANNED_RESULT);
  assert.equal(parsed.events.length, 1);
  assert.equal(parsed.reminders[0].priority, "none");
});

test("schema rejects an unknown priority", () => {
  const bad = structuredClone(CANNED_RESULT) as unknown as Record<string, unknown>;
  (bad.reminders as Array<Record<string, unknown>>)[0].priority = "critical";
  assert.throws(() => extractionResultSchema.parse(bad));
});

test("schema rejects a missing required field", () => {
  const bad = structuredClone(CANNED_RESULT) as unknown as { events: Array<Record<string, unknown>> };
  delete bad.events[0].title;
  assert.throws(() => extractionResultSchema.parse(bad));
});

test("buildUserContent embeds transcript, now and timezone", () => {
  const content = buildUserContent({ transcript: SAMPLE_TRANSCRIPT, now: SAMPLE_NOW, timeZone: SAMPLE_TZ });
  assert.ok(content.includes(SAMPLE_TRANSCRIPT));
  assert.ok(content.includes(SAMPLE_NOW));
  assert.ok(content.includes(SAMPLE_TZ));
});

test("extract returns the model's parsed output", async () => {
  const result = await extract(
    { transcript: SAMPLE_TRANSCRIPT, now: SAMPLE_NOW, timeZone: SAMPLE_TZ },
    fakeClient(CANNED_RESULT),
  );
  assert.equal(result.events[0].title, "Lunch with Sam");
  assert.equal(result.reminders[0].title, "Send the invoice");
});

test("extract throws on a refusal", async () => {
  await assert.rejects(
    extract({ transcript: SAMPLE_TRANSCRIPT, now: SAMPLE_NOW, timeZone: SAMPLE_TZ }, fakeClient(null, "refusal")),
    /declined/,
  );
});

test("extract throws when no structured output came back", async () => {
  await assert.rejects(
    extract({ transcript: SAMPLE_TRANSCRIPT, now: SAMPLE_NOW, timeZone: SAMPLE_TZ }, fakeClient(null)),
    /no parseable/,
  );
});

test("GET /health reports status", async () => {
  const server = createServer(fakeClient(CANNED_RESULT)).listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(res.status, 200);
    const body = (await res.json()) as { ok: boolean };
    assert.equal(body.ok, true);
  } finally {
    server.close();
  }
});

test("POST /extract validates the request body", async () => {
  const server = createServer(fakeClient(CANNED_RESULT)).listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const res = await fetch(`http://127.0.0.1:${port}/extract`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ transcript: "hi" }), // missing now + timeZone
    });
    assert.equal(res.status, 400);
  } finally {
    server.close();
  }
});

test("POST /extract returns the extraction for a valid body", async () => {
  const server = createServer(fakeClient(CANNED_RESULT)).listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const res = await fetch(`http://127.0.0.1:${port}/extract`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ transcript: SAMPLE_TRANSCRIPT, now: SAMPLE_NOW, timeZone: SAMPLE_TZ }),
    });
    assert.equal(res.status, 200);
    const body = (await res.json()) as ExtractionResult;
    assert.equal(body.events[0].location, "Joe's Diner");
  } finally {
    server.close();
  }
});

test("POST /extract short-circuits an empty transcript without calling the model", async () => {
  const throwingClient: ParsingClient = {
    messages: {
      async parse() {
        throw new Error("model should not be called");
      },
    },
  };
  const server = createServer(throwingClient).listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const res = await fetch(`http://127.0.0.1:${port}/extract`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ transcript: "   ", now: SAMPLE_NOW, timeZone: SAMPLE_TZ }),
    });
    assert.equal(res.status, 200);
    const body = (await res.json()) as ExtractionResult;
    assert.deepEqual(body, { events: [], reminders: [] });
  } finally {
    server.close();
  }
});

// Opt-in live test against the real Claude API. Skipped unless a key is present.
test(
  "live: extract against the real model",
  { skip: process.env.ANTHROPIC_API_KEY ? false : "ANTHROPIC_API_KEY not set" },
  async () => {
    const { createClient } = await import("../src/extract.js");
    const result = await extract(
      { transcript: SAMPLE_TRANSCRIPT, now: SAMPLE_NOW, timeZone: SAMPLE_TZ },
      createClient(),
    );
    extractionResultSchema.parse(result);
    assert.ok(result.events.length + result.reminders.length >= 1, "expected at least one item");
  },
);
