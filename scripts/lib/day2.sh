#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Exploitation des clusters kubeadm (vagrant, terraform proxmox/vsphere/libvirt,
#  existing) : plan et exécution des mises à niveau, mises à jour de l'OS,
#  sauvegardes etcd, restauration, santé, retrait d'un nœud, test de perte d'un
#  worker (Longhorn).
#
#  Toute opération qui modifie le cluster exige une confirmation explicite ;
#  les plus risquées (mise à niveau, restauration, retrait) demandent de taper
#  le nom du cluster ou du nœud (variables *_CONFIRM pour l'automatisation).
# =============================================================================

day2_require_kubeadm() {
  lab_is_kubeadm && return 0
  case "${LAB_R_PLATFORM}" in
    kind | minikube) die "Mode ${LAB_R_PLATFORM} : cluster jetable. Pour changer de version, recréez-le : $(hint_cmd deploy "${LAB_MODE}" "" --recreate)" ;;
    eks) die "Mode eks : AWS opère le control-plane. Mise à niveau : EKS_KUBERNETES_VERSION dans .env puis $(hint_cmd deploy terraform eks)" ;;
    attach) die "Mode attach : le framework ne gère ni les nœuds ni la version d'un cluster existant." ;;
  esac
  die "Commande réservée aux clusters kubeadm."
}

# Demande de taper une valeur (nom du cluster ou du nœud), sauf si <VARIABLE>=valeur est fourni.
#   confirm_typed <valeur attendue> <nom de la variable d'automatisation> <message>
confirm_typed() {
  local expected="$1" variable="$2" message="$3" answer
  [[ "${!variable:-}" == "${expected}" ]] && return 0
  [[ -t 0 ]] || die "Confirmation impossible sans terminal." "Ajoutez ${variable}=${expected} pour confirmer explicitement."
  printf '%s%s%s\n' "${C_BOLD}${C_YELLOW}" "${message}" "${C_RESET}"
  read -r -p "Tapez « ${expected} » pour confirmer : " answer
  [[ "${answer}" == "${expected}" ]] || die "Valeur incorrecte : opération annulée, rien n'a été modifié."
}

day2_kubectl() {
  kubectl --kubeconfig "${LAB_R_KUBECONFIG}" --context "${LAB_R_CONTEXT}" --request-timeout=20s "$@"
}

# make upgrade-plan : lecture seule (version actuelle, kubelets, compatibilité des addons).
cmd_upgrade_plan() {
  local server nodes rc=0
  day2_require_kubeadm
  addons_check_cluster
  server="$(day2_kubectl version -o json | "$(lab_python)" -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')" ||
    die "Version du cluster illisible (kubectl version)."
  nodes="$(mktemp "${LAB_STATE_DIR}/.nodes.XXXXXX")"
  day2_kubectl get nodes -o json >"${nodes}"
  step "Plan de mise à niveau (aucune modification)"
  labctl upgrade-plan "${LAB_RESOLVE_ARGS[@]}" --server-version "${server}" --nodes "${nodes}" || rc=$?
  rm -f "${nodes}"
  return "${rc}"
}

cmd_upgrade() {
  local rc=0
  cmd_upgrade_plan || rc=$?
  case "${rc}" in
    0) ;;
    10) ok "Rien à mettre à niveau." ; return 0 ;;
    *) die "Mise à niveau impossible en l'état (voir le plan ci-dessus) : rien n'a été modifié." ;;
  esac
  confirm_typed "${LAB_R_CONTEXT}" UPGRADE_CONFIRM \
    "Mise à niveau de \"${LAB_R_CONTEXT}\" vers Kubernetes ${KUBERNETES_VERSION} (nœuds drainés un par un)."
  step "Mise à niveau de Kubernetes (upgrade.yml)"
  ansible_playbook "$(lab_inventory)" upgrade.yml -e "upgrade_confirm=${LAB_R_CONTEXT}" ||
    die "La mise à niveau s'est arrêtée (voir la tâche en erreur)." \
      "Les nœuds déjà mis à niveau le restent ; le nœud en cours est remis en service (uncordon)." \
      "Une sauvegarde etcd a été prise au début : .lab/backups/${LAB_R_CONTEXT}/   |   docs/upgrades.md"
  ok "Cluster \"${LAB_R_CONTEXT}\" en ${KUBERNETES_VERSION}. Addons : $(hint_cmd addons-upgrade "${LAB_MODE}" "${LAB_PROVIDER}")"
}

cmd_os_update() {
  day2_require_kubeadm
  confirm_typed "${LAB_R_CONTEXT}" OS_UPDATE_CONFIRM \
    "Mises à jour de sécurité de l'OS sur chaque nœud de \"${LAB_R_CONTEXT}\", un par un (drain, redémarrage si nécessaire)."
  ansible_playbook "$(lab_inventory)" os-update.yml -e "os_update_confirm=${LAB_R_CONTEXT}" ||
    die "La mise à jour de l'OS s'est arrêtée (voir ci-dessus) ; le nœud en cours est remis en service."
  ok "Systèmes à jour."
}

