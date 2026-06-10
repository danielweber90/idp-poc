const express = require("express");
const { Pool } = require("pg");
const redis = require("redis");
const promClient = require("prom-client");
const app = express();
const PORT = process.env.PORT || 3000;

promClient.collectDefaultMetrics();
const httpDuration = new promClient.Histogram({ name: "http_request_duration_seconds", help: "Request duration", labelNames: ["method","route","status"] });
const httpTotal = new promClient.Counter({ name: "http_requests_total", help: "Total requests", labelNames: ["method","route","status"] });
app.use((req, res, next) => {
  const end = httpDuration.startTimer();
  res.on("finish", () => { const l = {method:req.method,route:req.path,status:res.statusCode}; end(l); httpTotal.inc(l); });
  next();
});
app.use(express.json());

const db = process.env.DATABASE_URL
  ? new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } })
  : null;

let rc = null;
if (process.env.REDIS_URL) { rc = redis.createClient({ url: process.env.REDIS_URL }); rc.connect().catch(console.error); }

app.get("/", (_, res) => res.send(`<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>IDP PoC Demo App</title>
<style>
  body{font-family:system-ui,sans-serif;max-width:640px;margin:60px auto;padding:0 20px;color:#1a1a1a}
  h1{font-size:1.6rem;margin-bottom:4px}
  p.sub{color:#555;margin-top:0}
  table{width:100%;border-collapse:collapse;margin-top:24px}
  th{text-align:left;padding:8px 12px;background:#f0f0f0;font-size:.85rem;text-transform:uppercase;letter-spacing:.05em}
  td{padding:10px 12px;border-top:1px solid #e8e8e8;font-size:.95rem}
  td a{color:#0066cc;text-decoration:none}
  td a:hover{text-decoration:underline}
  .badge{display:inline-block;padding:2px 8px;border-radius:4px;font-size:.8rem;font-weight:600}
  .ok{background:#d4edda;color:#155724}
  .warn{background:#fff3cd;color:#856404}
</style>
</head>
<body>
  <h1>IDP PoC — Demo App</h1>
  <p class="sub">Node.js · Express · PostgreSQL · Redis · Prometheus metrics</p>
  <table>
    <tr><th>Endpoint</th><th>Description</th></tr>
    <tr><td><a href="/health">/health</a></td><td>Liveness check</td></tr>
    <tr><td><a href="/api/info">/api/info</a></td><td>Backing-service connection status</td></tr>
    <tr><td><a href="/api/db-test">/api/db-test</a></td><td>Write a row to RDS, return visit count</td></tr>
    <tr><td><a href="/api/cache-test">/api/cache-test</a></td><td>Increment Redis counter</td></tr>
    <tr><td><a href="/metrics">/metrics</a></td><td>Prometheus metrics (scraped by Grafana)</td></tr>
  </table>
</body>
</html>`));

app.get("/health", (_, res) => res.json({ status: "ok", version: "1.0.0" }));
app.get("/metrics", async (_, res) => { res.set("Content-Type", promClient.register.contentType); res.end(await promClient.register.metrics()); });
app.get("/api/info", (_, res) => res.json({ app: "IDP PoC Demo App", db: db ? "connected" : "not configured", redis: rc ? "connected" : "not configured" }));
app.get("/api/db-test", async (_, res) => {
  if (!db) return res.status(503).json({ error: "DB not configured" });
  try {
    await db.query("CREATE TABLE IF NOT EXISTS visits (id SERIAL, ts TIMESTAMPTZ DEFAULT NOW())");
    await db.query("INSERT INTO visits DEFAULT VALUES");
    const r = await db.query("SELECT count(*) as total FROM visits");
    res.json({ visits: r.rows[0].total });
  } catch(e) { res.status(500).json({ error: e.message }); }
});
app.get("/api/cache-test", async (_, res) => {
  if (!rc) return res.status(503).json({ error: "REDIS_URL not set" });
  try { res.json({ counter: await rc.incr("poc-counter") }); } catch(e) { res.status(500).json({ error: e.message }); }
});
app.listen(PORT, () => console.log("Demo app on " + PORT));
