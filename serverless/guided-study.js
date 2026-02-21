/**
 * Example serverless proxy endpoint for Guided Study.
 * Routes:
 *   GET /api/health
 *   POST /api/guided-study
 *
 * Required env var:
 *   OPENAI_API_KEY
 */

export default async function handler(req, res) {
  if (req.method === "GET") {
    res.status(200).json({ ok: true });
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: "Server misconfiguration" });
    return;
  }

  try {
    const {
      scriptureRef = "",
      passageText = "",
      messages = [],
      locale = "en-US"
    } = req.body ?? {};

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
      "You may ask one gentle optional follow-up question.";

    const history = Array.isArray(messages)
      ? messages
          .filter((m) => (m?.role === "user" || m?.role === "assistant") && typeof m?.content === "string")
          .map((m) => ({ role: m.role, content: m.content }))
      : [];

    const openAIMessages = [
      { role: "system", content: systemPrompt },
      {
        role: "user",
        content: [
          `Scripture Reference: ${String(scriptureRef)}`,
          `Passage Text: ${String(passageText)}`,
          `Locale: ${String(locale)}`
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

    res.status(200).json({ replyText: String(reply).trim() });
  } catch (error) {
    res.status(500).json({ error: "Proxy request failed" });
  }
}
