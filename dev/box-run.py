#!/usr/bin/env python3
"""Lance ReDeFin sur une Freebox Player en mode développeur, depuis ce poste.

Même protocole que fbx-qml-run (github.com/fbx/freebox-dev-utils) et le plugin
Qt Creator de Free : la box télécharge l'app depuis un serveur HTTP local et
renvoie ses logs ici. Seuls les fichiers retenus par le .fbxproject sont
servis, comme dans le paquet FreeStore : un fichier oublié dans cette liste
échoue donc ici aussi (signalé « hors paquet »).

Usage : dev/box-run.py [-t IP_DE_LA_BOX] [chemin d'une copie de ReDeFin]
Sans chemin, lance le dépôt qui contient ce script. Ctrl-C pour arrêter.
"""
import argparse
import fnmatch
import functools
import http.server
import json
import os
import posixpath
import random
import re
import socket
import subprocess
import sys
import threading
import urllib.parse
import urllib.request

SERVICE = "_fbx-devel._tcp"
EXTENSIONS = {
    "QmlFiles": ["*.qml"],
    "JavaScriptFiles": ["*.js"],
    "ImageFiles": ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.svg", "*.webp"],
}


def package_rules(project_file):
    """(répertoire, motifs, récursif) pour chaque bloc de fichiers du .fbxproject."""
    with open(project_file, encoding="utf-8") as f:
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", f.read(), flags=re.S)

    rules = []
    for kind, body in re.findall(r"\b(QmlFiles|JavaScriptFiles|ImageFiles|Files)\s*\{([^}]*)\}", text):
        directory = re.search(r'directory:\s*"([^"]*)"', body)
        filters = re.search(r'filter:\s*"([^"]*)"', body)
        patterns = [p.strip() for p in filters.group(1).split(";")] if filters else EXTENSIONS.get(kind, ["*"])
        recursive = re.search(r"recursive:\s*true", body) is not None
        rules.append((posixpath.normpath(directory.group(1) if directory else "."), patterns, recursive))
    return rules


def is_packaged(rules, relpath):
    directory, name = posixpath.split(relpath)
    directory = directory or "."
    for root, patterns, recursive in rules:
        inside = directory == root or (recursive and (root == "." or directory.startswith(root + "/")))
        if inside and any(fnmatch.fnmatchcase(name, p) for p in patterns):
            return True
    return False


class PackageHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, rules, **kwargs):
        self.rules = rules
        super().__init__(*args, **kwargs)

    def send_head(self):
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        relpath = posixpath.normpath(path).lstrip("/")
        if not is_packaged(self.rules, relpath):
            print(f"[box-run] hors paquet : {relpath}", file=sys.stderr)
            self.send_error(404)
            return None
        return super().send_head()

    # La box ne doit jamais garder en cache une version précédente des fichiers.
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, format, *args):
        pass


def dns_sd(args, pattern, seconds=3):
    """Première correspondance de pattern dans la sortie de dns-sd (macOS), ou None."""
    proc = subprocess.Popen(["dns-sd", *args], stdout=subprocess.PIPE, text=True)
    timer = threading.Timer(seconds, proc.kill)
    timer.start()
    try:
        for line in proc.stdout:
            match = re.search(pattern, line)
            if match:
                return match
        return None
    finally:
        timer.cancel()
        proc.kill()
        proc.wait()


def find_box():
    browse = dns_sd(["-B", SERVICE, "local"], r"\sAdd\s.*" + re.escape(SERVICE) + r"\.\s+(.+)$")
    if not browse:
        return None
    lookup = dns_sd(["-L", browse.group(1).strip(), SERVICE, "local"], r"can be reached at (\S+?)\.?:\d+")
    if not lookup:
        return None
    return socket.gethostbyname(lookup.group(1))


def jsonrpc(endpoint, method, params):
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": str(random.randint(0, 10000)),
        "method": method,
        "params": params,
    }).encode()
    request = urllib.request.Request(endpoint, body, {
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    with urllib.request.urlopen(request, timeout=10) as response:
        answer = json.load(response)

    if "result" in answer:
        return answer["result"]
    error = answer.get("error", {})
    raise RuntimeError(f"JSON-RPC {error.get('code', -1)} : {error.get('message', 'ni résultat ni erreur')}")


def stream(host, port, output):
    """Recopie un flux de logs de la box jusqu'à sa fermeture."""
    with socket.create_connection((host, port)) as sock:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                return
            output.write(chunk)
            output.flush()


def main():
    parser = argparse.ArgumentParser(description="Lance ReDeFin sur une Freebox Player en mode développeur.")
    parser.add_argument("-t", dest="target", help="IP de la box (découverte mDNS sinon)")
    parser.add_argument("-p", dest="port", type=int, default=8234, help="port HTTP local (8234)")
    parser.add_argument("-e", dest="entry_point", default="main", help="point d'entrée du manifest (main)")
    parser.add_argument("repo", nargs="?", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = parser.parse_args()

    repo = os.path.abspath(args.repo)
    projects = [f for f in os.listdir(repo) if f.endswith(".fbxproject")]
    if len(projects) != 1:
        sys.exit(f"Un seul .fbxproject attendu dans {repo}, trouvé : {projects}")
    rules = package_rules(os.path.join(repo, projects[0]))

    host = args.target or find_box()
    if not host:
        sys.exit("Aucune box en mode développeur trouvée par mDNS : passer son IP avec -t.")

    with socket.create_connection((host, 80), timeout=5) as probe:
        local_ip = probe.getsockname()[0]

    handler = functools.partial(PackageHandler, rules=rules, directory=repo)
    server = http.server.ThreadingHTTPServer((local_ip, args.port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    manifest_url = f"http://{local_ip}:{args.port}/manifest.json"
    print(f"[box-run] box {host}, app servie depuis {manifest_url}", file=sys.stderr)
    try:
        result = jsonrpc(f"http://{host}/pub/devel", "debug_qml_app", {
            "manifest_url": manifest_url,
            "entry_point": args.entry_point,
            "wait": False,
        })
        for port, output in ((result["stdout_port"], sys.stdout.buffer), (result["stderr_port"], sys.stderr.buffer)):
            threading.Thread(target=stream, args=(host, port, output), daemon=True).start()
        print("[box-run] logs de la box ci-dessous, Ctrl-C pour arrêter", file=sys.stderr)
        threading.Event().wait()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
