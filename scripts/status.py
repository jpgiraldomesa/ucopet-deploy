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
SAMPLE = os.path.join(HERE, "status", ".muestra.json")
HISTORY = os.path.join(HERE, "status", "historial.json")
HISTORY_POINTS = 80
CGROUP = "/sys/fs/cgroup/system.slice/docker-{}.scope"
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
            "id": c["Id"],
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


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def usage(cs, now):
    # CPU de cada contenedor como porcentaje de un nucleo (la VM tiene 2: el tope es 200 %),
    # sacado de la diferencia de usage_usec entre esta muestra y la anterior. Memoria en MB.
    prev = read_json(SAMPLE, {})
    sample = {"t": now.timestamp(), "cpu": {}}
    for name, c in cs.items():
        if c["status"] != "running":
            continue
        base = CGROUP.format(c["id"])
        try:
            with open(f"{base}/cpu.stat") as f:
                usec = int(f.readline().split()[1])
            with open(f"{base}/memory.current") as f:
                c["mem_mb"] = round(int(f.read()) / 1048576)
        except (OSError, ValueError, IndexError):
            continue
        sample["cpu"][c["id"]] = usec
        before = prev.get("cpu", {}).get(c["id"])
        elapsed = sample["t"] - prev.get("t", 0)
        if before is not None and 0 < elapsed < 120:
            c["cpu"] = round(max(0, usec - before) / (elapsed * 1e6) * 100, 1)
    write_json(SAMPLE, sample)


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
    usage(cs, now)

    queues, consumers, rabbit_error = [], [], None
    rabbit_ip = (cs.get("rabbit") or {}).get("ip")
    columns = ("name,vhost,messages,consumers,message_stats.publish_details.rate,"
               "message_stats.ack_details.rate,message_stats.deliver_get_details.rate")
    try:
        queues = rabbit(f"queues?columns={columns}", s["RABBIT_PASSWORD"], rabbit_ip)
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
            stats = q.get("message_stats") or {}
            out = (stats.get("ack_details") or stats.get("deliver_get_details") or {}).get("rate", 0)
            env_queues.append({
                "name": q["name"],
                "owner": who[0] if who else owner_by_prefix(q["name"]),
                "listeners": who,
                "consumers": q.get("consumers", 0),
                "messages": q.get("messages", 0),
                "rate_in": round((stats.get("publish_details") or {}).get("rate", 0), 2),
                "rate_out": round(out, 2),
            })
        services = []
        for svc, label, kind in SERVICES:
            c = dict(cs.get(prefix + svc) or {"status": "missing"})
            c.pop("id", None)
            services.append({"svc": svc, "label": label, "kind": kind, **c})
        envs[env] = {
            "url": f"https://{s['DOMAIN']}{port}",
            "services": services,
            "queues": env_queues,
            "load": read_json(os.path.join(HERE, "status", f"carga-{env}.json"), None),
            "totals": {
                "cpu": round(sum(x.get("cpu", 0) for x in services), 1),
                "mem_mb": sum(x.get("mem_mb", 0) for x in services),
                "rate_in": round(sum(q["rate_in"] for q in env_queues), 2),
                "rate_out": round(sum(q["rate_out"] for q in env_queues), 2),
                "messages": sum(q["messages"] for q in env_queues),
            },
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

    infra = [{"name": n, **{k: cs[n].get(k) for k in ("status", "health", "restarts", "started_at", "cpu", "mem_mb")}}
             for n in ("postgres", "rabbit", "caddy") if n in cs]

    history = read_json(HISTORY, [])
    history.append({"t": now.isoformat(timespec="seconds"),
                    "infra_cpu": round(sum(i.get("cpu") or 0 for i in infra), 1),
                    "envs": {e: v["totals"] for e, v in envs.items()}})
    history = history[-HISTORY_POINTS:]
    write_json(HISTORY, history)

    write_json(OUT, {
        "generated_at": now.isoformat(timespec="seconds"),
        "rabbit_error": rabbit_error,
        "infra": infra,
        "envs": envs,
        "history": history,
    })


if __name__ == "__main__":
    main()
