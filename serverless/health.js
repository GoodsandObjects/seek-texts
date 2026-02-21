/**
 * Example serverless health endpoint.
 * Route: GET /api/health
 */

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  res.status(200).json({ ok: true });
}
