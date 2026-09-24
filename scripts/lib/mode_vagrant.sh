#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode vagrant : VMs créées par Vagrant, Kubernetes installé par
#  Ansible + kubeadm (niveau 2).
#
#    vagrant up            -> VMs + ansible/inventories/vagrant.ini
#    ansible-playbook      -> kubeadm init / join, CNI, vérifications
# =============================================================================

VAGRANT_INVENTORY="inventories/vagrant.ini"

vagrant_context() { echo "${CLUSTER_NAME}-vagrant"; }

vagrant_cmd() {
  (cd "${LAB_ROOT}/vagrant" && VAGRANT_CHECKPOINT_DISABLE=1 run vagrant "$@")
}

# Vrai si au moins une VM du lab a été créée par Vagrant.
vagrant_has_machines() {
  [[ -d "${LAB_ROOT}/vagrant/.vagrant/machines" ]] &&
    find "${LAB_ROOT}/vagrant/.vagrant/machines" -name id -type f 2>/dev/null | grep -q .
}

vagrant_deploy() {
  local context
  context="$(vagrant_context)"
  require_doctor vagrant

  if [[ "${RECREATE:-0}" == "1" ]] && vagrant_has_machines; then
    vagrant_destroy
  fi

  step "Création / démarrage des VMs avec Vagrant (provider ${VAGRANT_PROVIDER})"
  info "Les VMs existantes sont conservées : vagrant up ne fait que créer ce qui manque."
  vagrant_cmd up --provider "${VAGRANT_PROVIDER}" ||
    die "vagrant up a échoué." \
      "État des VMs : cd vagrant && vagrant status" \
      "Voir docs/vagrant.md et docs/troubleshooting.md"

  ansible_install_kubernetes "${VAGRANT_INVENTORY}"
  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  smoke_basic "${context}"
  kubeconfig_hint "${context}"
  printf '\nSe connecter à une VM : cd vagrant && vagrant ssh %s-cp-1\n' "${NODE_HOSTNAME_PREFIX}"
}

vagrant_destroy() {
  local context
  context="$(vagrant_context)"
  if ! vagrant_has_machines; then
    info "Aucune VM Vagrant : rien à détruire."
  else
    confirm "Détruire TOUTES les VMs Vagrant du lab (provider ${VAGRANT_PROVIDER}) ?" || die "Destruction annulée."
    vagrant_cmd destroy --force || die "vagrant destroy a échoué." "cd vagrant && vagrant status"
  fi
  known_hosts_forget "${VAGRANT_INVENTORY}"
  rm -f "${LAB_ROOT}/ansible/${VAGRANT_INVENTORY}" "${LAB_KUBE_DIR}/clusters/${context}.yaml"
  kubeconfig_remove "${context}" "${context}" "${context}-admin"
  ok "Lab Vagrant nettoyé (VMs, inventaire, kubeconfig)."
}

vagrant_status() {
  if vagrant_has_machines; then
    status_line up vagrant "VMs présentes (contexte $(vagrant_context)) : cd vagrant && vagrant status"
  else
    status_line none vagrant "aucune VM"
  fi
}

vagrant_kubeconfig() {
  local context
  context="$(vagrant_context)"
  ansible_fetch_kubeconfig "${VAGRANT_INVENTORY}"
  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  kubeconfig_hint "${context}"
}
