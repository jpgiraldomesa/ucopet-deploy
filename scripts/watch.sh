#!/bin/sh
# Corre en la VM cada 5 minutos (cron). Mira el ultimo commit de main y develop en cada repo de
# services.txt y, si alguno cambio desde la ultima vez, lanza el workflow deploy en GitHub.
# Reemplaza al schedule de GitHub, que llega con horas de atraso. Solo corre con la VM prendida.
# Necesita GH_DISPATCH_TOKEN en /opt/ucopet/secrets.env: token fino con Actions de lectura y
# escritura, solo sobre jpgiraldomesa/ucopet-deploy.
here=$(cd "$(dirname "$0")/.." && pwd)
secrets=${SECRETS:-/opt/ucopet/secrets.env}
seen=/opt/ucopet/watch.seen
log=/opt/ucopet/watch.log
repo=jpgiraldomesa/ucopet-deploy

token=$(sed -n 's/^GH_DISPATCH_TOKEN=//p' "$secrets")
[ -z "$token" ] && exit 0

now=$(mktemp)
while read -r svc src; do
  [ -z "$svc" ] && continue
  for env in main develop; do
    [ -f "$here/status/apagado-$env" ] && continue
    sha=$(git ls-remote "https://github.com/$src.git" "refs/heads/$env" 2>/dev/null | cut -f1)
    [ -n "$sha" ] && echo "$svc $env $sha" >> "$now"
  done
done < "$here/services.txt"

if [ ! -s "$now" ]; then
  rm -f "$now"
  exit 0
fi

if [ -f "$seen" ]; then
  changed=$(grep -vxFf "$seen" "$now" || true)
else
  changed=$(cat "$now")
fi
if [ -z "$changed" ]; then
  rm -f "$now"
  exit 0
fi

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$repo/actions/workflows/deploy.yml/dispatches" \
  -d '{"ref":"main","inputs":{"force":"false","todos":"false"}}')

stamp=$(date -u +%FT%TZ)
if [ "$code" = 204 ]; then
  mv "$now" "$seen"
  echo "$changed" | sed "s/^/$stamp lanzado: /" >> "$log"
else
  rm -f "$now"
  echo "$stamp error $code al lanzar deploy" >> "$log"
fi
tail -n 300 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
