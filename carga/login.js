import http from "k6/http";
import { check, sleep } from "k6";

const BASE = __ENV.BASE;
const WRITES = Number(__ENV.ESCRITURAS || 10);
const RUN = __ENV.RUN || "local";
const JSON_HEADERS = { "Content-Type": "application/json" };

export const options = {
  scenarios: {
    carga: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: Number(__ENV.VUS || 10) },
        { duration: `${Math.max(1, Number(__ENV.MINUTOS || 3) * 60 - 45)}s`, target: Number(__ENV.VUS || 10) },
        { duration: "15s", target: 0 },
      ],
    },
  },
  thresholds: {
    "http_req_duration{tipo:login}": ["p(95)<2000"],
    "http_req_duration{tipo:lectura}": ["p(95)<2000"],
    "http_req_duration{tipo:escritura}": ["p(95)<2000"],
    "http_req_failed": ["rate<0.05"],
  },
  summaryTrendStats: ["avg", "med", "p(95)", "p(99)", "max"],
};

function login() {
  return http.post(`${BASE}/persons/login`,
    JSON.stringify({ email: __ENV.EMAIL, password: __ENV.PASSWORD }),
    { headers: JSON_HEADERS, tags: { tipo: "login" } });
}

export function setup() {
  const res = login();
  if (res.status !== 200) throw new Error(`login respondio ${res.status}`);
  return { token: res.json("token") };
}

export default function (data) {
  const roll = Math.random() * 100;
  if (roll < 40) {
    const res = login();
    check(res, { "login 200": r => r.status === 200 && !!r.json("token") });
  } else if (roll < 40 + WRITES) {
    const doc = `9${String(__VU).padStart(3, "0")}${String(__ITER).padStart(6, "0")}`;
    const body = {
      documentType: "CC",
      documentNumber: doc,
      firstName: "Carga",
      lastName: `K6 ${__VU}-${__ITER}`,
      email: `carga.k6.${RUN}.${__VU}.${__ITER}@ucopet.com`,
      admin: false,
      active: true,
    };
    const res = http.post(`${BASE}/persons`, JSON.stringify(body), {
      headers: { ...JSON_HEADERS, Authorization: `Bearer ${data.token}` }, tags: { tipo: "escritura" },
    });
    check(res, { "alta 201": r => r.status === 201 });
  } else {
    const path = Math.random() < 0.5 ? "/persons/me" : "/persons/document-types";
    const res = http.get(`${BASE}${path}`, {
      headers: { Authorization: `Bearer ${data.token}` }, tags: { tipo: "lectura" },
    });
    check(res, { "lectura 200": r => r.status === 200 });
  }
  sleep(0.5 + Math.random());
}

function ms(metric, stat) {
  const v = metric && metric.values ? metric.values[stat] : undefined;
  return v === undefined ? "-" : `${Math.round(v)} ms`;
}

export function handleSummary(d) {
  const m = d.metrics;
  const reqs = m.http_reqs ? m.http_reqs.values : { count: 0, rate: 0 };
  const failed = m.http_req_failed ? m.http_req_failed.values.rate * 100 : 0;
  const rows = [
    ["Login (BCrypt + notificacion por el bus)", m["http_req_duration{tipo:login}"]],
    ["Lecturas con token", m["http_req_duration{tipo:lectura}"]],
    ["Altas de persona (por el bus)", m["http_req_duration{tipo:escritura}"]],
  ].map(([name, t]) => `| ${name} | ${ms(t, "med")} | ${ms(t, "p(95)")} | ${ms(t, "p(99)")} | ${ms(t, "max")} |`);
  const passed = Object.values(d.metrics).filter(v => v.thresholds)
    .every(v => Object.values(v.thresholds).every(t => t.ok));
  const md = [
    `### Carga del login ${RUN}`,
    "",
    `- **Peticiones:** ${reqs.count} (${reqs.rate.toFixed(1)} por segundo)`,
    `- **Fallidas:** ${failed.toFixed(2)} %`,
    `- **Usuarios simultaneos:** hasta ${__ENV.VUS}, 40 % logins, ${WRITES} % altas de persona, ${__ENV.MINUTOS} min`,
    `- **Umbrales** (p95 < 2 s y menos de 5 % de fallas): ${passed ? "cumplidos" : "NO cumplidos"}`,
    "",
    "| Tipo | Mediana | p95 | p99 | Maximo |",
    "|---|---|---|---|---|",
    ...rows,
    "",
  ].join("\n");
  return { "resumen.md": md, stdout: md + "\n" };
}
