# ucopet-deploy

Despliegue continuo de UcoPet en una VM de Azure. Construye `main` y `develop` de los siete repos
del equipo y los publica como dos entornos independientes. No toca los repos del equipo: los
Dockerfile y la configuracion viven aqui.

| Entorno | Rama | Direccion |
|---|---|---|
| main | `main` de cada repo | `https://<dominio>` |
| develop | `develop` de cada repo | `https://<dominio>:8443` |
| Rabbit (consola) | | `https://<dominio>:15671` |
| Estado | | `https://<dominio>/estado/` |

La pagina de estado muestra, por entorno, si cada pieza esta arriba, que commit corre y que colas
escucha cada procesador (que no tienen pantalla). La arma `scripts/status.py` cada minuto por cron
en la VM; escribe `status/estado.json` y Caddy lo sirve. No expone Docker ni la clave de Rabbit.

## Como funciona

1. Cada 15 minutos, GitHub Actions (`.github/workflows/deploy.yml`) mira el ultimo commit de `main`
   y `develop` en cada repo de `services.txt`.
2. Si la imagen de ese commit no existe en GHCR, la construye y la sube con dos etiquetas:
   `:<rama>` y `:<rama>-<commit>`.
3. Entra a la VM por SSH y corre `scripts/deploy.sh <rama>`, que baja las imagenes nuevas,
   arranca la API primero (crea las tablas) y despues el resto, y carga la semilla.

Si una rama no compila, ese servicio se queda con la imagen anterior y los demas siguen. El commit
roto queda marcado en GHCR (`:failed-<rama>-<commit>`) y no se reintenta hasta el proximo commit,
asi que llega un solo aviso por commit roto. El resumen de la ejecucion dice cual fue.

| Repo | Servicio |
|---|---|
| cristopherr26/ucopetapi | api |
| cristopherr26/Front-End-UcoPetApi | front |
| MontoyaVJuli/ucopet-commercial-processor | commercial |
| Michelgdr28/ucopet-health-processor | health |
| juliananaranjo/ucopet-payment-processor | payment |
| simongrisales/ucopet-user-processor | user |
| jpgiraldomesa/ucopet-inventory-processor | inventory |

## Piezas

| Archivo | Que hace |
|---|---|
| `docker/spring.Dockerfile` | compila con Gradle 9.8 y JDK 25 (no usa el wrapper del repo) y corre con JRE 25 |
| `docker/front.Dockerfile` | compila el Angular (Node 24, o 16 si el repo es Angular 13) y lo sirve con nginx |
| `docker/nginx.conf.template` | `/api/` va a la API de su mismo entorno; el resto cae en `index.html` |
| `infra/compose.yml` | lo compartido: Postgres, RabbitMQ y Caddy (HTTPS automatico) |
| `app/compose.yml` | un entorno: la API, los cinco procesadores y el front |
| `infra/rabbit-topology.json` | colas que ningun procesador declara solo (Salud), se importan en cada vhost |
| `seed/` | sedes, catalogo y cuentas del equipo; se puede correr las veces que sea |

Cada entorno tiene su propia base (`ucopet_main`, `ucopet_develop`) y su propio vhost de Rabbit.

## Cuentas

- `admin@ucopet.com`, la que crea la API al arrancar.
- Una por integrante del equipo, con rol ADMIN: `<usuario>@ucopet.com`, donde el usuario es el de
  su rama (`feature_pablogiraldo` -> `pablogiraldo@ucopet.com`). Lista en `seed/team.csv`.
- Dos medicos de prueba, con rol DOCTOR: `medica@ucopet.com` y `medico@ucopet.com`.

Las claves no estan en el repo; se piden a quien administra la VM.

## Montar la VM (una sola vez)

```bash
sudo mkdir -p /opt/ucopet && sudo chown "$USER" /opt/ucopet
git clone https://github.com/jpgiraldomesa/ucopet-deploy.git /opt/ucopet/deploy
cp /opt/ucopet/deploy/secrets.env.example /opt/ucopet/secrets.env   # y llenarlo
chmod 600 /opt/ucopet/secrets.env
```

Secretos del repo en GitHub: `VM_HOST`, `VM_USER` y `VM_SSH_KEY`.

## Horario de la VM

La VM esta apagada de 12 am a 6 am (hora de Colombia) para ahorrar creditos.

- **Apagado, 05:00 UTC:** el apagado automatico de Azure (`shutdown-computevm-vm-ucopet`), que libera la VM.
- **Encendido, 11:00 UTC:** `.github/workflows/vm.yml`, con la app de Entra `ucopet-deploy-github` por OIDC
  (sin secreto guardado), rol *Virtual Machine Contributor* solo sobre `rg-ucopet`.
- **El despliegue no corre de 05:00 a 11:30 UTC**, para no fallar por SSH con la VM apagada.
- **Prenderla o apagarla a mano:** pestaña Actions, workflow `vm`, `Run workflow` con `start` o `deallocate`.

## Operacion

```bash
scripts/deploy.sh develop                 # desplegar a mano un entorno
docker logs -f ucopet-develop-api         # ver una pieza
scripts/seed.sh develop                   # volver a cargar la semilla
```

Para forzar una reconstruccion completa: pestaña Actions, workflow `deploy`, `Run workflow` con
`force`.
