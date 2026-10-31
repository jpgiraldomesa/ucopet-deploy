#!/bin/sh
# Corre en la VM a las 04:50 UTC (11:50 pm en Colombia), antes del apagado de las 12.
# Vuelca las dos bases y guarda una copia por dia de la semana: quedan las ultimas 7.
# Restaurar: gunzip -c /opt/ucopet/backups/<dia>.sql.gz | docker exec -i postgres psql -U ucopet -d postgres
set -e
dir=/opt/ucopet/backups
mkdir -p "$dir"
day=$(date -u +%a)
docker exec postgres pg_dumpall -U ucopet --clean --if-exists | gzip > "$dir/$day.sql.gz.tmp"
mv "$dir/$day.sql.gz.tmp" "$dir/$day.sql.gz"
