import http from "k6/http";
import { check, sleep } from "k6";

const BASE = __ENV.BASE;
const RUN = __ENV.RUN || "local";
const VUS = Number(__ENV.VUS || 6);
const SECONDS = Number(__ENV.MINUTOS || 1) * 60;
const PER = Math.max(1, Math.round(VUS / 6));
const SERIAL = String(Math.floor(Date.now() / 1000) % 100000).padStart(5, "0");
const PROCESSORS = ["usuarios", "comercial", "salud", "inventario", "pagos", "lecturas"];

function scenario(exec) {
  return {
    executor: "ramping-vus",
    exec,
    startVUs: 0,
    stages: [
      { duration: "15s", target: PER },
      { duration: `${Math.max(1, SECONDS - 25)}s`, target: PER },
      { duration: "10s", target: 0 },
    ],
  };
}

const thresholds = {
  http_req_failed: [{ threshold: "rate<0.2", abortOnFail: true, delayAbortEval: "30s" }],
};
PROCESSORS.forEach(p => { thresholds[`http_req_duration{procesador:${p}}`] = ["p(95)<5000"]; });

export const options = {
  scenarios: Object.fromEntries(PROCESSORS.map(p => [p, scenario(p)])),
  thresholds,
  summaryTrendStats: ["med", "p(95)", "max"],
};

function list(res) {
  const body = res.json();
  return Array.isArray(body) ? body : (body && (body.content || body.data)) || [];
}

export function setup() {
  const login = http.post(`${BASE}/persons/login`,
    JSON.stringify({ email: __ENV.EMAIL, password: __ENV.PASSWORD }),
    { headers: { "Content-Type": "application/json" } });
  if (login.status !== 200) throw new Error(`login respondio ${login.status}`);
  const token = login.json("token");
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  const headquarters = list(http.get(`${BASE}/headquarter`, { headers })).filter(h => h.isActive !== false);
  const headquarter = headquarters[0].id;

  const product = http.post(`${BASE}/products`, JSON.stringify({
    name: `Carga ${RUN} stock`, description: "Se borra al terminar", price: 1000,
    taxCategory: "STANDARD", sellable: true, active: true, category: "SUPPLY",
  }), { headers });
  const productId = product.status < 300 ? product.json("id") : null;
  for (let i = 0; productId && i < 20 && http.get(`${BASE}/products/${productId}`, { headers }).status !== 200; i++) sleep(0.5);

  const tutors = list(http.get(`${BASE}/tutorPet`, { headers }));
  let tutorId = null, petId = null;
  for (const h of headquarters) {
    const pet = list(http.get(`${BASE}/pets?headquarterId=${h.id}`, { headers }))
      .find(p => tutors.some(t => t.id === p.tutorId));
    if (pet) { tutorId = pet.tutorId; petId = pet.id; break; }
  }
  const payMethods = list(http.get(`${BASE}/PayMethods`, { headers }));
  return { token, headquarter, productId, tutorId, petId, payMethodId: payMethods.length ? payMethods[0].id : null };
}

function serial() {
  return `8${SERIAL}${String(__VU).padStart(3, "0")}${String(__ITER).padStart(5, "0")}`;
}

function post(data, path, body, processor) {
  const headers = { Authorization: `Bearer ${data.token}`, "Content-Type": "application/json" };
  const res = http.post(`${BASE}/${path}`, JSON.stringify(body), { headers, tags: { procesador: processor } });
  check(res, { [`${processor} aceptado`]: r => r.status >= 200 && r.status < 300 });
  sleep(0.5 + Math.random());
}

export function usuarios(data) {
  post(data, "persons", {
    documentType: "CC", documentNumber: serial(), firstName: "Carga", lastName: `${RUN} ${__VU}-${__ITER}`,
    email: `carga.${RUN}.${__VU}.${__ITER}@ucopet.com`, admin: false, active: true,
  }, "usuarios");
}

