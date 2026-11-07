import http from "k6/http";
import { check, sleep } from "k6";

const BASE = __ENV.BASE;
const WRITES = Number(__ENV.ESCRITURAS || 30);
const RUN = __ENV.RUN || "local";
const VUS = Number(__ENV.VUS || 5);
const SECONDS = Number(__ENV.MINUTOS || 1) * 60;
const SERIAL = String(Math.floor(Date.now() / 1000) % 100000).padStart(5, "0");
const ROUTES = ["lectura", "producto", "servicio", "persona", "proveedor", "espacio"];

const thresholds = {
  http_req_failed: [{ threshold: "rate<0.2", abortOnFail: true, delayAbortEval: "20s" }],
};
ROUTES.forEach(r => { thresholds[`http_req_duration{ruta:${r}}`] = ["p(95)<5000"]; });

export const options = {
  scenarios: {
    presion: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "15s", target: VUS },
        { duration: `${Math.max(1, SECONDS - 25)}s`, target: VUS },
        { duration: "10s", target: 0 },
      ],
    },
  },
  thresholds,
  summaryTrendStats: ["med", "p(95)", "max"],
};

export function setup() {
  const res = http.post(`${BASE}/persons/login`,
    JSON.stringify({ email: __ENV.EMAIL, password: __ENV.PASSWORD }),
    { headers: { "Content-Type": "application/json" }, tags: { ruta: "login" } });
  if (res.status !== 200) throw new Error(`login respondio ${res.status}`);
  const token = res.json("token");
  const headquarters = http.get(`${BASE}/headquarter`, { headers: { Authorization: `Bearer ${token}` } }).json();
  return { token, headquarter: headquarters[0].id };
}

function serial() {
  return `7${SERIAL}${String(__VU).padStart(3, "0")}${String(__ITER).padStart(5, "0")}`;
}

const BUILDERS = {
  producto: () => ["products", {
    name: `Presion k6 ${RUN} ${__VU}-${__ITER}`, description: "Se borra al terminar", price: 1000,
    taxCategory: "STANDARD", sellable: true, active: true, category: "SUPPLY",
  }],
  servicio: () => ["services", {
    name: `Presion k6 ${RUN} ${__VU}-${__ITER}`, description: "Se borra al terminar", price: 1000,
    taxCategory: "STANDARD", sellable: true, active: true, category: "GENERAL", purchasable: false,
  }],
  persona: () => ["persons", {
    documentType: "CC", documentNumber: serial(), firstName: "Presion", lastName: `K6 ${__VU}-${__ITER}`,
    email: `presion.k6.${RUN}.${__VU}.${__ITER}@ucopet.com`, admin: false, active: true,
  }],
  proveedor: () => ["providers", {
    providerName: `Presion k6 ${RUN} ${__VU}-${__ITER}`, representName: "Presion k6", idType: "CC",
    documentNumber: serial(), mobileNumber: "3001234567", address: "Rionegro",
    email: `presion.k6.${RUN}.p${__VU}.${__ITER}@ucopet.com`, isActive: true,
  }],
  espacio: data => ["spaces", {
    code: `PKS-${String(__VU).padStart(3, "0")}${String(__ITER % 1000).padStart(3, "0")}`, type: "CONSULTORIO",
    description: `Presion k6 ${RUN}`, active: true, headquarterId: data.headquarter,
  }],
};

const READS = ["catalog", "products", "services", "headquarter"];

export default function (data) {
  const headers = { Authorization: `Bearer ${data.token}`, "Content-Type": "application/json" };
  if (Math.random() * 100 < WRITES) {
    const route = ROUTES[1 + Math.floor(Math.random() * (ROUTES.length - 1))];
    const [path, body] = BUILDERS[route](data);
    const res = http.post(`${BASE}/${path}`, JSON.stringify(body), { headers, tags: { ruta: route } });
    check(res, { [`${route} guardado`]: r => r.status >= 200 && r.status < 300 });
  } else {
    const path = READS[Math.floor(Math.random() * READS.length)];
    const res = http.get(`${BASE}/${path}`, { headers, tags: { ruta: "lectura" } });
    check(res, { "lectura 200": r => r.status === 200 });
  }
  sleep(0.5 + Math.random());
}

function ms(metric, stat) {
  const v = metric && metric.values ? metric.values[stat] : undefined;
  return v === undefined || !metric.values.max ? "-" : `${Math.round(v)} ms`;
}

export function handleSummary(d) {
  const reqs = d.metrics.http_reqs ? d.metrics.http_reqs.values : { count: 0, rate: 0 };
  const failed = d.metrics.http_req_failed ? d.metrics.http_req_failed.values.rate * 100 : 0;
  const rows = ROUTES.map(r => {
    const t = d.metrics[`http_req_duration{ruta:${r}}`];
    return `| ${r} | ${ms(t, "med")} | ${ms(t, "p(95)")} | ${ms(t, "max")} |`;
  });
  const fails = (d.root_group.checks || []).filter(c => c.fails > 0).map(c => `- ${c.name}: ${c.fails} fallas de ${c.passes + c.fails}`);
  const md = [
    `### Presion ${RUN}: ${VUS} usuarios, ${__ENV.MINUTOS} min, ${WRITES} % escrituras`,
    `- Peticiones: ${reqs.count} (${reqs.rate.toFixed(1)} por segundo)`,
    `- Fallidas: ${failed.toFixed(2)} %`,
    ...fails,
    "",
    "| Ruta | Mediana | p95 | Maximo |",
    "|---|---|---|---|",
    ...rows,
    "",
  ].join("\n");
  return { stdout: md };
}
