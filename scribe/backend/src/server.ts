import express, { type Request, type Response } from "express";
import { extractionRequestSchema } from "./schema.js";
import { createClient, extract, type ParsingClient } from "./extract.js";

const PORT = Number(process.env.PORT ?? 8787);

export function createServer(client: ParsingClient) {
  const app = express();
  app.use(express.json({ limit: "1mb" }));

  app.get("/health", (_req: Request, res: Response) => {
    res.json({ ok: true, hasApiKey: Boolean(process.env.ANTHROPIC_API_KEY) });
  });

  app.post("/extract", async (req: Request, res: Response) => {
    const parsed = extractionRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid_request", details: parsed.error.flatten() });
      return;
    }
    if (!parsed.data.transcript.trim()) {
      res.json({ events: [], reminders: [] });
      return;
    }
    try {
      const result = await extract(parsed.data, client);
      res.json(result);
    } catch (err) {
      const message = err instanceof Error ? err.message : "extraction_failed";
      console.error("extract failed:", message);
      res.status(502).json({ error: "extraction_failed", message });
    }
  });

  return app;
}

// Only boot a real server when run directly (not when imported by tests).
const isMain = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.warn("WARNING: ANTHROPIC_API_KEY is not set — /extract will fail until it is.");
  }
  const app = createServer(createClient());
  app.listen(PORT, () => {
    console.log(`Scribe backend listening on http://localhost:${PORT}`);
  });
}
