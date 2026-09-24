#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  ./k8s-lab doctor : vérifie les prérequis de chaque mode et explique
#  comment corriger ce qui manque (quoi, pourquoi, comment).
# =============================================================================

DOCTOR_ERRORS=0
DOCTOR_WARNINGS=0

d_ok()   { printf '  %s✔%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
d_info() { printf '  %s•%s %s\n' "${C_DIM}" "${C_RESET}" "$*"; }

# d_fail "problème" "pourquoi" "comment corriger" [lignes supplémentaires...]
d_fail() {
  DOCTOR_ERRORS=$((DOCTOR_ERRORS + 1))
  printf '  %s✘ %s%s\n' "${C_RED}" "$1" "${C_RESET}"
  shift
  local line
  for line in "$@"; do printf '      %s\n' "${line}"; done
}

d_warn() {
  DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
  printf '  %s! %s%s\n' "${C_YELLOW}" "$1" "${C_RESET}"
  shift
  local line
  for line in "$@"; do printf '      %s\n' "${line}"; done
}

host_os() {
  case "$(uname -s)" in
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi
      ;;
    Darwin) echo macos ;;
    *) echo other ;;
  esac
}

# Mémoire disponible en Mo (0 si inconnue).
host_available_memory_mb() {
  if [[ -r /proc/meminfo ]]; then
    awk '/^MemAvailable:/ {print int($2/1024); exit}' /proc/meminfo
  elif have sysctl && sysctl -n hw.memsize >/dev/null 2>&1; then
    echo $(($(sysctl -n hw.memsize) / 1024 / 1024))
  else
    echo 0
  fi
}

check_memory() {
  local needed_mb="$1" what="$2" available_mb
  available_mb="$(host_available_memory_mb)"
  if ((available_mb == 0)); then
    d_info "Mémoire disponible inconnue (besoin estimé : ${needed_mb} Mo pour ${what})."
  elif ((available_mb < needed_mb)); then
    d_warn "Mémoire disponible : ${available_mb} Mo, besoin estimé : ${needed_mb} Mo (${what})." \
      "Le cluster risque d'être lent ou instable. Réduisez WORKER_COUNT ou NODE_MEMORY_MB dans .env."
  else
    d_ok "Mémoire disponible : ${available_mb} Mo (besoin estimé : ${needed_mb} Mo)"
  fi
}

# --- Outils ------------------------------------------------------------------------

