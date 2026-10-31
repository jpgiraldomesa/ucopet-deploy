#!/bin/sh
# Corre en la VM. Levanta la infraestructura compartida y actualiza un entorno.
# Uso: scripts/deploy.sh <main|develop|pruebas>
# Lee los secretos de /opt/ucopet/secrets.env (no esta en el repo).
# Para pruebas: CLEAN=true borra su base y su vhost antes, y PRUEBAS_META (JSON en base64)
# dice quien lo cargo y con que ramas; queda en status/pruebas.json para la pagina de estado.
set -e
env=$1
case "$env" in
  main) port="" ;;
  develop) port=":8443" ;;
  pruebas) port=":9443" ;;
  *) echo "uso: $0 <main|develop|pruebas>"; exit 1 ;;
esac

here=$(cd "$(dirname "$0")/.." && pwd)
secrets=${SECRETS:-/opt/ucopet/secrets.env}
jwt_var="JWT_SECRET_$(echo "$env" | tr a-z A-Z)"
if ! grep -q "^$jwt_var=" "$secrets"; then
  echo "$jwt_var=$(openssl rand -base64 64 | tr -d '/+=\n' | cut -c1-64)" >> "$secrets"
fi
set -a; . "$secrets"; set +a
export ENV="$env" REGISTRY="${REGISTRY:-ghcr.io/jpgiraldomesa}"
export JWT_SECRET="$(eval echo "\$$jwt_var")" PUBLIC_URL="https://$DOMAIN$port"

mkdir -p "$here/status"
docker compose -f "$here/infra/compose.yml" --env-file "$secrets" up -d --wait
docker exec caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true

status_job="* * * * * $here/scripts/status.py >/dev/null 2>&1"
backup_job="50 4 * * * $here/scripts/backup.sh >/dev/null 2>&1"
watch_job="*/5 * * * * $here/scripts/watch.sh >/dev/null 2>&1"
{ crontab -l 2>/dev/null | grep -vE 'scripts/(status.py|backup.sh|watch.sh)' || true
  echo "$status_job"; echo "$backup_job"; echo "$watch_job"; } | crontab -

if [ -f "$here/status/apagado-$env" ]; then
  echo "$env esta apagado a proposito (scripts/entorno.sh $env encender para prenderlo); no se despliega"
  exit 0
fi

if [ "$env" = pruebas ] && [ "${CLEAN:-false}" = true ]; then
  docker compose -f "$here/app/compose.yml" down
  docker exec postgres dropdb -U ucopet --if-exists --force ucopet_pruebas
  docker exec rabbit rabbitmqctl -q delete_vhost pruebas 2>/dev/null || true
fi

if ! docker exec postgres psql -U ucopet -d postgres -tAc "select 1 from pg_database where datname='ucopet_$env'" | grep -q 1; then
  docker exec postgres createdb -U ucopet "ucopet_$env"
fi

if ! docker exec rabbit rabbitmqctl -q list_vhosts | grep -qx "$env"; then
  docker exec rabbit rabbitmqctl add_vhost "$env"
  docker exec rabbit rabbitmqctl set_permissions -p "$env" ucopet '.*' '.*' '.*'
fi
sed "s#\"vhost\": *\"/\"#\"vhost\": \"$env\"#g" "$here/infra/rabbit-topology.json" | docker exec -i rabbit sh -c "cat > /tmp/topology-$env.json"
docker exec rabbit rabbitmqctl -q import_definitions "/tmp/topology-$env.json" >/dev/null

docker compose -f "$here/app/compose.yml" pull -q --ignore-pull-failures
"$here/scripts/topology.py" "$env" || echo "topologia $env: no se pudo declarar, sigo igual"
ready=""
for svc in $(docker compose -f "$here/app/compose.yml" config --services); do
  if docker image inspect "$REGISTRY/ucopet-$svc:$env" >/dev/null 2>&1; then
    ready="$ready $svc"
  else
    echo "$env: $svc no tiene imagen todavia (su rama no compila), se salta"
  fi
done

case " $ready " in
  *" api "*)
    docker compose -f "$here/app/compose.yml" up -d api
    i=0
    since=$(docker inspect -f '{{.State.StartedAt}}' "ucopet-$env-api")
    until docker logs --since "$since" "ucopet-$env-api" 2>&1 | grep -q "Started "; do
      i=$((i + 1)); [ $i -ge 24 ] && { echo "la API de $env no arranco en 2 minutos; sigo igual"; break; }
      sleep 5
    done
    ;;
esac
docker compose -f "$here/app/compose.yml" up -d --remove-orphans $ready
docker image prune -f >/dev/null

"$here/scripts/seed.sh" "$env"

if [ "$env" = pruebas ] && [ -n "${PRUEBAS_META:-}" ]; then
  echo "$PRUEBAS_META" | base64 -d > "$here/status/pruebas.json"
fi

"$here/scripts/status.py" || true
