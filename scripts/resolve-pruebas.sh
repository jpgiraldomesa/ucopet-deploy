#!/bin/bash
# Corre en GitHub Actions para el entorno de pruebas. Recibe en BRANCHES el JSON del
# formulario (servicio -> rama), busca el commit de cada rama y decide:
#   - si ya hay imagen de ese commit (de develop, de main o de otra prueba), la reetiqueta :pruebas
#   - si no, la manda a construir.
# Primero valida todas las ramas: si una no existe, no toca nada.
# Salidas: matrix (lo que hay que construir), builds y meta (base64, para la pagina de estado).
set -euo pipefail
registry=${REGISTRY:-ghcr.io/jpgiraldomesa}
resolved=()
missing=()
meta_branches="{}"

while read -r svc repo; do
  [ -z "$svc" ] && continue
  branch=$(jq -r --arg s "$svc" '.[$s] // "develop"' <<< "$BRANCHES" | tr -d '[:space:]')
  [ -z "$branch" ] && branch=develop
  sha=$(git ls-remote "https://github.com/$repo.git" "refs/heads/$branch" | cut -f1)
  if [ -z "$sha" ]; then
    missing+=("$svc: la rama '$branch' no existe en $repo")
    continue
  fi
  resolved+=("$svc $repo $branch $sha")
  meta_branches=$(jq -c --arg s "$svc" --arg b "$branch" --arg h "$sha" --arg r "$repo" \
    '. + {($s): {branch: $b, sha: $h, repo: $r}}' <<< "$meta_branches")
done < services.txt

if [ ${#missing[@]} -gt 0 ]; then
  printf '%s\n' "${missing[@]}" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}" >&2
  exit 1
fi

items=()
for line in "${resolved[@]}"; do
  read -r svc repo branch sha <<< "$line"
  tag=${sha:0:12}
  found=""
  for candidate in "sha-$tag" "develop-$tag" "main-$tag"; do
    if docker manifest inspect "$registry/ucopet-$svc:$candidate" >/dev/null 2>&1; then
      found=$candidate
      break
    fi
  done
  if [ -n "$found" ]; then
    echo "reusa     $svc $branch ($tag) desde :$found"
    docker buildx imagetools create -t "$registry/ucopet-$svc:pruebas" "$registry/ucopet-$svc:$found" >/dev/null
  else
    echo "construye $svc $branch ($tag)"
    items+=("$(jq -nc --arg svc "$svc" --arg repo "$repo" --arg branch "$branch" --arg sha "$sha" --arg tag "$tag" \
      '{svc: $svc, repo: $repo, branch: $branch, sha: $sha, tag: $tag}')")
  fi
done

join() { local IFS=,; echo "$*"; }
meta=$(jq -nc --arg by "$ACTOR" --arg at "$(date -u +%FT%TZ)" --argjson clean "${CLEAN:-false}" \
  --argjson branches "$meta_branches" '{by: $by, at: $at, clean: $clean, branches: $branches}')
{
  echo "matrix={\"include\":[$(join "${items[@]+"${items[@]}"}")]}"
  echo "builds=${#items[@]}"
  echo "meta=$(base64 -w0 <<< "$meta")"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
