#!/bin/sh
# Corre en la VM. Levanta la infraestructura compartida y actualiza un entorno.
# Uso: scripts/deploy.sh <main|develop>
# Lee los secretos de /opt/ucopet/secrets.env (no esta en el repo).
set -e
env=$1
case "$env" in main|develop) ;; *) echo "uso: $0 <main|develop>"; exit 1 ;; esac

here=$(cd "$(dirname "$0")/.." && pwd)
secrets=${SECRETS:-/opt/ucopet/secrets.env}
set -a; . "$secrets"; set +a
export ENV="$env" REGISTRY="${REGISTRY:-ghcr.io/jpgiraldomesa}"
if [ "$env" = main ]; then
  export JWT_SECRET="$JWT_SECRET_MAIN" PUBLIC_URL="https://$DOMAIN"
else
  export JWT_SECRET="$JWT_SECRET_DEVELOP" PUBLIC_URL="https://$DOMAIN:8443"
fi

docker compose -f "$here/infra/compose.yml" --env-file "$secrets" up -d --wait

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
docker compose -f "$here/app/compose.yml" up -d --remove-orphans api
i=0
since=$(docker inspect -f '{{.State.StartedAt}}' "ucopet-$env-api")
until docker logs --since "$since" "ucopet-$env-api" 2>&1 | grep -q "Started "; do
  i=$((i + 1)); [ $i -ge 24 ] && { echo "la API de $env no arranco en 2 minutos; sigo igual"; break; }
  sleep 5
done
docker compose -f "$here/app/compose.yml" up -d --remove-orphans
docker image prune -f >/dev/null

"$here/scripts/seed.sh" "$env"
