#!/bin/sh
# Imprime la version de Node con la que compila el front que esta en $1.
# Angular 17 o mas nuevo -> 24; anterior -> 16 (Angular 13 no corre en Node moderno).
major=$(sed -n 's/.*"@angular\/core": *"[^0-9]*\([0-9]*\).*/\1/p' "$1/package.json" | head -1)
if [ "${major:-0}" -ge 17 ]; then echo 24; else echo 16; fi
