#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Fonctions communes du CLI k8s-lab : affichage, configuration, confirmations.
#  Ce fichier est "sourcé" par ./k8s-lab, il ne s'exécute pas seul.
# =============================================================================

# --- Couleurs (désactivées hors terminal ou si NO_COLOR est défini) -----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_CYAN=$'\033[36m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN=''
fi

# --- Messages -------------------------------------------------------------------
step()  { printf '\n%s==> %s%s\n' "${C_BOLD}${C_BLUE}" "$*" "${C_RESET}"; }
info()  { printf '%s\n' "$*"; }
ok()    { printf '%s[ok]%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn()  { printf '%s[attention]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
error() { printf '%s[erreur]%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
hint()  { printf '%s    %s%s\n' "${C_DIM}" "$*" "${C_RESET}"; }

# Affiche un message d'erreur pédagogique (quoi, pourquoi, comment corriger) et quitte.
#   die "Titre" ["ligne d'explication" ...]
die() {
  local title="$1"
  shift || true
  printf '\n%s[erreur]%s %s%s%s\n' "${C_RED}" "${C_RESET}" "${C_BOLD}" "${title}" "${C_RESET}" >&2
  local line
  for line in "$@"; do
    printf '  %s\n' "${line}" >&2
  done
  printf '\n' >&2
  exit 1
}

# Affiche la commande exécutée (pédagogie : l'étudiant voit ce qui se passe) puis l'exécute.
run() {
  printf '%s$ %s%s\n' "${C_CYAN}" "$*" "${C_RESET}"
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

# Vrai si $1 >= $2 (comparaison de versions, "v" initial ignoré).
version_ge() {
  local a="${1#v}" b="${2#v}"
  [[ "$(printf '%s\n%s\n' "${b}" "${a}" | sort -V | head -n1)" == "${b}" ]]
}

# --- Configuration ----------------------------------------------------------------
# Lit un fichier KEY=VALUE sans l'exécuter (plus sûr qu'un "source").
# Une variable déjà présente dans l'environnement n'est jamais écrasée : c'est
# ce qui donne la priorité environnement > .env > config/lab.env.
load_env_file() {
  local file="$1" line key value
  [[ -f "${file}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ ! "${line}" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
      warn "${file}: ligne ignorée (format attendu CLE=valeur) : ${line}"
      continue
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    # Guillemets englobants facultatifs : CLE="valeur"
    if [[ "${value}" =~ ^\"(.*)\"$ || "${value}" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    if [[ -z "${!key+x}" ]]; then
      printf -v "${key}" '%s' "${value}"
      export "${key?}"
    fi
  done <"${file}"
}

load_config() {
  load_env_file "${LAB_ROOT}/.env"
  load_env_file "${LAB_ROOT}/config/lab.env"

  # Répertoires de travail (ignorés par Git).
  LAB_STATE_DIR="${LAB_ROOT}/.lab"
  LAB_KUBE_DIR="${LAB_ROOT}/.kube"
  LAB_KUBECONFIG="${LAB_KUBE_DIR}/config"
  export LAB_STATE_DIR LAB_KUBE_DIR LAB_KUBECONFIG

  validate_config
}

# Vérifications de base : une erreur de frappe dans .env doit être expliquée.
validate_config() {
  local var
  for var in WORKER_COUNT NODE_CPUS NODE_MEMORY_MB NODE_DISK_GB MINIKUBE_NODES MINIKUBE_CPUS MINIKUBE_MEMORY_MB; do
    if [[ ! "${!var:-}" =~ ^[0-9]+$ ]]; then
      die "${var}=${!var:-} n'est pas un nombre entier." \
        "Corrigez la valeur dans .env (ou config/lab.env)."
    fi
  done
  if ((WORKER_COUNT > 20)); then
    die "WORKER_COUNT=${WORKER_COUNT} est trop grand (maximum 20 dans ce lab)."
  fi
  if [[ ! "${CLUSTER_NAME:-}" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
    die "CLUSTER_NAME=${CLUSTER_NAME:-} est invalide." \
      "Utilisez des minuscules, chiffres et tirets (ex : k8s-lab)."
  fi
  if [[ ! "${KUBERNETES_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "KUBERNETES_VERSION=${KUBERNETES_VERSION:-} est invalide." \
      "Indiquez une version complète, par exemple 1.37.1."
  fi
}

ensure_state_dirs() {
  mkdir -p "${LAB_STATE_DIR}" "${LAB_KUBE_DIR}/clusters"
  chmod 700 "${LAB_STATE_DIR}" "${LAB_KUBE_DIR}" "${LAB_KUBE_DIR}/clusters"
}

# --- Confirmation des opérations destructives --------------------------------------
# ASSUME_YES=1 (option --yes) permet l'automatisation (CI). Sans terminal et
# sans --yes, on refuse plutôt que de détruire quelque chose par surprise.
confirm() {
  local question="$1" answer
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    info "${question} [oui, option --yes]"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "Confirmation impossible : pas de terminal interactif." \
      "Relancez avec --yes (ou YES=1 avec make) pour confirmer explicitement."
  fi
  printf '%s%s%s [o/N] ' "${C_BOLD}${C_YELLOW}" "${question}" "${C_RESET}"
  read -r answer
  [[ "${answer}" =~ ^([oOyY]|oui|yes)$ ]]
}

# --- Clé SSH dédiée au lab -----------------------------------------------------------
# Par défaut, une clé ed25519 propre au lab est générée dans .lab/ssh/ :
# on ne distribue pas votre clé personnelle sur des VMs de TP.
ensure_ssh_key() {
  if [[ -n "${SSH_PRIVATE_KEY_FILE:-}" ]]; then
    SSH_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_FILE/#\~/${HOME}}"
    [[ -f "${SSH_PRIVATE_KEY_FILE}" && -f "${SSH_PRIVATE_KEY_FILE}.pub" ]] ||
      die "Clé SSH introuvable : ${SSH_PRIVATE_KEY_FILE} (et/ou ${SSH_PRIVATE_KEY_FILE}.pub)." \
        "Corrigez SSH_PRIVATE_KEY_FILE dans .env, ou videz-la pour utiliser une clé générée."
  else
    SSH_PRIVATE_KEY_FILE="${LAB_STATE_DIR}/ssh/id_ed25519"
    if [[ ! -f "${SSH_PRIVATE_KEY_FILE}" ]]; then
      have ssh-keygen || die "ssh-keygen est introuvable." "Installez le client OpenSSH (paquet openssh-client)."
      mkdir -p "${LAB_STATE_DIR}/ssh"
      chmod 700 "${LAB_STATE_DIR}/ssh"
      info "Génération d'une clé SSH dédiée au lab : ${SSH_PRIVATE_KEY_FILE}"
      ssh-keygen -q -t ed25519 -N "" -C "k8s-lab@$(hostname -s 2>/dev/null || echo host)" -f "${SSH_PRIVATE_KEY_FILE}"
      chmod 600 "${SSH_PRIVATE_KEY_FILE}"
    fi
  fi
  export SSH_PRIVATE_KEY_FILE
}
