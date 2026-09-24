#!/usr/bin/env bash
# =============================================================================
#  Vérifie que la documentation ne renvoie vers rien d'inexistant :
#    1. chaque lien Markdown relatif ([texte](chemin)) désigne un fichier ;
#    2. chaque chemin docs/<page>.md cité (docs, scripts, Terraform...) existe ;
#    3. chaque commande "make <cible>" citée dans un .md existe dans le Makefile.
#
#    scripts/check-docs.sh        (lancé en CI par "make check-docs")
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT}"
errors=0

report() {
  printf '  %s\n' "$*"
  errors=$((errors + 1))
}

# 1. Liens Markdown relatifs (les URL et les ancres seules sont ignorées).
while IFS= read -r file; do
  [[ -f "${file}" ]] || continue
  while IFS= read -r target; do
    target="${target%%#*}"
    [[ -z "${target}" || -e "$(dirname "${file}")/${target}" ]] || report "${file} : lien cassé vers ${target}"
  done < <(grep -oE '\]\([^) ]+\)' "${file}" | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^(https?://|mailto:|#)' || true)
done < <(git ls-files --cached --others --exclude-standard -- '*.md')

# 2. Pages docs/*.md citées n'importe où dans le dépôt (hors URL : ".../docs/x.md").
while IFS=: read -r file match; do
  path="docs/${match#*docs/}"
  [[ -f "${path}" ]] || report "${file} : ${path} n'existe pas"
done < <(git grep --untracked -oE '(^|[^/])docs/[A-Za-z0-9_-]+\.md' || true)

# 3. Cibles make citées dans la documentation : en début de ligne (bloc de code),
#    au début d'un `code` ou après && / ; (le texte en français est ignoré).
targets="$(sed -n -E 's/^([a-zA-Z_-]+):.*/\1/p' Makefile)"
# shellcheck disable=SC2016 # les ` de l'expression régulière sont ceux du Markdown
while IFS=: read -r file match; do
  target="${match#*make }"
  target="${target%%[[:space:]\`]*}"
  grep -qx "${target}" <<<"${targets}" || report "${file} : « make ${target} » n'existe pas dans le Makefile"
done < <(git grep --untracked -oE '(^[[:space:]]*|`|&& |; )make [a-z][a-z-]*([[:space:]`]|$)' -- '*.md' || true)

if ((errors > 0)); then
  printf '%s problème(s) dans la documentation (voir ci-dessus).\n' "${errors}" >&2
  exit 1
fi
printf 'Documentation : liens, pages citées et commandes make cohérents.\n'