export function comercial(data) {
  post(data, "providers", {
    providerName: `Carga ${RUN} ${__VU}-${__ITER}`, representName: "Carga", idType: "CC",
    documentNumber: serial(), mobileNumber: "3001234567", address: "Rionegro",
    email: `carga.${RUN}.p${__VU}.${__ITER}@ucopet.com`, isActive: true,
  }, "comercial");
}

export function salud(data) {
  post(data, "spaces", {
    code: `CKS-${String(__VU).padStart(2, "0")}${String(__ITER % 10000).padStart(4, "0")}`, type: "Consultorio",
    description: `Carga ${RUN} consultorio de prueba`, active: true, headquarterId: data.headquarter,
  }, "salud");
}

export function inventario(data) {
  if (data.productId && __ITER % 2 === 1) {
    post(data, "stock/adjust", {
      productId: data.productId, headquarterId: data.headquarter, quantity: 1, reason: "PURCHASE",
      note: `Carga ${RUN}`,
    }, "inventario");
    return;
  }
  post(data, "products", {
    name: `Carga ${RUN} ${__VU}-${__ITER}`, description: "Se borra al terminar", price: 1000,
    taxCategory: "STANDARD", sellable: true, active: true, category: "SUPPLY",
  }, "inventario");
}

export function pagos(data) {
  if (!data.tutorId || !data.payMethodId) { sleep(5); return; }
  post(data, "receipts", {
    tutorId: data.tutorId, petId: data.petId, concept: `Carga ${RUN} ${__VU}-${__ITER}`,
    amount: 1000, payMethodId: data.payMethodId,
  }, "pagos");
}

const READS = ["catalog", "persons", "providers", "spaces", "receipts", "headquarter"];

export function lecturas(data) {
  const headers = { Authorization: `Bearer ${data.token}` };
  const path = READS[Math.floor(Math.random() * READS.length)];
  const res = http.get(`${BASE}/${path}`, { headers, tags: { procesador: "lecturas" } });
  check(res, { "lectura 200": r => r.status === 200 });
  sleep(0.3 + Math.random() / 2);
}

function ms(metric, stat) {
  const v = metric && metric.values ? metric.values[stat] : undefined;
  return v === undefined || !metric.values.max ? "-" : `${Math.round(v)} ms`;
}

export function handleSummary(d) {
  const reqs = d.metrics.http_reqs ? d.metrics.http_reqs.values : { count: 0, rate: 0 };
  const failed = d.metrics.http_req_failed ? d.metrics.http_req_failed.values.rate * 100 : 0;
  const names = { usuarios: "Usuarios (personas)", comercial: "Comercial (proveedores)", salud: "Salud (espacios)",
    inventario: "Inventario (productos y stock)", pagos: "Pagos (recibos de caja)", lecturas: "Lecturas" };
  const rows = PROCESSORS.map(p => {
    const t = d.metrics[`http_req_duration{procesador:${p}}`];
    return `| ${names[p]} | ${ms(t, "med")} | ${ms(t, "p(95)")} | ${ms(t, "max")} |`;
  });
  const fails = (d.root_group.checks || []).filter(c => c.fails > 0).map(c => `- ${c.name}: ${c.fails} fallas de ${c.passes + c.fails}`);
  const md = [
    `### Carga de todos los procesadores ${RUN}`,
    "",
    `- **Usuarios simultaneos:** hasta ${PER * PROCESSORS.length} (${PER} por procesador y ${PER} leyendo), ${__ENV.MINUTOS} min`,
    `- **Peticiones:** ${reqs.count} (${reqs.rate.toFixed(1)} por segundo)`,
    `- **Fallidas:** ${failed.toFixed(2)} %`,
    ...fails,
    "",
    "| Procesador | Mediana | p95 | Maximo |",
    "|---|---|---|---|",
    ...rows,
    "",
  ].join("\n");
  return { stdout: md, "resumen.md": md };
}
