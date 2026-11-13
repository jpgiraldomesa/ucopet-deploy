# ucopet-deploy

Despliegue continuo de UcoPet en una VM de Azure. Construye `main` y `develop` de los siete repos
del equipo y los publica como dos entornos independientes. No toca los repos del equipo: los
Dockerfile y la configuracion viven aqui.

| Entorno | Rama | Direccion |
|---|---|---|
| main | `main` de cada repo | `https://<dominio>` |
| develop | `develop` de cada repo | `https://<dominio>:8443` |
| pruebas | las ramas que alguien elija | `https://<dominio>:9443` |
| Rabbit (consola) | | `https://<dominio>:15671` |
| Estado | | `https://<dominio>/estado/` |

La pagina de estado muestra, por entorno, si cada pieza esta arriba, que commit corre y que colas
escucha cada procesador (que no tienen pantalla). La arma `scripts/status.py` cada 5 segundos en la
VM (`scripts/status-loop.sh`, que cron relanza cada minuto); escribe `status/estado.json`, Caddy lo
sirve y la pagina lo consulta cada 5 segundos. No expone Docker ni la clave de Rabbit.

## Como funciona

1. Cada 5 minutos, la VM (`scripts/watch.sh`, por cron) mira el ultimo commit de `main` y `develop` en
   cada repo de `services.txt`. Si alguno cambio, lanza el workflow `deploy`
   (`.github/workflows/deploy.yml`). No se usa el `schedule` de GitHub: llegaba con horas de atraso.
   Necesita `GH_DISPATCH_TOKEN` en `/opt/ucopet/secrets.env` (token fino, solo `ucopet-deploy`,
   permiso *Actions: read and write*). Lo que lanzo queda en `/opt/ucopet/watch.log`.
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
| `infra/rabbit-topology.json` | colas que nadie declara en su codigo (medicos, especialidades de medico, mascotas, ventas, Salud); se importan en cada vhost. Solo colas con consumidor |
| `scripts/topology.py` | lee los `.properties` del jar de Salud y declara las colas que su codigo escucha, asi una cola nueva no lo tumba; las que solo nombra el `.properties` no se crean. Con `faltantes`, despues de levantar, declara las colas de la API que un procesador espera y todavia no existen (la API las crea recien al publicar por primera vez) |
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

## Probar una rama (entorno pruebas)

Un entorno compartido para ver una rama `feature_*` junto a lo demas antes de hacer merge.

1. Pestaña Actions, workflow **probar ramas**, `Run workflow`.
2. Poner la rama en cada repo que se quiera cambiar; lo que se deje en `develop` queda como en develop.
   Marcar *Base limpia* para borrar los datos de pruebas y volver a sembrar.
3. En unos minutos queda en `https://<dominio>:9443`. La pagina de estado (pestaña *pruebas*) dice quien lo
   cargo, cuando y que rama tiene cada pieza.

Si ya existe la imagen de ese commit (de develop, de main o de otra prueba) se reusa; si no, se construye.
Si una rama no existe, no se toca nada y el resumen de la ejecucion lo dice. Es uno solo: el ultimo que lo
lanza lo ocupa. Solo construye lo que esta subido a GitHub.

## Prueba de carga

Pestaña Actions, workflow **carga**, `Run workflow`: modulo (`catalogo` o `login`), entorno (`pruebas` o
`develop`), minutos (1 a 20), usuarios simultaneos (5 a 50) y porcentaje de escrituras.

- **login** (`carga/login.js`): 40 % inicios de sesion (cada uno es un BCrypt y publica la notificacion
  `LOGIN_SUCCEDED` por Rabbit, que consume el procesador de Usuarios), lecturas con token y altas de persona
  por el bus (`person.create.qu`). Al terminar borra las personas `carga.k6.<id>.*` y esas notificaciones.

- Corre k6 (`carga/carga.js`) desde GitHub, no desde la VM: la carga entra por Caddy y el front como la de
  un usuario real. Entra con `pablogiraldo@ucopet.com` y mezcla lecturas del catalogo con creacion de
  productos, que pasan por Rabbit y el procesador de Inventario.
- Mientras corre, la pagina de estado muestra el aviso con la cuenta regresiva y en las graficas se ve
  subir la CPU y los mensajes por segundo.
- Al terminar, el resumen de la ejecucion trae peticiones por segundo, fallas y tiempos (mediana, p95,
  p99) de lecturas y escrituras, y `scripts/carga.sh fin` borra los productos de prueba.

## Apagar o prender un entorno

Pestaña Actions, workflow **entorno**, `Run workflow`: elegir `main`, `develop` o `pruebas` y `apagar` o `encender`.

- **Apagar** detiene sus siete contenedores y deja la marca `status/apagado-<entorno>`: el despliegue lo salta y
  la pagina de estado lo muestra apagado. La base y el vhost quedan intactos.
- **Encender** quita la marca y lo despliega con lo ultimo de su rama.

No se hace desde la pagina de estado porque es publica y sin login: cualquiera con el enlace podria apagarlo.

## Horario de la VM

La VM esta apagada de 12 am a 6 am (hora de Colombia) para ahorrar creditos.

- **Apagado, 05:00 UTC:** el apagado automatico de Azure (`shutdown-computevm-vm-ucopet`), que libera la VM.
- **Encendido:** solo a mano (Actions, workflow `vm`, `start`, o `az vm start -g rg-ucopet -n vm-ucopet`).
  `.github/workflows/vm.yml` entra con la app de Entra `ucopet-deploy-github` por OIDC (sin secreto guardado,
  rol *Virtual Machine Contributor* solo sobre `rg-ucopet`). No tiene horario: el cron de GitHub llegaba con
  horas de atraso y prendia la VM a cualquier hora.
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
