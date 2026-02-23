/**
 * Example serverless proxy endpoint for Guided Study.
 * Routes:
 *   GET /api/health
 *   POST /api/guided-study
 *
 * Required env var:
 *   OPENAI_API_KEY
 */

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 20;
const rateBuckets = new Map();
const MAX_SCRIPTURE_REF_LENGTH = 240;
const MAX_PASSAGE_LENGTH = 8_000;
const MAX_MESSAGE_LENGTH = 1_200;
const MAX_MESSAGE_COUNT = 24;

function getClientIP(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim().length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket?.remoteAddress || "unknown";
}

function exceedsRateLimit(ip) {
  const now = Date.now();
  const bucket = rateBuckets.get(ip) || [];
  const recent = bucket.filter((ts) => now - ts < RATE_LIMIT_WINDOW_MS);
  if (recent.length >= RATE_LIMIT_MAX_REQUESTS) {
    rateBuckets.set(ip, recent);
    return true;
  }
  recent.push(now);
  rateBuckets.set(ip, recent);
  return false;
}

function sanitizeText(input, maxLength) {
  if (typeof input !== "string") return "";
  const stripped = input
    .replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return stripped.slice(0, maxLength);
}

function outputUnsafe(text) {
  const lower = String(text || "").toLowerCase();
  const blockedPatterns = [
    /\b(fuck|shit|bitch|cunt|motherfucker)\b/i,
    /\b(kill yourself|suicide method|how to make a bomb|how to murder)\b/i
  ];
  return blockedPatterns.some((pattern) => pattern.test(lower));
}

export default async function handler(req, res) {
  if (req.method === "GET") {
    res.status(200).json({ ok: true });
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const clientIP = getClientIP(req);
  if (exceedsRateLimit(clientIP)) {
    res.status(429).json({ error: "Too many requests. Please try again shortly." });
    return;
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: "Server misconfiguration" });
    return;
  }

  try {
    if (!req.body || typeof req.body !== "object") {
      res.status(400).json({ error: "Invalid JSON payload." });
      return;
    }

    const {
      scriptureRef = "",
      passageText = "",
      messages = [],
      locale = "en-US"
    } = req.body ?? {};

    const cleanScriptureRef = sanitizeText(scriptureRef, MAX_SCRIPTURE_REF_LENGTH);
    const cleanPassageText = sanitizeText(passageText, MAX_PASSAGE_LENGTH);
    if (cleanScriptureRef.length == 0 && cleanPassageText.length == 0) {
      res.status(400).json({ error: "Missing scripture context." });
      return;
    }

    if (!Array.isArray(messages) || messages.length === 0) {
      res.status(400).json({ error: "Messages are required." });
      return;
    }
    if (messages.length > MAX_MESSAGE_COUNT) {
      res.status(400).json({ error: "Too many messages in one request." });
      return;
    }

    const systemPrompt =
      "You are Guided Study, a neutral and balanced religious study companion.\n" +
      "You help users explore religious texts respectfully across Christianity, Islam, Judaism, Hinduism, Buddhism.\n" +
      "If a request is outside religious texts, religious traditions, spiritual practice, or reflection, gently redirect to this scope.\n" +
      "Use wording like: I’m here to help with guided study of religious texts and traditions. If you share a passage, tradition, or question you’re exploring, I can help.\n" +
      "Provide context grounded in the tradition.\n" +
      "Explain themes calmly.\n" +
      "Present interpretations descriptively, not prescriptively.\n" +
      "Do not assert theological truth claims.\n" +
      "Do not challenge or correct beliefs.\n" +
      "Do not compare religions unless asked.\n" +
      "Do not rank traditions.\n" +
      "Avoid preachy, devotional, skeptical, or dismissive tone.\n" +
      "Avoid moral prescriptions and 'you should' language.\n" +
      "Use clean language: no profanity, vulgarity, slang, sexualized, or aggressive phrasing.\n" +
      "Maintain calm, respectful wording even if the user is harsh.\n" +
      "If asked for self-harm, violence, or illegal wrongdoing instructions, refuse clearly and gently redirect toward safety and lawful support.\n" +
      "Never provide methods, steps, planning, or optimization for harmful or illegal acts.\n" +
      "You may ask one gentle optional follow-up question.";

    const history = messages
      .filter((m) => (m?.role === "user" || m?.role === "assistant") && typeof m?.content === "string")
      .map((m) => ({
        role: m.role,
        content: sanitizeText(m.content, MAX_MESSAGE_LENGTH)
      }))
      .filter((m) => m.content.length > 0);
    if (history.length === 0) {
      res.status(400).json({ error: "No valid messages found." });
      return;
    }

    const openAIMessages = [
      { role: "system", content: systemPrompt },
      {
        role: "user",
        content: [
          `Scripture Reference: ${cleanScriptureRef}`,
          `Passage Text: ${cleanPassageText}`,
          `Locale: ${sanitizeText(String(locale), 64)}`
        ].join("\n")
      },
      ...history
    ];

    const openAIResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        messages: openAIMessages
      })
    });

    if (!openAIResponse.ok) {
      const body = await openAIResponse.text();
      res.status(openAIResponse.status).json({ error: body.slice(0, 500) });
      return;
    }

    const data = await openAIResponse.json();
    const reply = data?.choices?.[0]?.message?.content || "";
    const safeReply = sanitizeText(reply, 4_000);
    const finalReply = outputUnsafe(safeReply)
      ? "I can’t help with harmful or explicit content. If you want, we can continue with a safe, respectful reflection on the passage."
      : safeReply;

    res.status(200).json({ replyText: String(finalReply).trim() });
  } catch (error) {
    res.status(500).json({ error: "Proxy request failed" });
  }
}