cmd_backup() {
  day2_require_kubeadm
  step "Sauvegarde etcd (instantané sur chaque control-plane, copie locale chiffrable)"
  ansible_playbook "$(lab_inventory)" backup.yml || die "La sauvegarde a échoué (voir ci-dessus)."
  ok "Instantanés etcd : .lab/backups/${LAB_R_CONTEXT}/ (et /var/backups/k8s-lab/etcd sur les nœuds)."
  [[ "${LAB_R_ADDONS}" != *velero* ]] || info "Ressources et volumes applicatifs : Velero (planification BACKUP_SCHEDULE)."
}

cmd_restore() {
  local snapshot="${SNAPSHOT:-}"
  day2_require_kubeadm
  [[ -n "${snapshot}" ]] || die "Précisez l'instantané etcd à restaurer : SNAPSHOT=<fichier>." \
    "Instantanés disponibles : ls .lab/backups/${LAB_R_CONTEXT}/" "Procédure : docs/backup-dr.md#restauration"
  [[ "${snapshot}" == /* ]] || snapshot="${LAB_ROOT}/${snapshot}"
  [[ -f "${snapshot}" ]] || die "Instantané introuvable : ${snapshot}"
  confirm_typed "${LAB_R_CONTEXT}" RESTORE_CONFIRM \
    "RESTAURATION d'etcd sur \"${LAB_R_CONTEXT}\" : l'état du cluster revient à celui de l'instantané (tout ce qui a changé depuis est perdu)."
  ansible_playbook "$(lab_inventory)" etcd-restore.yml -e "etcd_restore_snapshot=${snapshot}" \
    -e "restore_confirm=${LAB_R_CONTEXT}" || die "La restauration a échoué (voir ci-dessus) : docs/backup-dr.md#restauration"
  ok "etcd restauré depuis $(basename "${snapshot}"). Vérifiez : $(hint_cmd health "${LAB_MODE}" "${LAB_PROVIDER}")"
}

cmd_health() {
  day2_require_kubeadm
  step "Santé du cluster \"${LAB_R_CONTEXT}\" (lecture seule)"
  ansible_playbook "$(lab_inventory)" health.yml || die "Des contrôles de santé ont échoué (voir ci-dessus)."
  day2_kubectl get nodes -o wide
  day2_kubectl get --raw='/readyz?verbose' | tail -n 3
  ok "Cluster en bonne santé."
}

cmd_node_remove() {
  local node="${NODE:-}"
  day2_require_kubeadm
  [[ -n "${node}" ]] || die "Précisez le nœud à retirer : NODE=<nom> (kubectl get nodes)."
  confirm_typed "${node}" NODE_REMOVE_CONFIRM \
    "Retrait du nœud ${node} : drain, kubeadm reset sur CE nœud uniquement, suppression de l'objet Node. La machine est conservée."
  ansible_playbook "$(lab_inventory)" node-remove.yml -e "node_remove=${node}" -e "node_remove_confirm=${node}" ||
    die "Le retrait du nœud a échoué (voir ci-dessus)."
  ok "Nœud ${node} retiré du cluster. Retirez-le aussi de l'inventaire / de WORKER_COUNT (docs/day2.md)."
}

# Test destructif de Longhorn : panne simulée d'un worker (kubelet, Pods et containerd
# arrêtés), bascule du volume, puis remise en service. Jamais lancé automatiquement.
cmd_storage_failure_test() {
  local node="${NODE:-}"
  day2_require_kubeadm
  [[ " ${LAB_R_ADDONS:-} " == *" longhorn "* ]] || die "Longhorn n'est pas dans le plan des addons (STORAGE_BACKENDS / ADDONS)."
  [[ -n "${node}" ]] || die "Précisez le worker à arrêter : NODE=<nom> (kubectl get nodes)."
  confirm_typed "${node}" STORAGE_FAILURE_CONFIRM \
    "Test DESTRUCTIF : kubelet, tous les Pods et containerd seront arrêtés sur ${node} pendant plusieurs minutes, puis redémarrés."
  ansible_playbook "$(lab_inventory)" storage-node-failure.yml -e "node_failure_confirm=${node}" ||
    die "Le test de perte de nœud a échoué (voir ci-dessus). Vérifiez l'état de ${node} : kubectl get node ${node}"
  ok "Le volume Longhorn a survécu à la perte de ${node} ; nœud remis en service, réplicas reconstruits."
}

cmd_uninstall() {
  [[ "${LAB_R_PLATFORM}" == existing ]] ||
    die "uninstall concerne le mode existing (machines conservées). Pour les autres modes : $(hint_cmd destroy "${LAB_MODE}" "${LAB_PROVIDER}")"
  existing_uninstall
}
