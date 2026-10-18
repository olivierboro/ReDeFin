#!/bin/bash
# Lance ReDeFin sur le poste de travail (macOS, Qt 5 de Homebrew : `brew install qt@5`)
# avec les remplaçants des modules Freebox de modules/.
#
# Usage : dev/desktop/run.sh [--delta] [--grab=<fichier.png>] [--keys=…] [--trace-focus] [chemin d'une copie de ReDeFin]
#   --delta        simule une Freebox Delta / Devialet (fbx7hd-delta) au lieu d'une Révolution
#   --grab=…       capture la fenêtre après 6 s (--grab-delay=<ms>) puis quitte
#   --keys=…       rejoue des touches avant la capture (détail dans modules/fbx/application/application.qml)
#   --trace-focus  journalise chaque changement d'élément actif
#   Sans chemin, lance le dépôt qui contient ce script.
#
# Télécommande : flèches, Entrée = OK, Échap = Retour, PageUp / PageDown.
# Réglages persistés dans data/settings.ini (données de session : ignoré par git, ne pas partager).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
qmlscene="/opt/homebrew/opt/qt@5/bin/qmlscene"
model="fbx6hd"
repo="$(cd "$here/../.." && pwd)"
extra=()

for arg in "$@"; do
  case "$arg" in
    --delta) model="fbx7hd-delta" ;;
    --grab=*|--grab-delay=*|--keys=*|--trace-focus) extra+=("$arg") ;;
    *) repo="$arg" ;;
  esac
done

# libfbxqml (Free, sans licence publiée) n'est pas versionnée : modules/ y pointe
# par des liens symboliques.
if [ ! -d "$here/libfbxqml" ]; then
  git clone --quiet https://github.com/fbx/libfbxqml.git "$here/libfbxqml"
fi

# Appareils du réseau local pour la découverte Jellyfin : adresse du poste et
# voisins de la table ARP, hors multicast et broadcast.
lan_hosts="$(
  {
    route -n get default 2>/dev/null | awk '/interface:/ {print $2}' | xargs -I{} ipconfig getifaddr {} 2>/dev/null
    arp -an | sed -nE 's/^[^(]*\(([0-9.]+)\) at [0-9a-f:]+ .*/\1/p'
  } | grep -vE '^(22[4-9]|23[0-9])\.|\.255$' | sort -u -t. -k1,1n -k2,2n -k3,3n -k4,4n | paste -sd, -
)"

exec "$qmlscene" -I "$here/modules" "$repo/main.qml" -- "--fbx-model=$model" "--lan-hosts=$lan_hosts" ${extra[@]+"${extra[@]}"}
