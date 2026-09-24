#!/usr/bin/env bash
# =============================================================================
#  Installe kind, kubectl et/ou minikube aux versions de config/lab.env,
#  SANS sudo, dans ~/.local/bin (modifiable : INSTALL_DIR=...).
#  Chaque binaire est vérifié par son empreinte SHA-256 officielle.
#
#    scripts/install-tools.sh kind kubectl          # Linux ou macOS, amd64 ou arm64
#    scripts/install-tools.sh minikube
#
#  Docker, Vagrant, Terraform et Ansible s'installent avec le gestionnaire de
#  paquets de votre système : voir ./k8s-lab doctor.
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"

lab_value() {
  local value
  value="$(printenv "$1" || true)"
  [[ -n "${value}" ]] || value="$(sed -n -E "s/^$1=(.*)$/\1/p" "${ROOT}/config/lab.env" | tail -n1)"
  echo "${value}"
}

fail() {
  printf '[erreur] %s\n' "$*" >&2
  exit 1
}

detect_platform() {
  case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=darwin ;;
    *) fail "Système non supporté par ce script : $(uname -s). Utilisez la documentation officielle de chaque outil." ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) ARCH=amd64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
    *) fail "Architecture non supportée : $(uname -m)." ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# download_verified <nom> <url du binaire> <url de l'empreinte>
download_verified() {
  local name="$1" url="$2" sum_url="$3" tmp expected actual
  tmp="$(mktemp -d)"
  printf 'Téléchargement de %s : %s\n' "${name}" "${url}"
  curl -fsSL --retry 3 -o "${tmp}/${name}" "${url}" || fail "Téléchargement impossible : ${url}"
  expected="$(curl -fsSL --retry 3 "${sum_url}" | awk '{print $1}')" || fail "Empreinte introuvable : ${sum_url}"
  actual="$(sha256_of "${tmp}/${name}")"
  if [[ -z "${expected}" || "${expected}" != "${actual}" ]]; then
    rm -rf "${tmp}"
    fail "Empreinte SHA-256 incorrecte pour ${name} (attendu ${expected}, obtenu ${actual}) : installation annulée."
  fi
  mkdir -p "${INSTALL_DIR}"
  install -m 0755 "${tmp}/${name}" "${INSTALL_DIR}/${name}"
  rm -rf "${tmp}"
  printf '[ok] %s installé dans %s (SHA-256 vérifié)\n' "${name}" "${INSTALL_DIR}"
}

install_kind() {
  local version
  version="$(lab_value KIND_VERSION)"
  download_verified kind \
    "https://kind.sigs.k8s.io/dl/${version}/kind-${OS}-${ARCH}" \
    "https://kind.sigs.k8s.io/dl/${version}/kind-${OS}-${ARCH}.sha256sum"
}

install_kubectl() {
  local version
  version="$(lab_value KUBECTL_VERSION)"
  download_verified kubectl \
    "https://dl.k8s.io/release/${version}/bin/${OS}/${ARCH}/kubectl" \
    "https://dl.k8s.io/release/${version}/bin/${OS}/${ARCH}/kubectl.sha256"
}

install_minikube() {
  local version
  version="$(lab_value MINIKUBE_VERSION)"
  download_verified minikube \
    "https://storage.googleapis.com/minikube/releases/${version}/minikube-${OS}-${ARCH}" \
    "https://storage.googleapis.com/minikube/releases/${version}/minikube-${OS}-${ARCH}.sha256"
}

main() {
  (($# > 0)) || fail "Précisez les outils à installer : kind, kubectl, minikube (ex : $0 kind kubectl)"
  detect_platform
  local tool
  for tool in "$@"; do
    case "${tool}" in
      kind | kubectl | minikube) "install_${tool}" ;;
      *) fail "Outil non géré par ce script : ${tool} (kind, kubectl, minikube)." ;;
    esac
  done
  # shellcheck disable=SC2016 # $PATH doit rester littéral dans le conseil affiché
  case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *) printf '\n[attention] %s n'"'"'est pas dans votre PATH. Ajoutez à ~/.bashrc :\n  export PATH="%s:$PATH"\n' "${INSTALL_DIR}" "${INSTALL_DIR}" ;;
  esac
}

main "$@"