check_kubectl() {
  if ! have kubectl; then
    d_fail "kubectl est introuvable." \
      "kubectl est l'outil en ligne de commande pour piloter n'importe quel cluster Kubernetes." \
      "Installation : https://kubernetes.io/docs/tasks/tools/ (version conseillée : ${KUBECTL_VERSION})" \
      "Ou, sans sudo (Linux/macOS) : scripts/install-tools.sh kubectl"
    return
  fi
  local version
  version="$(kubectl version --client 2>/dev/null | sed -n 's/^Client Version: //p')"
  local want_minor have_minor
  want_minor="$(echo "${KUBECTL_VERSION#v}" | cut -d. -f2)"
  have_minor="$(echo "${version#v}" | cut -d. -f2)"
  if [[ -n "${have_minor}" && -n "${want_minor}" ]] && ((have_minor + 1 < want_minor || have_minor > want_minor + 1)); then
    d_warn "kubectl ${version} : trop éloigné de Kubernetes ${KUBECTL_VERSION} (écart max supporté : 1 version mineure)." \
      "Mettez kubectl à jour : https://kubernetes.io/docs/tasks/tools/"
  else
    d_ok "kubectl ${version}"
  fi
}

check_container_engine() {
  if have docker; then
    local cgroup_version
    if ! cgroup_version="$(docker info --format '{{.CgroupVersion}}' 2>/dev/null)"; then
      d_fail "Docker est installé mais ne répond pas (démon arrêté, ou droits insuffisants)." \
        "Kind et Minikube (driver docker) créent leurs nœuds sous forme de conteneurs Docker." \
        "Linux : sudo systemctl enable --now docker" \
        "        puis, pour éviter sudo : sudo usermod -aG docker \$USER  (et reconnectez-vous)" \
        "macOS / Windows : démarrez Docker Desktop." \
        "Puis relancez : $(hint_cmd doctor kind)"
      return
    fi
    d_ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null) (démon joignable)"
    if [[ "${cgroup_version}" == "1" ]]; then
      d_fail "Docker utilise cgroup v1." \
        "Kubernetes >= 1.35 refuse par défaut de démarrer sur cgroup v1 : les nœuds Kind/Minikube ne démarreront pas." \
        "Utilisez une distribution récente (Ubuntu 22.04+, Debian 12+, Fedora) ou WSL2 à jour."
    fi
  elif have podman; then
    d_warn "Docker est absent, Podman est présent." \
      "Kind fonctionne avec Podman en mode expérimental : export KIND_EXPERIMENTAL_PROVIDER=podman" \
      "Minikube : MINIKUBE_DRIVER=podman dans .env"
  else
    d_fail "Docker est requis pour Kind (et pour Minikube avec le driver docker), mais il est introuvable." \
      "Kind exécute les nœuds Kubernetes dans des conteneurs Docker." \
      "Linux : https://docs.docker.com/engine/install/" \
      "macOS / Windows : https://docs.docker.com/desktop/" \
      "Installez Docker puis relancez : $(hint_cmd doctor kind)"
  fi
}

check_kind() {
  if ! have kind; then
    d_fail "kind est introuvable." \
      "kind (Kubernetes IN Docker) crée un cluster dont chaque nœud est un conteneur." \
      "Installation : https://kind.sigs.k8s.io/docs/user/quick-start/#installation (version conseillée : ${KIND_VERSION})" \
      "Ou, sans sudo (Linux/macOS) : scripts/install-tools.sh kind"
    return
  fi
  local version
  version="$(kind version 2>/dev/null | awk '{print $2}')"
  if version_ge "${version}" "${KIND_VERSION}"; then
    d_ok "kind ${version}"
  else
    d_warn "kind ${version} est plus ancien que la version conseillée ${KIND_VERSION}." \
      "L'image ${KIND_NODE_IMAGE%%@*} est prévue pour kind ${KIND_VERSION}. Mettez kind à jour."
  fi
}

check_minikube() {
  if ! have minikube; then
    d_fail "minikube est introuvable." \
      "Minikube crée un cluster local, avec des addons prêts à l'emploi (dashboard, ingress...)." \
      "Installation : https://minikube.sigs.k8s.io/docs/start/ (version conseillée : ${MINIKUBE_VERSION})" \
      "Ou, sans sudo (Linux/macOS) : scripts/install-tools.sh minikube"
    return
  fi
  local version
  version="$(minikube version --short 2>/dev/null)"
  if version_ge "${version}" "${MINIKUBE_VERSION}"; then
    d_ok "minikube ${version}"
  else
    d_warn "minikube ${version} est plus ancien que la version conseillée ${MINIKUBE_VERSION}." \
      "Kubernetes ${MINIKUBE_KUBERNETES_VERSION} pourrait ne pas être supporté. Mettez minikube à jour."
  fi
}

check_minikube_driver() {
  local driver="${MINIKUBE_DRIVER:-}"
  if [[ -n "${driver}" ]]; then
    case "${driver}" in
      docker) check_container_engine ;;
      podman)
        if have podman; then d_ok "driver podman"; else d_fail "Driver podman demandé mais podman est introuvable."; fi
        ;;
      kvm2)
        if have virsh && [[ -e /dev/kvm ]]; then d_ok "driver kvm2 (libvirt + /dev/kvm)"; else
          d_fail "Driver kvm2 demandé mais libvirt ou /dev/kvm est absent." \
            "Ubuntu : sudo apt install qemu-kvm libvirt-daemon-system && sudo usermod -aG libvirt \$USER"
        fi
        ;;
      virtualbox)
        if have VBoxManage; then d_ok "driver virtualbox"; else d_fail "Driver virtualbox demandé mais VirtualBox est introuvable."; fi
        ;;
      *) d_info "Driver minikube \"${driver}\" : non vérifié par doctor." ;;
    esac
    return
  fi
  # Détection automatique : minikube choisira lui-même parmi les drivers disponibles.
  if have docker && docker info >/dev/null 2>&1; then
    d_ok "Driver minikube détecté : docker"
    check_container_engine
  elif have podman; then
    d_ok "Driver minikube détecté : podman"
  elif have virsh && [[ -e /dev/kvm ]]; then
    d_ok "Driver minikube détecté : kvm2"
  elif have VBoxManage; then
    d_ok "Driver minikube détecté : virtualbox"
  elif [[ "$(host_os)" == "macos" ]] && (have vfkit || have qemu-system-aarch64 || have qemu-system-x86_64); then
    d_ok "Driver minikube détecté : vfkit/qemu"
  else
    d_fail "Aucun driver utilisable par minikube n'a été détecté." \
      "Minikube a besoin d'un moteur pour héberger le nœud : Docker (le plus simple), Podman, KVM ou VirtualBox." \
      "Installez Docker : https://docs.docker.com/engine/install/  puis relancez : $(hint_cmd doctor minikube)"
  fi
}

