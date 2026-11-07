#!/bin/sh
# Corre en la VM: cron lo lanza cada minuto y durante 55 segundos recalcula el estado cada 5.
# Cron no baja de un minuto, y asi la pagina de estado va casi en vivo sin montar un servicio.
# flock evita que se encimen dos vueltas.
here=$(cd "$(dirname "$0")/.." && pwd)
end=$(($(date +%s) + 55))
while [ "$(date +%s)" -lt "$end" ]; do
  "$here/scripts/status.py"
  sleep 5
done
