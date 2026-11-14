# Plan de JMeter: todos los procesadores

`ucopet-procesadores.jmx` carga los cinco procesadores a la vez, cada uno con su propio grupo de hilos, para ver en la
pagina de estado (`/estado/#pruebas`, seccion "Cada pieza en vivo") como responde cada uno.

| Grupo de hilos | Peticion | Procesador que la guarda |
|---|---|---|
| Preparacion | login, sede activa, una mascota con su tutor, un metodo de pago | (solo lee) |
| Usuarios | `POST /persons` | Usuarios |
| Comercial | `POST /providers` | Comercial |
| Salud | `POST /spaces` | Salud |
| Inventario | `POST /products` | Inventario |
| Pagos | `POST /receipts` | Pagos |
| Lecturas | catalogo, personas, proveedores, recibos | (la API lee la base) |

Cada peticion espera un 2xx. Entre peticiones hay una pausa de 0,5 a 1,5 s.

## Propiedades

| Propiedad | Por defecto | Que es |
|---|---|---|
| `host` | `ucopet.westus2.cloudapp.azure.com` | |
| `puerto` | `9443` | 9443 es `pruebas`, 8443 es `develop` |
| `correo` | `pablogiraldo@ucopet.com` | cuenta ADMIN |
| `clave` | (vacia) | la clave del equipo; no se guarda en el plan |
| `hilos` | `1` | hilos **por procesador** |
| `minutos` | `3` | duracion |
| `run` | `jmeter` | marca de los datos creados, para borrarlos despues |

## Correrlo

Con pantalla (para mostrarlo): abrir el `.jmx` en JMeter, poner las propiedades en
*Options → Properties* o lanzar con ellas:

```bash
jmeter -t ucopet-procesadores.jmx -Jclave='<clave>' -Jhilos=2 -Jminutos=5 -Jrun=jm$(date +%H%M)
```

Sin pantalla, con informe HTML:

```bash
jmeter -n -t ucopet-procesadores.jmx -Jclave='<clave>' -Jhilos=2 -Jminutos=5 -Jrun=jm1 \
  -l resultados.jtl -e -o informe
```

## Borrar lo que creo

Todo lo creado lleva la marca `run` ("Carga <run> ..."). En la VM:

```bash
/opt/ucopet/deploy/scripts/carga.sh fin pruebas <run> todos
```

Es la misma limpieza que usa la carga `todos` de k6 (`carga/todos.js`), que se lanza desde Actions → carga.
