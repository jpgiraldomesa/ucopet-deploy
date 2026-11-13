#!/bin/sh
# Carga la semilla de seed/ en la base de un entorno. Se puede correr las veces que sea:
# cada fila tiene un id fijo y "on conflict do nothing", asi que no pisa lo que cambie el equipo.
# Cada archivo corre en su propia transaccion y solo si existen sus tablas: si la rama
# todavia no tiene esas tablas (main hoy), ese archivo se salta.
# Uso: scripts/seed.sh <main|develop>   (necesita TEAM_PASSWORD en el entorno)
env=$1
here=$(cd "$(dirname "$0")/.." && pwd)
db="ucopet_$env"
psql() { docker exec -i postgres psql -U ucopet -d "$db" "$@"; }

tables_exist() {
  for t in "$@"; do
    [ "$(psql -tAc "select to_regclass('public.$t') is not null")" = t ] || return 1
  done
}

if [ "$(docker inspect -f '{{.State.Running}}' "ucopet-$env-api" 2>/dev/null)" != true ]; then
  echo "semilla $env: la API no esta corriendo, se salta"; exit 0
fi

i=0
until tables_exist persons headquarter products; do
  i=$((i + 1))
  [ $i -ge 36 ] && { echo "semilla $env: la API no creo las tablas en 3 minutos, se salta"; exit 0; }
  sleep 5
done

docker exec postgres sh -c "rm -rf /tmp/seed && mkdir -p /tmp/seed"
for f in "$here"/seed/*; do docker exec -i postgres sh -c "cat > /tmp/seed/$(basename "$f")" < "$f"; done

clave=$(docker run --rm httpd:2.4-alpine htpasswd -bnBC 10 "" "$TEAM_PASSWORD" | tr -d ':\n')

run() {
  file=$1; shift
  if ! tables_exist "$@"; then echo "semilla $env: $file se salta, faltan tablas"; return; fi
  if psql -q -v ON_ERROR_STOP=1 -v clave="$clave" -1 -f "/tmp/seed/$file" >/dev/null; then
    echo "semilla $env: $file ok"
  else
    echo "semilla $env: $file fallo, el esquema de la rama ya no coincide"
  fi
}

run 10-sedes.sql headquarter
run 20-catalogo.sql products services service_headquarters stocks stock_movements headquarter
run 30-personas.sql persons doctors
run 40-restricciones.sql notifications providers
