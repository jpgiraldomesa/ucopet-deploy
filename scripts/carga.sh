#!/bin/sh
# Corre en la VM, llamado por el workflow carga.
#   scripts/carga.sh inicio <entorno> <minutos> <usuarios> <escrituras> <quien> <modulo> <url-de-la-ejecucion>
#     Revisa que el entorno este arriba y deja status/carga-<entorno>.json para la pagina de estado.
#   scripts/carga.sh fin <entorno> <id-de-la-ejecucion> <modulo>
#     Espera a que el procesador termine con lo que quedo en la cola, borra lo que creo la prueba
#     (catalogo: productos "Carga k6 <id> ..."; login: personas carga.k6.<id>.* y las notificaciones
#     de sus inicios de sesion) y marca la hora real de fin.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
action=$1; env=$2
case "$env" in develop|pruebas) ;; *) echo "entorno: develop o pruebas"; exit 1 ;; esac
meta="$here/status/carga-$env.json"

case "$action" in
  inicio)
    minutes=$3; vus=$4; writes=$5; who=$6; module=${7:-catalogo}; url=$8
    if [ -f "$here/status/apagado-$env" ]; then echo "$env esta apagado"; exit 1; fi
    if [ "$(docker inspect -f '{{.State.Running}}' "ucopet-$env-api" 2>/dev/null)" != true ]; then
      echo "la API de $env no esta corriendo"; exit 1
    fi
    python3 - "$meta" "$who" "$minutes" "$vus" "$writes" "$module" "$url" <<'EOF'
import datetime, json, sys
path, who, minutes, vus, writes, module, url = sys.argv[1:]
now = datetime.datetime.now(datetime.timezone.utc)
json.dump({"by": who, "desde": now.isoformat(timespec="seconds"),
           "hasta": (now + datetime.timedelta(minutes=int(minutes))).isoformat(timespec="seconds"),
           "minutos": int(minutes), "vus": int(vus), "escrituras": int(writes), "modulo": module,
           "run_url": url},
          open(path, "w"))
EOF
    ;;
  fin)
    run=$3; module=${4:-catalogo}
    if [ "$module" = login ]; then queue='person\.create'; else queue='inventory\.product\.save'; fi
    for i in $(seq 1 30); do
      left=$(docker exec rabbit rabbitmqctl -q list_queues -p "$env" name messages \
        | awk -v q="$queue" '$1 ~ q {s += $2} END {print s + 0}')
      [ "${left:-0}" = 0 ] && break
      sleep 2
    done
    if [ "$module" = login ]; then
      since=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['desde'])" "$meta" 2>/dev/null \
        || date -u +%FT%TZ)
      docker exec -i postgres psql -U ucopet -d "ucopet_$env" -v ON_ERROR_STOP=1 -q <<SQL
begin;
delete from persons where email like 'carga.k6.$run.%';
delete from notifications where type = 'LOGIN_SUCCEDED'
  and person_id = (select id from persons where email = 'pablogiraldo@ucopet.com')
  and created_at >= ('$since'::timestamptz at time zone 'America/Bogota');
commit;
SQL
    else
      docker exec -i postgres psql -U ucopet -d "ucopet_$env" -v ON_ERROR_STOP=1 -q <<SQL
begin;
delete from stock_movements where product_id in (select id from products where name like 'Carga k6 $run %');
delete from stocks where product_id in (select id from products where name like 'Carga k6 $run %');
delete from products where name like 'Carga k6 $run %';
commit;
SQL
    fi
    python3 - "$meta" <<'EOF'
import datetime, json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except (OSError, ValueError):
    sys.exit(0)
now = datetime.datetime.now(datetime.timezone.utc)
if datetime.datetime.fromisoformat(data["hasta"]) > now:
    data["hasta"] = now.isoformat(timespec="seconds")
json.dump(data, open(path, "w"))
EOF
    echo "datos de la prueba ($module) borrados de ucopet_$env"
    ;;
  *) echo "accion: inicio o fin"; exit 1 ;;
esac
"$here/scripts/status.py" || true
