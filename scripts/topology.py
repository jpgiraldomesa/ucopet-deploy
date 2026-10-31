#!/usr/bin/env python3
# Corre en la VM desde deploy.sh, antes de levantar el entorno.
# El procesador de Salud no declara sus colas: si no existen en Rabbit, no arranca. En vez de
# mantenerlas a mano en infra/rabbit-topology.json, este script lee los *.properties del jar
# que trae su imagen, busca los trios <x>.exchange-name / <x>.queue-name / <x>.routing-key-name
# y los declara (exchange direct durable, cola durable, binding). Es idempotente.
# Solo para los servicios de NO_DECLARE: a los que declaran sus colas no se les toca nada,
# porque una cola declarada antes con otros argumentos los haria fallar.
# Uso: scripts/topology.py <entorno>
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


def jar_properties(image):
    cid = subprocess.run(["docker", "create", image], capture_output=True, text=True, check=True).stdout.strip()
    try:
        jar = subprocess.run(["docker", "cp", f"{cid}:/app/app.jar", "-"], capture_output=True, check=True).stdout
    finally:
        subprocess.run(["docker", "rm", cid], capture_output=True)
    with tarfile.open(fileobj=io.BytesIO(jar)) as tar:
        data = tar.extractfile(tar.getmembers()[0]).read()
    props = {}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
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


def main():
    env = sys.argv[1]
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

    for svc in NO_DECLARE:
        image = f"{REGISTRY}/ucopet-{svc}:{env}"
        try:
            items = triples(jar_properties(image))
        except subprocess.CalledProcessError:
            print(f"topologia {env}: {svc} no tiene imagen, se salta")
            continue
        for t in items:
            ex = urllib.parse.quote(t["exchange-name"], safe="")
            q = urllib.parse.quote(t["queue-name"], safe="")
            call("PUT", f"exchanges/{vhost}/{ex}", {"type": "direct", "durable": True})
            call("PUT", f"queues/{vhost}/{q}", {"durable": True})
            call("POST", f"bindings/{vhost}/e/{ex}/q/{q}", {"routing_key": t["routing-key-name"]})
        print(f"topologia {env}: {svc} con {len(items)} colas declaradas")


if __name__ == "__main__":
    main()