check_ssh() {
  if have ssh && have ssh-keygen; then
    d_ok "Client OpenSSH ($(ssh -V 2>&1 | cut -d, -f1))"
  else
    d_fail "Le client SSH (ssh, ssh-keygen) est introuvable." \
      "Ansible se connecte aux VMs en SSH." \
      "Ubuntu/Debian : sudo apt install openssh-client"
  fi
}

check_ansible() {
  if ! have ansible-playbook; then
    d_fail "Ansible est introuvable." \
      "Ansible installe Kubernetes (kubeadm) sur les VMs, quel que soit l'outil qui les a créées." \
      "Installation conseillée (version récente) : pipx install --include-deps ansible" \
      "  (Ubuntu/Debian : sudo apt install pipx && pipx ensurepath)" \
      "Doc : https://docs.ansible.com/ansible/latest/installation_guide/"
    return
  fi
  local version
  version="$(ansible-playbook --version 2>/dev/null | head -n1 | sed -E 's/.*core ([0-9.]+).*/\1/')"
  if version_ge "${version}" "2.18.0"; then
    d_ok "ansible-core ${version}"
  else
    d_fail "ansible-core ${version} est trop ancien (2.18 minimum)." \
      "Les collections utilisées (community.general 13) exigent ansible-core >= 2.18." \
      "Les paquets APT d'Ubuntu 24.04 sont trop anciens : pipx install --include-deps ansible"
  fi
  if ansible-galaxy collection list community.general 2>/dev/null | grep -q '^community.general' &&
    ansible-galaxy collection list ansible.posix 2>/dev/null | grep -q '^ansible.posix'; then
    d_ok "Collections Ansible ansible.posix et community.general"
  else
    d_info "Collections Ansible manquantes : elles seront installées au déploiement (ansible/requirements.yml)."
  fi
}

check_terraform() {
  local bin
  bin="$(terraform_bin)"
  if [[ -z "${bin}" ]]; then
    d_fail "Terraform (ou OpenTofu) est introuvable." \
      "Terraform crée les VMs à partir du code du dossier terraform/ (Infrastructure as Code)." \
      "Terraform : https://developer.hashicorp.com/terraform/install" \
      "OpenTofu (alternative libre, compatible) : https://opentofu.org/docs/intro/install/"
    return
  fi
  local version
  version="$("${bin}" version 2>/dev/null | head -n1 | sed -E 's/^[^0-9]*v?([0-9.]+).*/\1/')"
  if version_ge "${version}" "1.9.0"; then
    d_ok "${bin} ${version}"
  else
    d_fail "${bin} ${version} est trop ancien (1.9 minimum)." "Mettez-le à jour (conseillé : ${TERRAFORM_VERSION})."
  fi
}

