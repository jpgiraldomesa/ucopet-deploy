import http from "k6/http";
import { check, sleep } from "k6";

const BASE = __ENV.BASE;
const WRITES = Number(__ENV.ESCRITURAS || 10);
const RUN = __ENV.RUN || "local";

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
    "http_req_duration{tipo:lectura}": ["p(95)<2000"],
    "http_req_duration{tipo:escritura}": ["p(95)<2000"],
    "http_req_failed": ["rate<0.05"],
  },
  summaryTrendStats: ["avg", "med", "p(95)", "p(99)", "max"],
};

export function setup() {
  const res = http.post(`${BASE}/persons/login`,
    JSON.stringify({ email: __ENV.EMAIL, password: __ENV.PASSWORD }),
    { headers: { "Content-Type": "application/json" }, tags: { tipo: "login" } });
  if (res.status !== 200) throw new Error(`login respondio ${res.status}`);
  const token = res.json("token");
  const auth = { headers: { Authorization: `Bearer ${token}` } };
  const products = http.get(`${BASE}/products`, auth).json().map(p => p.id);
  return { token, products };
}

const READS = ["catalog", "products", "services", "headquarter", "product"];

export default function (data) {
  const params = { headers: { Authorization: `Bearer ${data.token}`, "Content-Type": "application/json" } };
  if (Math.random() * 100 < WRITES) {
    const body = {
      name: `Carga k6 ${RUN} ${__VU}-${__ITER}`,
      description: "Creado por la prueba de carga; se borra al terminar",
      price: 1000 + Math.round(Math.random() * 90000),
      taxCategory: "STANDARD",
      sellable: true,
      active: true,
      category: "SUPPLY",
    };
    const res = http.post(`${BASE}/products`, JSON.stringify(body), { ...params, tags: { tipo: "escritura", ruta: "POST products" } });
    check(res, { "escritura 201": r => r.status === 201 });
  } else {
    const what = READS[Math.floor(Math.random() * READS.length)];
    const url = what === "product" && data.products.length
      ? `${BASE}/products/${data.products[Math.floor(Math.random() * data.products.length)]}`
      : `${BASE}/${what === "product" ? "products" : what}`;
    const res = http.get(url, { ...params, tags: { tipo: "lectura", ruta: `GET ${what}` } });
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
  const rows = [["Lecturas", m["http_req_duration{tipo:lectura}"]], ["Escrituras", m["http_req_duration{tipo:escritura}"]]]
    .map(([name, t]) => `| ${name} | ${ms(t, "med")} | ${ms(t, "p(95)")} | ${ms(t, "p(99)")} | ${ms(t, "max")} |`);
  const passed = Object.entries(d.metrics).filter(([k, v]) => v.thresholds)
    .every(([, v]) => Object.values(v.thresholds).every(t => t.ok));
  const md = [
    `### Carga ${RUN}`,
    "",
    `- **Peticiones:** ${reqs.count} (${reqs.rate.toFixed(1)} por segundo)`,
    `- **Fallidas:** ${failed.toFixed(2)} %`,
    `- **Usuarios simultáneos:** hasta ${__ENV.VUS}, ${__ENV.ESCRITURAS} % escrituras, ${__ENV.MINUTOS} min`,
    `- **Umbrales** (p95 < 2 s y menos de 5 % de fallas): ${passed ? "cumplidos" : "NO cumplidos"}`,
    "",
    "| Tipo | Mediana | p95 | p99 | Máximo |",
    "|---|---|---|---|---|",
    ...rows,
    "",
  ].join("\n");
  return { "resumen.md": md, stdout: md + "\n" };
}
