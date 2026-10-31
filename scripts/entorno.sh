#!/bin/sh
# Corre en la VM. Apaga o prende un entorno entero (sus siete contenedores).
# Uso: scripts/entorno.sh <main|develop|pruebas> <apagar|encender> [quien]
# Apagar deja la marca status/apagado-<entorno>: deploy.sh lo salta y la pagina de estado lo muestra.
# La base y el vhost no se tocan: al prenderlo vuelve con sus datos.
set -e
env=$1; action=$2; who=${3:-alguien}
case "$env" in main|develop|pruebas) ;; *) echo "uso: $0 <main|develop|pruebas> <apagar|encender>"; exit 1 ;; esac
here=$(cd "$(dirname "$0")/.." && pwd)
mark="$here/status/apagado-$env"
mkdir -p "$here/status"

case "$action" in
  apagar)
    printf '{"by": "%s", "at": "%s"}\n' "$who" "$(date -u +%FT%TZ)" > "$mark"
    ENV="$env" REGISTRY="${REGISTRY:-ghcr.io/jpgiraldomesa}" docker compose -f "$here/app/compose.yml" stop
    ;;
  encender)
    rm -f "$mark"
    "$here/scripts/deploy.sh" "$env"
    ;;
  *) echo "accion: apagar o encender"; exit 1 ;;
esac

"$here/scripts/status.py" || true
