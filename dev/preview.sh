#!/bin/bash
# Reconstruit la copie d'essai ../ReDeFin-preview (branche locale-preview) :
# upstream/beta plus les modifications de chaque branche de PR, commitées ou non,
# puis la lance dans le harnais. Copie locale uniquement : jamais commitée,
# poussée ni proposée en PR, et écrasée à chaque reconstruction.
#
# Les correctifs de desktop/patches/ (profil de lecture du Mac…) s'appliquent
# ensuite : propres au harnais, ils n'entrent dans aucune branche de PR.
#
# Usage : dev/preview.sh [--no-run] [--fake-video] [--option-de-run.sh…] [copie de travail…]
#   --fake-video  lance avec le faux lecteur au lieu de la vraie lecture
#                 transcodée par Jellyfin pour le Mac (--mac-video de run.sh)
#   Toute autre option en --… est transmise à desktop/run.sh (--open-item=…).
#   Sans copie indiquée, prend toutes les copies de travail du dépôt sauf
#   celle-ci (beta) et la copie d'essai elle-même.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
preview="$(dirname "$repo")/ReDeFin-preview"
base="upstream/beta"
run=1
video="--mac-video"
sources=()
run_args=()

for arg in "$@"; do
  case "$arg" in
    --no-run) run=0 ;;
    --fake-video) video="" ;;
    --*) run_args+=("$arg") ;;
    *) sources+=("$(cd "$arg" && pwd)") ;;
  esac
done

if [ ${#sources[@]} -eq 0 ]; then
  while IFS= read -r path; do
    [ "$path" = "$repo" ] || [ "$path" = "$preview" ] || sources+=("$path")
  done < <(git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p')
fi

if [ ! -d "$preview" ]; then
  git -C "$repo" worktree add --quiet --no-track -B locale-preview "$preview" "$base"
fi
git -C "$preview" reset --quiet --hard "$base"
git -C "$preview" clean --quiet -fd

for src in ${sources[@]+"${sources[@]}"}; do
  name="$(git -C "$src" rev-parse --abbrev-ref HEAD)"
  if ! git -C "$src" diff --binary "$base" | git -C "$preview" apply --whitespace=nowarn; then
    echo "Conflit en appliquant $name ($src) : la copie d'essai est incomplète." >&2
    exit 1
  fi
  # Fichiers nouveaux pas encore suivis par git dans la branche.
  (cd "$src" && git ls-files --others --exclude-standard -z | xargs -0 -I{} rsync -R "{}" "$preview/")
  echo "+ $name"
done

for patch in "$here"/desktop/patches/*.patch; do
  [ -e "$patch" ] || continue
  if ! git -C "$preview" apply --whitespace=nowarn "$patch"; then
    echo "Correctif du harnais inapplicable : $patch" >&2
    exit 1
  fi
  echo "+ $(basename "$patch") (harnais)"
done

[ "$run" -eq 1 ] && exec "$here/desktop/run.sh" "$preview" ${video:+"$video"} ${run_args[@]+"${run_args[@]}"}
exit 0
