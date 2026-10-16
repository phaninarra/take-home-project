const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = Number(process.env.PORT || 8081);
const API_KEY = process.env.API_KEY || "pd_live_7f3c9a2e5b81";

const raw = fs.readFileSync(path.join(__dirname, "data", "payees.json"), "utf8");
const records = JSON.parse(raw).payees;
const byId = new Map(records.map((r) => [r.payeeId, r]));

function shape(r) {
  return {
    id: r.payeeId,
    displayName: r.name,
    program: r.programId,
    account: { last4: r.accountLast4, routingLast4: r.routingLast4 },
    state: r.status,
  };
}

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function fail(res, status, code, message) {
  send(res, status, { error: { code, message } });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");

  if (url.pathname === "/health") {
    return send(res, 200, { state: "up" });
  }

  if (req.headers["x-api-key"] !== API_KEY) {
    return fail(res, 401, "invalid_api_key", "Supply a valid X-Api-Key header.");
  }

  if (req.method !== "GET") {
    return fail(res, 405, "method_not_allowed", `${req.method} is not supported.`);
  }

  const single = url.pathname.match(/^\/payees\/([A-Za-z0-9-]+)$/);
  if (single) {
    const found = byId.get(single[1]);
    if (!found) {
      return fail(res, 404, "not_found", `No payee with id ${single[1]}.`);
    }
    return send(res, 200, { payee: shape(found) });
  }

  if (url.pathname === "/payees") {
    const program = url.searchParams.get("program");
    let subset = records;
    if (program) {
      subset = records.filter((r) => r.programId === program);
    }
    return send(res, 200, { payees: subset.map(shape), count: subset.length });
  }

  return fail(res, 404, "no_route", `Nothing at ${url.pathname}.`);
});

server.listen(PORT, "0.0.0.0");
