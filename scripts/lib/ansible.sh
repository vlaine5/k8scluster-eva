#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Installation de Kubernetes (kubeadm) par Ansible, commune à Vagrant et
#  Terraform : l'outil qui crée les VMs écrit un inventaire, Ansible fait le reste.
# =============================================================================

ansible_ensure_collections() {
  if ansible-galaxy collection list community.general 2>/dev/null | grep -q '^community.general' &&
    ansible-galaxy collection list ansible.posix 2>/dev/null | grep -q '^ansible.posix'; then
    return 0
  fi
  step "Installation des collections Ansible (ansible/requirements.yml)"
  run ansible-galaxy collection install -r "${LAB_ROOT}/ansible/requirements.yml"
}

# Paramètres Kubernetes de config/lab.env transmis à Ansible (extra vars).
ansible_write_vars() {
  local file="${LAB_STATE_DIR}/ansible/cluster-vars.yml"
  mkdir -p "${LAB_STATE_DIR}/ansible"
  cat >"${file}" <<VARS
# Généré par ./k8s-lab depuis config/lab.env et .env (ne pas modifier).
kubernetes_version: "${KUBERNETES_VERSION}"
pod_cidr: "${POD_CIDR}"
service_cidr: "${SERVICE_CIDR}"
cni: "${CNI}"
flannel_version: "${FLANNEL_VERSION}"
container_runtime: "${CONTAINER_RUNTIME}"
containerd_version: "${CONTAINERD_VERSION}"
VARS
  echo "${file}"
}

# ansible_install_kubernetes <inventaire (relatif à ansible/)> [options ansible-playbook...]
ansible_install_kubernetes() {
  local inventory="$1" vars_file
  shift
  [[ -s "${LAB_ROOT}/ansible/${inventory}" ]] ||
    die "Inventaire Ansible introuvable : ansible/${inventory}" \
      "Il est normalement généré par Vagrant ou Terraform juste avant cette étape."
  ansible_ensure_collections
  vars_file="$(ansible_write_vars)"
  step "Installation de Kubernetes avec Ansible + kubeadm (5 à 15 minutes)"
  info "Inventaire : ansible/${inventory}   |   Playbook : ansible/site.yml"
  (
    cd "${LAB_ROOT}/ansible" &&
      ANSIBLE_CONFIG="${LAB_ROOT}/ansible/ansible.cfg" run ansible-playbook -i "${inventory}" site.yml -e "@${vars_file}" "$@"
  ) || die "Le playbook Ansible a échoué (voir la tâche en erreur ci-dessus)." \
    "Relancer l'installation : ./k8s-lab deploy <mode> (idempotent, les VMs sont conservées)" \
    "Voir docs/troubleshooting.md"
}

# Récupère (à nouveau) le kubeconfig depuis le control-plane.
ansible_fetch_kubeconfig() {
  local inventory="$1"
  [[ -s "${LAB_ROOT}/ansible/${inventory}" ]] ||
    die "Inventaire Ansible introuvable : ansible/${inventory}" "Le cluster est-il déployé ? ./k8s-lab status"
  ansible_ensure_collections
  (
    cd "${LAB_ROOT}/ansible" &&
      ANSIBLE_CONFIG="${LAB_ROOT}/ansible/ansible.cfg" run ansible-playbook -i "${inventory}" kubeconfig.yml
  ) || die "Impossible de récupérer le kubeconfig depuis le control-plane."
}

# Oublie les clés SSH des VMs d'un inventaire (après destruction) : de
# nouvelles VMs réutiliseront les mêmes adresses avec de nouvelles clés.
known_hosts_forget() {
  local inventory="${LAB_ROOT}/ansible/$1" known="${LAB_STATE_DIR}/known_hosts" host port
  [[ -f "${inventory}" && -f "${known}" ]] || return 0
  while read -r host port; do
    [[ -n "${host}" ]] || continue
    if [[ -n "${port}" && "${port}" != "22" ]]; then
      ssh-keygen -R "[${host}]:${port}" -f "${known}" >/dev/null 2>&1 || true
    else
      ssh-keygen -R "${host}" -f "${known}" >/dev/null 2>&1 || true
    fi
  done < <(sed -n -E 's/.*ansible_host=([^ ]+)( .*ansible_port=([0-9]+))?.*/\1 \3/p' "${inventory}")
  rm -f "${known}.old"
}
