#!/bin/bash
# Corre en GitHub Actions. Mira el ultimo commit de main y develop en cada repo
# y arma la lista de imagenes que no existen todavia en GHCR.
# Salidas: matrix (lo que hay que construir) y envs (los entornos a desplegar).
set -euo pipefail
registry=${REGISTRY:-ghcr.io/jpgiraldomesa}
force=${FORCE:-false}
items=()
envs=()

while read -r svc repo; do
  [ -z "$svc" ] && continue
  for env in main develop; do
    sha=$(git ls-remote "https://github.com/$repo.git" "refs/heads/$env" | cut -f1)
    [ -z "$sha" ] && { echo "$repo no tiene $env"; continue; }
    tag="$env-${sha:0:12}"
    if [ "$force" != true ] && docker manifest inspect "$registry/ucopet-$svc:$tag" >/dev/null 2>&1; then
      echo "al dia   $svc:$env ($tag)"
      continue
    fi
    if [ "$force" != true ] && docker manifest inspect "$registry/ucopet-$svc:failed-$tag" >/dev/null 2>&1; then
      echo "fallo    $svc:$env ($tag) no compila; se reintenta con el proximo commit"
      continue
    fi
    echo "cambio   $svc:$env ($tag)"
    items+=("{\"svc\":\"$svc\",\"repo\":\"$repo\",\"env\":\"$env\",\"sha\":\"$sha\",\"tag\":\"$tag\"}")
    envs+=("\"$env\"")
  done
done < services.txt

if [ "${DEPLOY_ALL:-false}" = true ]; then envs+=('"main"' '"develop"'); fi

join() { local IFS=,; echo "$*"; }
matrix="{\"include\":[$(join "${items[@]}")]}"
uniq_envs="[$(printf '%s\n' "${envs[@]}" | grep . | sort -u | paste -sd, - || true)]"
echo "matrix=$matrix" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "envs=$uniq_envs" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "builds=${#items[@]}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
