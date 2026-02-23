const MAX_SCRIPTURE_REF_LENGTH = 240;
const MAX_PASSAGE_LENGTH = 8000;
const MAX_MESSAGE_LENGTH = 1200;
const MAX_MESSAGE_COUNT = 24;
const MAX_LOCALE_LENGTH = 64;
const MAX_REPLY_LENGTH = 4000;

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 20;
const rateBuckets = new Map();

const OPENAI_CHAT_COMPLETIONS_URL = "https://api.openai.com/v1/chat/completions";
const OPENAI_MODERATIONS_URL = "https://api.openai.com/v1/moderations";

const SYSTEM_PROMPT = [
  "You are Guided Study, a neutral and balanced religious study companion.",
  "You help users explore religious texts respectfully across Christianity, Islam, Judaism, Hinduism, Buddhism.",
  "If a request is outside religious texts, religious traditions, spiritual practice, or reflection, gently redirect to this scope.",
  "Provide context grounded in the tradition.",
  "Explain themes calmly.",
  "Present interpretations descriptively, not prescriptively.",
  "Do not assert theological truth claims.",
  "Do not challenge or correct beliefs.",
  "Do not compare religions unless asked.",
  "Do not rank traditions.",
  "Avoid preachy, devotional, skeptical, or dismissive tone.",
  "Avoid moral prescriptions and 'you should' language.",
  "Use clean language: no profanity, vulgarity, sexualized, or aggressive phrasing.",
  "If asked for self-harm, violence, or illegal wrongdoing instructions, refuse and redirect to safety.",
  "Never provide methods or step-by-step instructions for harmful or illegal acts.",
  "Format for readability: keep paragraphs short (1-2 sentences) with a blank line between paragraphs.",
  "Use bullets sparingly when listing ideas; avoid dense walls of text.",
  "When helpful, use brief section headings such as Plain meaning, Key ideas, and Reflection.",
].join("\\n");

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method.toUpperCase();

    if (method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(request, env),
      });
    }

    if (url.pathname === "/health" && method === "GET") {
      return jsonResponse({ ok: true }, 200, request, env);
    }

    if (url.pathname === "/guided-study" && method === "POST") {
      return handleGuidedStudy(request, env);
    }

    if (url.pathname === "/guided-study" || url.pathname === "/health") {
      return jsonResponse({ error: "Method not allowed" }, 405, request, env);
    }

    return jsonResponse({ error: "Not found" }, 404, request, env);
  },
};

