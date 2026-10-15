#!/usr/bin/env bash
# shellcheck shell=bash
# Prepare a fresh Debian/Ubuntu control VM for Terraform + Proxmox deployments.
# No Proxmox API calls, cluster creation, or changes to .env.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
export PATH="${ROOT}/.venv/bin:${INSTALL_DIR}:${PATH}"

die() { printf '[error] %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ "$(uname -s)" == Linux ]] || die "Linux only (Debian/Ubuntu)."
[[ -r /etc/os-release ]] || die "/etc/os-release missing."
# shellcheck disable=SC1091
. /etc/os-release
case "${ID}" in
  debian|ubuntu) ;;
  *) die "Unsupported OS: ${ID}. Use Debian or Ubuntu." ;;
esac
[[ "$(uname -m)" == x86_64 || "$(uname -m)" == aarch64 ]] || die "Unsupported CPU architecture."
have apt-get || die "apt-get not found."
have curl || true

if (( EUID == 0 )); then
  APT=(apt-get)
else
  have sudo || die "sudo is required to install system packages."
  APT=(sudo apt-get)
fi

info "Install OS packages (does not install Docker or modify Proxmox)"
"${APT[@]}" update
DEBIAN_FRONTEND=noninteractive "${APT[@]}" install -y \
  ca-certificates curl git gnupg make openssh-client \
  python3 python3-venv python3-pip unzip jq

info "Install Python virtual environment and Ansible"
if [[ ! -x "${ROOT}/.venv/bin/python" ]]; then
  python3 -m venv "${ROOT}/.venv"
fi
"${ROOT}/.venv/bin/python" -m pip install --upgrade pip
"${ROOT}/.venv/bin/python" -m pip install -r "${ROOT}/requirements-dev.txt"
"${ROOT}/.venv/bin/ansible-galaxy" collection install -r "${ROOT}/ansible/requirements.yml"

info "Install kubectl and Helm from pinned versions (SHA-256 checked)"
INSTALL_DIR="${INSTALL_DIR}" bash "${ROOT}/scripts/install-tools.sh" kubectl helm

info "Install Terraform (pinned version, checksum verified)"
if ! have terraform; then
  version="$(sed -n -E 's/^TERRAFORM_VERSION=(.*)$/\1/p' "${ROOT}/config/lab.env" | tail -n 1)"
  [[ "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid TERRAFORM_VERSION in config/lab.env: ${version}"
  version="${version#v}"
  case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
  filename="terraform_${version}_linux_${arch}.zip"
  base="https://releases.hashicorp.com/terraform/${version}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  curl -fsSL --retry 3 "${base}/${filename}" -o "${tmp}/${filename}"
  curl -fsSL --retry 3 "${base}/terraform_${version}_SHA256SUMS" -o "${tmp}/SHA256SUMS"
  expected="$(awk -v f="${filename}" '$2 == f {print $1}' "${tmp}/SHA256SUMS")"
  [[ "${expected}" =~ ^[a-fA-F0-9]{64}$ ]] || die "No checksum for ${filename}"
  actual="$(sha256sum "${tmp}/${filename}" | awk '{print $1}')"
  [[ "${actual}" == "${expected}" ]] || die "Terraform SHA-256 mismatch"
  unzip -q "${tmp}/${filename}" terraform -d "${tmp}"
  mkdir -p "${INSTALL_DIR}"
  install -m 0755 "${tmp}/terraform" "${INSTALL_DIR}/terraform"
  rm -rf "${tmp}"
  trap - EXIT
else
  info "Terraform already installed: $(terraform version | head -n 1)"
fi

info "Configure PATH for future interactive Bash sessions"
if [[ -f "${HOME}/.bashrc" ]] && ! grep -Fq '# k8s-lab GitOps tools' "${HOME}/.bashrc"; then
  printf '\n# k8s-lab GitOps tools\nexport PATH="%s:$PATH"\n' "${INSTALL_DIR}" >> "${HOME}/.bashrc"
fi

info "Tool versions"
terraform version | head -n 1
ansible-playbook --version | head -n 1
kubectl version --client
helm version --short

printf '\n[ok] Control VM tools installed.\n'
printf 'Next: source .venv/bin/activate && make doctor MODE=terraform PROVIDER=proxmox\n'
printf 'Set PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN in .env separately.\n'
printf 'No Proxmox resources were changed.\n'
