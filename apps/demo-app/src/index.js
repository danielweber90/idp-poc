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
