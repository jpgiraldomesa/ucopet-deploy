#!/usr/bin/env python3
# Corre en la VM cada 5 segundos (status-loop.sh). Junta el estado de los contenedores y de las colas
# de Rabbit y lo escribe en status/estado.json, que Caddy sirve en /estado.
# No expone el socket de Docker ni la clave de Rabbit: solo escribe un archivo.
import base64
import datetime
import json
import os
import subprocess
import urllib.request

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECRETS = os.environ.get("SECRETS", "/opt/ucopet/secrets.env")
OUT = os.path.join(HERE, "status", "estado.json")

ENVS = {"main": "", "develop": ":8443", "pruebas": ":9443"}
PRUEBAS_META = os.path.join(HERE, "status", "pruebas.json")
SERVICES = [
    ("api", "API", "api"),
    ("front", "Front", "front"),
    ("commercial", "Comercial", "processor"),
    ("health", "Salud", "processor"),
    ("payment", "Pagos", "processor"),
    ("user", "Usuarios", "processor"),
    ("inventory", "Inventario", "processor"),
]
PREFIXES = [
    ("ucopet.commercial.", "commercial"),
    ("ucopet.health.", "health"),
    ("ucopet.payment.", "payment"),
    ("ucopet.inventory.", "inventory"),
    ("ucopet.user.", "user"),
    ("provider.", "commercial"),
    ("person.", "user"),
    ("pet.", "user"),
    ("doctor.", "user"),
    ("notification.", "user"),
    ("specialtieDoctor.", "user"),
]


def secrets():
    values = {}
    with open(SECRETS) as f:
        for line in f:
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                values[k] = v
    return values


def docker_inspect(kind, ids):
    if not ids:
        return []
    out = subprocess.run(["docker", kind, "inspect", *ids], capture_output=True, text=True)
    return json.loads(out.stdout or "[]")


def containers():
    ids = subprocess.run(["docker", "ps", "-aq"], capture_output=True, text=True).stdout.split()
    data = docker_inspect("container", ids)
    images = {i["Id"]: i for i in docker_inspect("image", sorted({c["Image"] for c in data}))}
    result = {}
    for c in data:
        name = c["Name"].lstrip("/")
        state = c["State"]
        labels = c["Config"].get("Labels") or {}
        image = images.get(c["Image"], {})
        net = (c["NetworkSettings"].get("Networks") or {}).get("ucopet") or {}
        result[name] = {
            "status": state.get("Status"),
            "health": (state.get("Health") or {}).get("Status"),
            "restarts": c.get("RestartCount", 0),
            "started_at": state.get("StartedAt"),
            "repo": labels.get("ucopet.repo"),
            "revision": labels.get("org.opencontainers.image.revision"),
            "built_at": image.get("Created"),
            "ip": net.get("IPAddress"),
        }
    return result


def rabbit(path, password, host):
    req = urllib.request.Request(f"http://{host}:15672/api/{path}")
    token = base64.b64encode(f"ucopet:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def owner_by_prefix(queue):
    for prefix, svc in PREFIXES:
        if queue.startswith(prefix):
            return svc
    return None


def main():
    s = secrets()
    cs = containers()
    by_ip = {v["ip"]: k for k, v in cs.items() if v["ip"]}
    now = datetime.datetime.now(datetime.timezone.utc)

    queues, consumers, rabbit_error = [], [], None
    rabbit_ip = (cs.get("rabbit") or {}).get("ip")
    try:
        queues = rabbit("queues?columns=name,vhost,messages,consumers", s["RABBIT_PASSWORD"], rabbit_ip)
        consumers = rabbit("consumers", s["RABBIT_PASSWORD"], rabbit_ip)
    except Exception as e:
        rabbit_error = str(e)

    listeners = {}
    for c in consumers:
        key = (c["queue"]["vhost"], c["queue"]["name"])
        container = by_ip.get((c.get("channel_details") or {}).get("peer_host"))
        if container:
            listeners.setdefault(key, set()).add(container)

    envs = {}
    for env, port in ENVS.items():
        prefix = f"ucopet-{env}-"
        env_queues = []
        for q in sorted((q for q in queues if q["vhost"] == env), key=lambda q: q["name"]):
            who = sorted(c[len(prefix):] for c in listeners.get((env, q["name"]), set()) if c.startswith(prefix))
            env_queues.append({
                "name": q["name"],
                "owner": who[0] if who else owner_by_prefix(q["name"]),
                "listeners": who,
                "consumers": q.get("consumers", 0),
                "messages": q.get("messages", 0),
            })
        services = []
        for svc, label, kind in SERVICES:
            c = cs.get(prefix + svc)
            services.append({"svc": svc, "label": label, "kind": kind, **(c or {"status": "missing"})})
        envs[env] = {
            "url": f"https://{s['DOMAIN']}{port}",
            "services": services,
            "queues": env_queues,
        }
        try:
            with open(os.path.join(HERE, "status", f"apagado-{env}")) as f:
                envs[env]["off"] = json.load(f)
        except (OSError, ValueError):
            envs[env]["off"] = None
        if env == "pruebas":
            try:
                with open(PRUEBAS_META) as f:
                    envs[env]["meta"] = json.load(f)
            except (OSError, ValueError):
                envs[env]["meta"] = None

    infra = [{"name": n, **{k: cs[n][k] for k in ("status", "health", "restarts", "started_at")}}
             for n in ("postgres", "rabbit", "caddy") if n in cs]

    data = {
        "generated_at": now.isoformat(timespec="seconds"),
        "rabbit_error": rabbit_error,
        "infra": infra,
        "envs": envs,
    }
    tmp = f"{OUT}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, OUT)


if __name__ == "__main__":
    main()