check_vagrant() {
  if ! have vagrant; then
    d_fail "Vagrant est introuvable." \
      "Vagrant crée et démarre les VMs décrites dans vagrant/Vagrantfile." \
      "Installation : https://developer.hashicorp.com/vagrant/install"
    return
  fi
  d_ok "$(vagrant --version 2>/dev/null)"

  local plugins
  plugins="$(vagrant plugin list 2>/dev/null || true)"
  case "${VAGRANT_PROVIDER}" in
    virtualbox)
      if have VBoxManage; then d_ok "VirtualBox $(VBoxManage --version 2>/dev/null)"; else
        d_fail "VirtualBox est introuvable (VAGRANT_PROVIDER=virtualbox)." \
          "Installation : https://www.virtualbox.org/wiki/Downloads" \
          "Sous Linux avec KVM, préférez VAGRANT_PROVIDER=libvirt dans .env."
      fi
      ;;
    libvirt)
      if grep -q '^vagrant-libvirt' <<<"${plugins}"; then
        d_ok "Plugin vagrant-libvirt"
      else
        d_fail "Plugin vagrant-libvirt manquant." \
          "Installation : https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html"
      fi
      check_libvirt_host
      ;;
    vmware_desktop)
      if grep -q '^vagrant-vmware-desktop' <<<"${plugins}"; then
        d_ok "Plugin vagrant-vmware-desktop"
      else
        d_fail "Plugin vagrant-vmware-desktop manquant." \
          "Installez VMware Workstation/Fusion, Vagrant VMware Utility puis :" \
          "vagrant plugin install vagrant-vmware-desktop" \
          "Doc : https://developer.hashicorp.com/vagrant/docs/providers/vmware/installation"
      fi
      ;;
    vmware_esxi)
      d_warn "Mode historique ESXi : le plugin vagrant-vmware-esxi n'est plus maintenu depuis 2022." \
        "Il reste proposé pour les ESXi autonomes (sans vCenter). Voir docs/deploy-vagrant.md."
      if grep -q '^vagrant-vmware-esxi' <<<"${plugins}"; then
        d_ok "Plugin vagrant-vmware-esxi"
      else
        d_fail "Plugin vagrant-vmware-esxi manquant." "vagrant plugin install vagrant-vmware-esxi"
      fi
      if have ovftool; then
        d_ok "VMware OVF Tool"
      else
        d_fail "ovftool (VMware OVF Tool) est introuvable." "Il est requis par vagrant-vmware-esxi. Voir docs/deploy-vagrant.md."
      fi
      if [[ -n "${ESXI_HOSTNAME:-}" ]]; then
        d_ok "ESXI_HOSTNAME=${ESXI_HOSTNAME}"
      else
        d_fail "ESXI_HOSTNAME n'est pas défini." "Ajoutez-le dans .env (voir .env.example)."
      fi
      if [[ -n "${ESXI_PASSWORD:-}" ]]; then
        d_ok "ESXI_PASSWORD défini (valeur masquée)"
      else
        d_fail "ESXI_PASSWORD n'est pas défini." "Ajoutez-le dans .env : il n'est jamais écrit dans le Vagrantfile."
      fi
      ;;
    *)
      d_fail "VAGRANT_PROVIDER=${VAGRANT_PROVIDER} n'est pas supporté." \
        "Valeurs possibles : virtualbox, libvirt, vmware_desktop, vmware_esxi."
      ;;
  esac
}

