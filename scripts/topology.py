#!/usr/bin/env python3
# Corre en la VM desde deploy.sh, antes de levantar el entorno.
# El procesador de Salud no declara sus colas: si no existen en Rabbit, no arranca. En vez de
# mantenerlas a mano en infra/rabbit-topology.json, este script lee los *.properties del jar
# que trae su imagen, busca los trios <x>.exchange-name / <x>.queue-name / <x>.routing-key-name
# y los declara (exchange direct durable, cola durable, binding). Es idempotente.
# Solo las que tienen consumidor: la clave de la cola tiene que aparecer en algun .class del jar
# (el @RabbitListener(queues = "${...queue-name}") queda escrito ahi). Las que el .properties nombra
# pero nadie escucha no se crean, para no llenar Rabbit de colas muertas.
# Solo para los servicios de NO_DECLARE: a los que declaran sus colas no se les toca nada,
# porque una cola declarada antes con otros argumentos los haria fallar.
# Uso: scripts/topology.py <entorno>
#
# Con "faltantes" (scripts/topology.py <entorno> faltantes), despues de levantar el entorno: la API declara
# sus colas recien la primera vez que publica algo, y un procesador que escucha una cola de la API (los
# traslados de Inventario) se queda esperandola. Busca en los logs de los procesadores las colas que no
# encuentran, y si son de la API (estan en sus .properties) las declara como ella: durable, sin argumentos.
# Las que no son de la API no se tocan.
import base64
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import urllib.parse
import urllib.request
import zipfile

NO_DECLARE = ["health"]
SECRETS = os.environ.get("SECRETS", "/opt/ucopet/secrets.env")
REGISTRY = os.environ.get("REGISTRY", "ghcr.io/jpgiraldomesa")


def secrets():
    with open(SECRETS) as f:
        return dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)


def jar_classes_text(image):
    return jar_properties(image, classes=True)


def jar_properties(image, classes=False):
    cid = subprocess.run(["docker", "create", image], capture_output=True, text=True, check=True).stdout.strip()
    try:
        jar = subprocess.run(["docker", "cp", f"{cid}:/app/app.jar", "-"], capture_output=True, check=True).stdout
    finally:
        subprocess.run(["docker", "rm", cid], capture_output=True)
    with tarfile.open(fileobj=io.BytesIO(jar)) as tar:
        data = tar.extractfile(tar.getmembers()[0]).read()
    props = {}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        if classes:
            return b"".join(z.read(n) for n in z.namelist()
                            if n.startswith("BOOT-INF/classes/") and n.endswith(".class"))
        for name in z.namelist():
            if name.startswith("BOOT-INF/classes/") and name.endswith(".properties"):
                for line in z.read(name).decode("utf-8", "replace").splitlines():
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        props[k.strip()] = v.strip()
    return props


def triples(props):
    found = {}
    for key, value in props.items():
        m = re.match(r"(.+)\.(exchange-name|queue-name|routing-key-name)$", key)
        if m and "${" not in value:
            found.setdefault(m.group(1), {})[m.group(2)] = value
    return [t for t in found.values() if len(t) == 3]


def missing_queues(env):
    names = set()
    for svc in ["commercial", "health", "payment", "user", "inventory"]:
        logs = subprocess.run(["docker", "logs", "--since", "15m", f"ucopet-{env}-{svc}"],
                              capture_output=True, text=True)
        names.update(re.findall(r"no queue '([^']+)'", logs.stdout + logs.stderr))
    return names


def main():
    env = sys.argv[1]
    only_missing = len(sys.argv) > 2 and sys.argv[2] == "faltantes"
    s = secrets()
    ip = subprocess.run(["docker", "inspect", "-f", "{{.NetworkSettings.Networks.ucopet.IPAddress}}", "rabbit"],
                        capture_output=True, text=True, check=True).stdout.strip()
    auth = "Basic " + base64.b64encode(f"ucopet:{s['RABBIT_PASSWORD']}".encode()).decode()
    vhost = urllib.parse.quote(env, safe="")

    def call(method, path, body):
        req = urllib.request.Request(f"http://{ip}:15672/api/{path}", method=method,
                                     data=json.dumps(body).encode(), headers={"Authorization": auth,
                                                                               "Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=10).read()

    def declare(t):
        ex = urllib.parse.quote(t["exchange-name"], safe="")
        q = urllib.parse.quote(t["queue-name"], safe="")
        call("PUT", f"exchanges/{vhost}/{ex}", {"type": "direct", "durable": True})
        call("PUT", f"queues/{vhost}/{q}", {"durable": True})
        call("POST", f"bindings/{vhost}/e/{ex}/q/{q}", {"routing_key": t["routing-key-name"]})

    if only_missing:
        waiting = missing_queues(env)
        if not waiting:
            print(f"topologia {env}: ningun procesador espera colas")
            return
        api = {t["queue-name"]: t for t in triples(jar_properties(f"{REGISTRY}/ucopet-api:{env}"))}
        done = sorted(q for q in waiting if q in api)
        for q in done:
            declare(api[q])
        print(f"topologia {env}: declaradas de la API {done or 'ninguna'}; sin dueno {sorted(waiting - set(done)) or 'ninguna'}")
        return

    for svc in NO_DECLARE:
        image = f"{REGISTRY}/ucopet-{svc}:{env}"
        try:
            props = jar_properties(image)
            code = jar_classes_text(image)
            keys = {v: k for k, v in props.items() if k.endswith(".queue-name")}
            items = [t for t in triples(props)
                     if ("${" + keys.get(t["queue-name"], "") + "}").encode() in code]
        except subprocess.CalledProcessError:
            print(f"topologia {env}: {svc} no tiene imagen, se salta")
            continue
        for t in items:
            declare(t)
        print(f"topologia {env}: {svc} con {len(items)} colas declaradas")


if __name__ == "__main__":
    main()
