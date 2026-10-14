#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Ansible : installation de Kubernetes (kubeadm) sur les nœuds, addons depuis
#  votre poste, opérations de maintenance. Toutes les variables viennent du
#  résolveur (scripts/labctl ansible-vars) : un seul fichier JSON, sans secret.
# =============================================================================

ansible_ensure_collections() {
  local collection missing=0
  for collection in community.general ansible.posix kubernetes.core; do
    ansible-galaxy collection list "${collection}" 2>/dev/null | grep -q "^${collection} " || missing=1
  done
  ((missing == 0)) && return 0
  step "Installation des collections Ansible (ansible/requirements.yml)"
  run ansible-galaxy collection install -r "${LAB_ROOT}/ansible/requirements.yml"
}

# Inventaire « localhost » des playbooks exécutés depuis votre poste (addons, CNI kind) :
# l'interpréteur Python est celui d'Ansible (avec la bibliothèque kubernetes).
ansible_local_inventory() {
  local file="${LAB_STATE_DIR}/ansible/localhost.ini"
  mkdir -p "${LAB_STATE_DIR}/ansible"
  cat >"${file}" <<'INV'
# Généré par ./k8s-lab : playbooks exécutés sur votre poste (API Kubernetes).
localhost ansible_connection=local ansible_python_interpreter="{{ ansible_playbook_python }}"
INV
  echo "${file}"
}

# ansible_playbook <inventaire> <playbook> [options ansible-playbook...]
# Lance un playbook depuis ansible/ avec les variables du plan courant.
ansible_playbook() {
  local inventory="$1" playbook="$2" vars_file
  shift 2
  [[ "${inventory}" == /* ]] || inventory="${LAB_ROOT}/ansible/${inventory}"
  [[ -s "${inventory}" ]] || die "Inventaire Ansible introuvable : ${inventory#"${LAB_ROOT}"/}" \
    "Vagrant ou Terraform l'écrivent juste avant cette étape ; en mode existing : EXISTING_INVENTORY."
  ansible_ensure_collections
  vars_file="$(lab_ansible_vars)"
  local extra=(-e "@${vars_file}")
  # Le nom des fichiers (kubeconfig, sauvegardes, marqueur) suit le contexte du mode.
  lab_is_kubeadm && extra+=(-e "cluster_name=${LAB_R_CONTEXT}")
  # Variables Ansible supplémentaires (fichier) : réservé aux tests du framework
  # (nœuds conteneurs de tests/kubeadm-in-docker) ou à un usage avancé documenté.
  [[ -z "${LAB_ANSIBLE_EXTRA_VARS:-}" ]] || extra+=(-e "@${LAB_ANSIBLE_EXTRA_VARS}")
  (
    cd "${LAB_ROOT}/ansible" &&
      ANSIBLE_CONFIG="${LAB_ROOT}/ansible/ansible.cfg" run ansible-playbook -i "${inventory}" "${playbook}" "${extra[@]}" "$@"
  )
}

# ansible_install_kubernetes <inventaire> : site.yml (préparation, kubeadm, CNI, vérifications).
ansible_install_kubernetes() {
  local inventory="$1"
  step "Installation de Kubernetes avec Ansible + kubeadm (5 à 20 minutes)"
  info "Inventaire : ${inventory}   |   Playbook : ansible/site.yml"
  ansible_playbook "${inventory}" site.yml ||
    die "Le playbook Ansible a échoué (voir la tâche en erreur ci-dessus)." \
      "Relancer l'installation : $(hint_cmd deploy "${LAB_MODE:-<mode>}" "${LAB_PROVIDER:-}") (sans risque : rien n'est réinitialisé)" \
      "Voir docs/troubleshooting.md"
}

# Récupère (à nouveau) le kubeconfig depuis le premier control-plane.
ansible_fetch_kubeconfig() {
  ansible_playbook "$1" kubeconfig.yml ||
    die "Impossible de récupérer le kubeconfig depuis le control-plane."
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