check_libvirt_host() {
  if [[ "$(host_os)" != "linux" ]]; then
    d_fail "libvirt/KVM nécessite un hôte Linux." "Sous macOS/Windows, utilisez Vagrant + VirtualBox, ou Kind."
    return
  fi
  if [[ -e /dev/kvm ]]; then
    d_ok "Virtualisation matérielle disponible (/dev/kvm)"
  else
    d_warn "/dev/kvm est absent : pas de virtualisation matérielle." \
      "Activez VT-x/AMD-V dans le BIOS (ou la virtualisation imbriquée si vous êtes déjà dans une VM)." \
      "Terraform libvirt peut fonctionner en émulation (très lent) : domain_type = \"qemu\" dans terraform.tfvars."
  fi
  if ! have virsh; then
    d_fail "libvirt (virsh) est introuvable." \
      "Ubuntu/Debian : sudo apt install qemu-kvm libvirt-daemon-system" \
      "puis : sudo usermod -aG libvirt \$USER  (et reconnectez-vous)"
    return
  fi
  local uri="${LIBVIRT_DEFAULT_URI:-qemu:///system}"
  if virsh -c "${uri}" version >/dev/null 2>&1; then
    d_ok "libvirt joignable (${uri})"
  else
    d_fail "Impossible de se connecter à libvirt (${uri})." \
      "Le démon est-il démarré ? sudo systemctl enable --now libvirtd" \
      "Votre utilisateur est-il dans le groupe libvirt ? sudo usermod -aG libvirt \$USER (puis reconnexion)"
  fi
}

check_tfvars() {
  local provider="$1" dir="${LAB_ROOT}/terraform/providers/$1"
  if [[ -f "${dir}/terraform.tfvars" ]]; then
    d_ok "terraform/providers/${provider}/terraform.tfvars présent"
  elif [[ "${provider}" == "libvirt" ]]; then
    d_info "Pas de terraform.tfvars : valeurs par défaut utilisées (réseau 192.168.123.0/24)."
  else
    d_fail "terraform/providers/${provider}/terraform.tfvars est absent." \
      "Ce fichier décrit VOTRE infrastructure (nœud, stockage, réseau...)." \
      "cp terraform/providers/${provider}/terraform.tfvars.example terraform/providers/${provider}/terraform.tfvars" \
      "puis éditez-le (aucun secret dedans). Guide : docs/deploy-${provider}.md"
  fi
}

check_proxmox_access() {
  if [[ -z "${PROXMOX_VE_ENDPOINT:-}" ]]; then
    d_fail "PROXMOX_VE_ENDPOINT n'est pas défini." \
      "Ajoutez l'URL de votre Proxmox dans .env, ex : PROXMOX_VE_ENDPOINT=https://pve.example.lan:8006/"
    return
  fi
  d_ok "PROXMOX_VE_ENDPOINT=${PROXMOX_VE_ENDPOINT}"
  if [[ -n "${PROXMOX_VE_API_TOKEN:-}" ]]; then
    d_ok "PROXMOX_VE_API_TOKEN défini (valeur masquée)"
  elif [[ -n "${PROXMOX_VE_USERNAME:-}" && -n "${PROXMOX_VE_PASSWORD:-}" ]]; then
    d_warn "Authentification Proxmox par mot de passe." "Un token API dédié est préférable (révocable, droits limités)."
  else
    d_fail "Aucun identifiant Proxmox (PROXMOX_VE_API_TOKEN) dans .env." \
      "Créez un token API dédié : docs/deploy-proxmox.md"
  fi
  local insecure=() code
  [[ "${PROXMOX_VE_INSECURE:-false}" == "true" ]] && insecure=(--insecure)
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 ${insecure[@]+"${insecure[@]}"} \
    "${PROXMOX_VE_ENDPOINT%/}/api2/json/version" 2>/dev/null || true)"
  case "${code}" in
    200 | 401) d_ok "API Proxmox joignable" ;;
    000 | "") d_fail "API Proxmox injoignable (${PROXMOX_VE_ENDPOINT})." \
      "Vérifiez l'URL, le réseau, et le certificat (PROXMOX_VE_INSECURE=true si auto-signé)." ;;
    *) d_warn "API Proxmox : réponse HTTP ${code} inattendue." ;;
  esac
}