async function handleGuidedStudy(request, env) {
  if (!env.OPENAI_API_KEY) {
    return jsonResponse({ error: "Server misconfiguration" }, 500, request, env);
  }

  const clientIP = getClientIP(request);
  if (exceedsRateLimit(clientIP)) {
    return jsonResponse(
      { error: "Too many requests. Please try again shortly." },
      429,
      request,
      env,
      {
        "Retry-After": String(Math.ceil(RATE_LIMIT_WINDOW_MS / 1000)),
      }
    );
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON payload." }, 400, request, env);
  }

  if (!payload || typeof payload !== "object") {
    return jsonResponse({ error: "Invalid JSON payload." }, 400, request, env);
  }

  const scriptureRefRaw = payload.scriptureRef;
  const passageTextRaw = payload.passageText;
  const localeRaw = payload.locale;
  const messagesRaw = payload.messages;

  if (containsDisallowedMarkup(scriptureRefRaw) || containsDisallowedMarkup(passageTextRaw) || containsDisallowedMarkup(localeRaw)) {
    return jsonResponse({ error: "Input contains disallowed markup." }, 400, request, env);
  }

  const scriptureRef = sanitizeText(scriptureRefRaw, MAX_SCRIPTURE_REF_LENGTH);
  const passageText = sanitizeText(passageTextRaw, MAX_PASSAGE_LENGTH);
  const locale = sanitizeText(typeof localeRaw === "string" ? localeRaw : "en-US", MAX_LOCALE_LENGTH);

  if (!scriptureRef && !passageText) {
    return jsonResponse({ error: "Missing scripture context." }, 400, request, env);
  }

  if (!Array.isArray(messagesRaw) || messagesRaw.length === 0) {
    return jsonResponse({ error: "Messages are required." }, 400, request, env);
  }
  if (messagesRaw.length > MAX_MESSAGE_COUNT) {
    return jsonResponse({ error: "Too many messages in one request." }, 400, request, env);
  }

  const history = [];
  for (const message of messagesRaw) {
    if (!message || typeof message !== "object") {
      continue;
    }

    const role = message.role;
    const content = message.content;

    if ((role !== "user" && role !== "assistant") || typeof content !== "string") {
      continue;
    }

    if (containsDisallowedMarkup(content)) {
      return jsonResponse({ error: "Input contains disallowed markup." }, 400, request, env);
    }

    const cleaned = sanitizeText(content, MAX_MESSAGE_LENGTH);
    if (cleaned) {
      history.push({ role, content: cleaned });
    }
  }

  if (history.length === 0) {
    return jsonResponse({ error: "No valid messages found." }, 400, request, env);
  }

  const latestUserMessage = [...history].reverse().find((m) => m.role === "user")?.content || "";

  const moderationInput = [
    `Scripture Reference: ${scriptureRef}`,
    `Passage Text: ${passageText}`,
    `Latest User Message: ${latestUserMessage}`,
  ].join("\\n");

  const moderation = await moderateText(moderationInput, env.OPENAI_API_KEY);
  if (!moderation.ok) {
    return jsonResponse({ error: moderation.errorMessage }, moderation.statusCode, request, env);
  }

  const openAIMessages = [
    { role: "system", content: SYSTEM_PROMPT },
    {
      role: "user",
      content: [
        `Scripture Reference: ${scriptureRef}`,
        `Passage Text: ${passageText}`,
        `Locale: ${locale || "en-US"}`,
      ].join("\\n"),
    },
    ...history,
  ];

  const completionResponse = await fetch(OPENAI_CHAT_COMPLETIONS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: "gpt-4.1-mini",
      messages: openAIMessages,
      temperature: 0.6,
      max_tokens: 320,
    }),
  });

  if (!completionResponse.ok) {
    const status = completionResponse.status >= 400 && completionResponse.status < 600 ? completionResponse.status : 502;
    return jsonResponse(
      { error: "The study service is temporarily unavailable. Please try again." },
      status,
      request,
      env
    );
  }

  const completionData = await completionResponse.json();
  const rawReply = completionData?.choices?.[0]?.message?.content;
  const replyText = sanitizeText(rawReply, MAX_REPLY_LENGTH);

  if (!replyText) {
    return jsonResponse({ error: "Proxy returned an empty reply." }, 502, request, env);
  }

  const replyModeration = await moderateText(replyText, env.OPENAI_API_KEY);
  if (!replyModeration.ok) {
    return jsonResponse(
      {
        replyText:
          "I can’t provide that response. If you want, I can help with a safe, respectful reflection on this passage.",
      },
      200,
      request,
      env
    );
  }

  return jsonResponse({ replyText }, 200, request, env);
}

async function moderateText(input, apiKey) {
  const response = await fetch(OPENAI_MODERATIONS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "omni-moderation-latest",
      input,
    }),
  });

  if (!response.ok) {
    return {
      ok: false,
      statusCode: 502,
      errorMessage: "Moderation service unavailable.",
    };
  }

  const data = await response.json();
  const flagged = Boolean(data?.results?.[0]?.flagged);

  if (flagged) {
    return {
      ok: false,
      statusCode: 400,
      errorMessage: "Content failed safety checks.",
    };
  }

  return { ok: true };
}

function containsDisallowedMarkup(value) {
  if (typeof value !== "string") return false;
  const lower = value.toLowerCase();
  return (
    /<\s*script\b/i.test(lower) ||
    /<\s*\/\s*script\s*>/i.test(lower) ||
    /<\s*style\b/i.test(lower) ||
    /<[^>]+>/i.test(lower) ||
    /javascript\s*:/i.test(lower) ||
    /on[a-z]+\s*=/.test(lower)
  );
}

function sanitizeText(input, maxLength) {
  if (typeof input !== "string") return "";
  const cleaned = input
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return truncate(cleaned, maxLength);
}

function truncate(value, maxLength) {
  if (!value) return "";
  if (value.length <= maxLength) return value;
  return value.slice(0, maxLength);
}

function getClientIP(request) {
  const cfConnectingIP = request.headers.get("CF-Connecting-IP");
  if (cfConnectingIP) return cfConnectingIP.trim();

  const xForwardedFor = request.headers.get("X-Forwarded-For");
  if (xForwardedFor) {
    return xForwardedFor.split(",")[0].trim();
  }

  return "unknown";
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

function jsonResponse(payload, status, request, env, extraHeaders = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(request, env),
      ...extraHeaders,
    },
  });
}

function corsHeaders(request, env) {
  const allowed = parseAllowedOrigins(env.ALLOWED_ORIGINS);
  const requestOrigin = request.headers.get("Origin") || "";

  let allowOrigin = "*";
  if (allowed.length > 0 && !allowed.includes("*")) {
    allowOrigin = allowed.includes(requestOrigin) ? requestOrigin : allowed[0];
  }

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function parseAllowedOrigins(value) {
  if (typeof value !== "string") return ["*"];
  const entries = value
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  return entries.length > 0 ? entries : ["*"];
}
