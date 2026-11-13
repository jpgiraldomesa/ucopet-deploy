#!/bin/bash
# Prueba de presion desde el Mac contra develop, con carga/presion.js (k6 en Docker).
# Uso: scripts/presion-local.sh <usuarios> <minutos> [escrituras]
# Escribe por la API hacia Inventario, Usuarios, Comercial y Salud; Pagos no entra porque un
# egreso exige una orden de compra real. k6 aborta si pasa de 20 % de fallas. Al terminar, o si
# se interrumpe, borra lo creado. Muestrea la pagina de estado cada 5 s e imprime los picos.
set -u
vus=${1:?usuarios}; minutes=${2:?minutos}; writes=${3:-30}
here=$(cd "$(dirname "$0")/.." && pwd)
domain=ucopet.westus2.cloudapp.azure.com
run="p$(date +%s)"
samples=$(mktemp)

cleanup() {
  [ -n "${sampler:-}" ] && kill "$sampler" 2>/dev/null
  ssh ucopet-vm "bash -s" <<EOF
for i in \$(seq 1 60); do
  left=\$(docker exec rabbit rabbitmqctl -q list_queues -p develop name messages | awk '{s += \$2} END {print s + 0}')
  [ "\$left" = 0 ] && break
  sleep 2
done
echo "mensajes sin procesar al limpiar: \$left"
docker exec -i postgres psql -U ucopet -d ucopet_develop -v ON_ERROR_STOP=1 -q <<'SQL'
begin;
delete from notifications where person_id in (select id from persons where email like 'presion.k6.$run.%');
delete from persons where email like 'presion.k6.$run.%';
delete from providers where provider_name like 'Presion k6 $run %';
delete from spaces where description = 'Presion k6 $run';
delete from service_headquarters where service_id in (select id from services where name like 'Presion k6 $run %');
delete from services where name like 'Presion k6 $run %';
delete from stock_movements where product_id in (select id from products where name like 'Presion k6 $run %');
delete from stocks where product_id in (select id from products where name like 'Presion k6 $run %');
delete from products where name like 'Presion k6 $run %';
commit;
SQL
echo "limpieza: \$?"
rm -f /opt/ucopet/deploy/status/carga-develop.json
EOF
  rm -f "$samples"
}
trap cleanup EXIT

password=$(ssh ucopet-vm "sed -n 's/^TEAM_PASSWORD=//p' /opt/ucopet/secrets.env")
hasta=$(date -u -v+"${minutes}"M +%FT%TZ)
ssh ucopet-vm "printf '{\"by\": \"presion desde el Mac\", \"desde\": \"%s\", \"hasta\": \"%s\", \"minutos\": $minutes, \"vus\": $vus, \"escrituras\": $writes}' \
  \"$(date -u +%FT%TZ)\" \"$hasta\" > /opt/ucopet/deploy/status/carga-develop.json"

( while :; do curl -s -m 4 "https://$domain/estado/estado.json" >> "$samples" && echo >> "$samples"; sleep 5; done ) &
sampler=$!

docker run --rm --user "$(id -u):$(id -g)" -v "$here/carga:/carga:ro" -w /carga \
  -e BASE="https://$domain:8443/api/v1" -e EMAIL=pablogiraldo@ucopet.com -e PASSWORD="$password" \
  -e VUS="$vus" -e MINUTOS="$minutes" -e ESCRITURAS="$writes" -e RUN="$run" \
  grafana/k6:1.8.2 run presion.js
echo "k6 termino con codigo $?"

python3 - "$samples" <<'PY'
import json, sys
peak, mem, restarts, waiting, rate = {}, {}, {}, 0, 0
first = {}
n = 0
for line in open(sys.argv[1]):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    n += 1
    e = d["envs"]["develop"]
    waiting = max(waiting, e["totals"]["messages"])
    rate = max(rate, e["totals"]["rate_in"])
    for s in e["services"] + d["infra"]:
        k = s.get("svc") or s["name"]
        peak[k] = max(peak.get(k, 0), s.get("cpu") or 0)
        mem[k] = max(mem.get(k, 0), s.get("mem_mb") or 0)
        first.setdefault(k, s.get("restarts") or 0)
        restarts[k] = (s.get("restarts") or 0) - first[k]
print(f"\n### Consumo en develop ({n} muestras). CPU en % de un nucleo; la VM tiene 2")
print(f"Pico de mensajes en espera: {waiting} · pico de entrada: {rate:.1f} por segundo")
print("| Pieza | CPU pico | RAM pico | Reinicios |\n|---|---|---|---|")
for k in sorted(peak, key=peak.get, reverse=True):
    print(f"| {k} | {peak[k]:.0f} % | {mem[k]} MB | {restarts[k]} |")
PY
