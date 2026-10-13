#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode existing : Kubernetes (kubeadm) installé sur des machines Linux qui
#  existent déjà (bare metal, VMs créées à la main), décrites par un inventaire
#  Ansible (EXISTING_INVENTORY). Aucune machine n'est créée ni supprimée.
#
#    1. validation de la configuration et de l'inventaire (résolveur)
#    2. contrôles préalables en LECTURE SEULE (preflight.yml) : OS, ressources,
#       ports, paquets en conflit, cluster déjà présent, pare-feu, SELinux...
#    3. affichage des changements prévus, puis confirmation
#    4. site.yml (préparation, containerd, kubeadm, CNI, HA), kubeconfig
#    5. addons, tests, manifeste du déploiement
#
#  Protections : jamais de formatage sans LONGHORN_DISK_ALLOW_FORMAT=true et un
#  disque vide désigné (LONGHORN_DISK_DEVICE), jamais de kubeadm reset
#  automatique, pare-feu/SELinux/AppArmor jamais désactivés, machines déjà dans
#  un cluster refusées. « destroy » ne supprime JAMAIS les machines.
# =============================================================================

existing_context() { echo "${CLUSTER_NAME}-existing"; }

existing_deploy() {
  local context inventory
  context="$(existing_context)"
  require_doctor existing
  inventory="$(lab_inventory)"

  step "Contrôles préalables sur les machines existantes (lecture seule, rien n'est modifié)"
  ansible_playbook "${inventory}" preflight.yml ||
    die "Les contrôles préalables ont échoué : AUCUNE machine n'a été modifiée." \
      "Corrigez les points signalés ci-dessus, puis relancez : $(hint_cmd deploy existing)" \
      "Voir docs/existing-mode.md#controles-prealables"

  step "Changements qui vont être appliqués aux machines"
  cat <<PLAN
  - paquets : containerd ${LAB_R_OS_FAMILY:+(${LAB_R_OS_FAMILY}) }, kubelet/kubeadm/kubectl ${KUBERNETES_VERSION} (dépôts officiels), prérequis des addons
  - noyau : modules overlay et br_netfilter, sysctl du routage IP (/etc/sysctl.d/99-kubernetes.conf)
  - swap : ${NODE_SWAP:-disable} ; pare-feu : ports Kubernetes OUVERTS (jamais désactivé) ; SELinux/AppArmor conservés
  - Kubernetes : ${LAB_R_CP_COUNT} control-plane(s), ${LAB_R_WORKER_COUNT} worker(s), CNI ${LAB_R_CNI}${LAB_R_VIP:+, VIP ${LAB_R_VIP}}
  - disques : $( [[ "${LAB_R_LONGHORN_DISK}" == true ]] && echo "disque Longhorn ${LONGHORN_DISK_DEVICE} (formaté seulement s'il est vide ET LONGHORN_DISK_ALLOW_FORMAT=true)" || echo "aucun disque touché")
  - jamais modifiés : partitions existantes, configuration réseau, utilisateurs, services sans rapport
PLAN
  confirm "Installer Kubernetes sur les machines de ${inventory} ?" || die "Installation annulée : rien n'a été modifié."

  ansible_install_kubernetes "${inventory}"
  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  post_deploy "${context}"
}

existing_destroy() {
  die "Le mode existing ne détruit JAMAIS les machines : elles ne sont pas gérées par le framework." \
    "Pour retirer Kubernetes de ces machines (kubeadm reset, données conservées) : $(hint_cmd uninstall existing)" \
    "Voir docs/existing-mode.md#desinstallation"
}

# Désinstallation explicite : kubeadm reset sur chaque nœud (sauvegarde etcd d'abord).
existing_uninstall() {
  local context answer
  context="$(existing_context)"
  step "Désinstallation de Kubernetes des machines existantes (${LAB_R_EXISTING_INVENTORY})"
  cat <<WARN
  Effets : kubeadm reset sur CHAQUE nœud de l'inventaire, interfaces et configuration du CNI
  supprimées. Une sauvegarde etcd est prise avant (si possible). Conservés : les machines, leurs
  données, les paquets installés, les volumes Longhorn sur disque, les données NFS.
WARN
  if [[ "${ASSUME_YES:-0}" == "1" && "${UNINSTALL_CONFIRM:-}" != "${context}" ]]; then
    die "--yes ne suffit pas pour désinstaller un cluster." "Ajoutez UNINSTALL_CONFIRM=${context} (nom du cluster)."
  fi
  if [[ "${UNINSTALL_CONFIRM:-}" != "${context}" ]]; then
    [[ -t 0 ]] || die "Confirmation impossible sans terminal." "Ajoutez UNINSTALL_CONFIRM=${context}."
    read -r -p "Tapez le nom du cluster (${context}) pour confirmer : " answer
    [[ "${answer}" == "${context}" ]] || die "Nom incorrect : désinstallation annulée."
  fi
  ansible_playbook "$(lab_inventory)" reset.yml -e "reset_confirm=${context}" ||
    die "La désinstallation a échoué sur au moins un nœud (voir ci-dessus)."
  rm -f "${LAB_KUBE_DIR}/clusters/${context}.yaml"
  kubeconfig_remove "${context}" "${context}" "${context}-admin"
  ok "Kubernetes désinstallé des machines (machines et données conservées)."
}

existing_status() {
  if [[ -n "${EXISTING_INVENTORY:-}" ]]; then
    if [[ -s "${LAB_KUBE_DIR}/clusters/$(existing_context).yaml" ]]; then
      status_line up existing "${EXISTING_INVENTORY} (contexte $(existing_context))"
    else
      status_line none existing "${EXISTING_INVENTORY} : Kubernetes pas encore installé par le lab"
    fi
  else
    status_line none existing "EXISTING_INVENTORY non défini"
  fi
}

existing_kubeconfig() {
  local context
  context="$(existing_context)"
  ansible_fetch_kubeconfig "$(lab_inventory)"
  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  kubeconfig_hint "${context}"
}