check_vsphere_access() {
  local var
  for var in VSPHERE_SERVER VSPHERE_USER VSPHERE_PASSWORD; do
    if [[ -n "${!var:-}" ]]; then
      if [[ "${var}" == "VSPHERE_PASSWORD" ]]; then d_ok "${var} défini (valeur masquée)"; else d_ok "${var}=${!var}"; fi
    else
      d_fail "${var} n'est pas défini." "Ajoutez-le dans .env (voir .env.example)."
    fi
  done
  d_info "vCenter est obligatoire : le provider vSphere ne sait pas cloner une VM sur un ESXi autonome."
}

# --- Diagnostic par mode ------------------------------------------------------------

doctor_mode() {
  local mode="$1" provider="${2:-}"
  DOCTOR_ERRORS=0
  DOCTOR_WARNINGS=0
  case "${mode}" in
    kind)
      check_container_engine
      check_kind
      check_kubectl
      check_memory $(((WORKER_COUNT + 1) * 700 + 1024)) "kind, $((WORKER_COUNT + 1)) nœud(s)"
      ;;
    minikube)
      check_minikube
      check_minikube_driver
      check_kubectl
      check_memory $((MINIKUBE_NODES * MINIKUBE_MEMORY_MB)) "minikube, ${MINIKUBE_NODES} nœud(s)"
      ;;
    vagrant)
      check_vagrant
      check_ansible
      check_ssh
      check_kubectl
      check_memory $(((WORKER_COUNT + 1) * NODE_MEMORY_MB)) "$((WORKER_COUNT + 1)) VM(s) de ${NODE_MEMORY_MB} Mo"
      ;;
    terraform)
      check_terraform
      check_ansible
      check_ssh
      check_kubectl
      case "${provider}" in
        proxmox)
          check_tfvars proxmox
          check_proxmox_access
          ;;
        vsphere)
          check_tfvars vsphere
          check_vsphere_access
          ;;
        libvirt)
          check_tfvars libvirt
          check_libvirt_host
          check_memory $(((WORKER_COUNT + 1) * NODE_MEMORY_MB)) "$((WORKER_COUNT + 1)) VM(s) de ${NODE_MEMORY_MB} Mo"
          ;;
        *) d_fail "Provider Terraform inconnu : \"${provider}\"." "Valeurs possibles : ${TERRAFORM_PROVIDERS}." ;;
      esac
      ;;
    *) d_fail "Mode inconnu : \"${mode}\"." "Modes : kind, minikube, vagrant, terraform <provider>." ;;
  esac
  return "${DOCTOR_ERRORS}"
}

# ./k8s-lab doctor [mode] [provider]
cmd_doctor() {
  local mode="${1:-}" provider="${2:-}"
  if [[ -n "${mode}" ]]; then
    step "Prérequis du mode ${mode}${provider:+ ${provider}}"
    if doctor_mode "${mode}" "${provider}"; then
      printf '\n'
      ok "Tout est prêt pour : $(hint_cmd deploy "${mode}" "${provider}")"
      return 0
    fi
    printf '\n'
    error "${DOCTOR_ERRORS} problème(s) à corriger avant de déployer (détails ci-dessus)."
    return 1
  fi

  # Sans argument : bilan de tous les modes.
  local summary=() entry m p label
  for entry in kind minikube vagrant "terraform proxmox" "terraform vsphere" "terraform libvirt"; do
    m="${entry%% *}"
    p=""
    [[ "${entry}" == *" "* ]] && p="${entry#* }"
    label="${m}${p:+ ${p}}"
    step "Mode ${label}"
    if doctor_mode "${m}" "${p}"; then
      summary+=("${C_GREEN}prêt${C_RESET}          ${label}")
    else
      summary+=("${C_RED}${DOCTOR_ERRORS} problème(s)${C_RESET} ${label}")
    fi
  done
  step "Bilan"
  printf '  %s\n' "${summary[@]}"
  printf '\n  Détail d'"'"'un mode : %s\n' "$(hint_cmd doctor '<mode>')"
  return 0
}
