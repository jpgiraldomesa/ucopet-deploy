#!/bin/sh
# Construye en esta maquina la imagen de un servicio a partir de un clon de su repo.
# Uso: scripts/build-local.sh <servicio> <carpeta-del-repo> <entorno>
# Ejemplo: scripts/build-local.sh api ../src/ucopetapi-develop develop
set -e
svc=$1; src=$2; env=$3
here=$(cd "$(dirname "$0")/.." && pwd)
registry=${REGISTRY:-ghcr.io/jpgiraldomesa}

if [ "$svc" = front ]; then
  docker build -f "$here/docker/front.Dockerfile" \
    --build-arg NODE_VERSION="$("$here/scripts/node-version.sh" "$src")" \
    --build-context config="$here/docker" \
    -t "$registry/ucopet-front:$env" "$src"
else
  docker build -f "$here/docker/spring.Dockerfile" -t "$registry/ucopet-$svc:$env" "$src"
fi
