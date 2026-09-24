#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode kind : Kubernetes dans des conteneurs Docker (niveau 1, découverte).
#  https://kind.sigs.k8s.io/
# =============================================================================

kind_context() { echo "kind-${CLUSTER_NAME}"; }

kind_cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"
}

# Configuration kind générée depuis config/lab.env. Avec les valeurs par
# défaut, le résultat est identique à local/kind/kind-config.yaml.
kind_render_config() {
  local i
  cat <<KIND
# Configuration kind du lab (générée par ./k8s-lab depuis config/lab.env).
# Doc : https://kind.sigs.k8s.io/docs/user/configuration/
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
nodes:
  - role: control-plane
    image: ${KIND_NODE_IMAGE}
KIND
  for ((i = 1; i <= WORKER_COUNT; i++)); do
    printf '  - role: worker\n    image: %s\n' "${KIND_NODE_IMAGE}"
  done
}

kind_deploy() {
  local context config_file
  context="$(kind_context)"
  require_doctor kind

  if kind_cluster_exists; then
    if [[ "${RECREATE:-0}" == "1" ]]; then
      kind_destroy
    else
      info "Le cluster kind \"${CLUSTER_NAME}\" existe déjà : rien à créer (pour le recréer : $(hint_cmd deploy kind "" --recreate))."
      run kind export kubeconfig --name "${CLUSTER_NAME}" --kubeconfig "${LAB_KUBECONFIG}"
    fi
  fi

  if ! kind_cluster_exists; then
    if [[ -n "${KIND_CONFIG:-}" ]]; then
      config_file="${KIND_CONFIG}"
      [[ "${config_file}" == /* ]] || config_file="${LAB_ROOT}/${config_file}"
      [[ -f "${config_file}" ]] || die "KIND_CONFIG=${KIND_CONFIG} : fichier introuvable."
      info "Configuration kind personnalisée : ${config_file}"
    else
      config_file="${LAB_STATE_DIR}/kind/kind-config.yaml"
      mkdir -p "${LAB_STATE_DIR}/kind"
      kind_render_config >"${config_file}"
      info "Configuration kind générée : ${config_file#"${LAB_ROOT}"/} (1 control-plane + ${WORKER_COUNT} worker(s))"
    fi
    step "Création du cluster kind \"${CLUSTER_NAME}\" (1 à 3 minutes)"
    run kind create cluster --name "${CLUSTER_NAME}" --config "${config_file}" \
      --kubeconfig "${LAB_KUBECONFIG}" --wait 5m ||
      die "La création du cluster kind a échoué." \
        "Vérifiez que Docker fonctionne : docker info" \
        "Nettoyez puis réessayez : $(hint_cmd destroy kind)  puis  $(hint_cmd deploy kind)" \
        "Voir docs/troubleshooting.md"
  fi
  chmod 600 "${LAB_KUBECONFIG}"

  smoke_basic "${context}"
  kubeconfig_hint "${context}"
  printf '\nChaque nœud est un conteneur Docker : docker ps --filter "label=io.x-k8s.kind.cluster=%s"\n' "${CLUSTER_NAME}"
}

kind_destroy() {
  have kind || die "kind est introuvable : impossible de lister ou de supprimer un cluster kind." \
    "Installez-le (scripts/install-tools.sh kind) puis relancez : $(hint_cmd destroy kind)"
  if ! kind_cluster_exists; then
    info "Aucun cluster kind \"${CLUSTER_NAME}\" : rien à détruire."
    return 0
  fi
  confirm "Détruire le cluster kind \"${CLUSTER_NAME}\" (tous ses conteneurs) ?" || die "Destruction annulée."
  run kind delete cluster --name "${CLUSTER_NAME}" --kubeconfig "${LAB_KUBECONFIG}"
  ok "Cluster kind \"${CLUSTER_NAME}\" détruit."
}

kind_status() {
  if ! have kind; then
    status_line none kind "(non installé)"
    return 0
  fi
  if kind_cluster_exists; then
    status_line up kind "${CLUSTER_NAME} (contexte $(kind_context))"
  else
    status_line none kind "aucun cluster"
  fi
}

kind_kubeconfig() {
  kind_cluster_exists || die "Aucun cluster kind \"${CLUSTER_NAME}\"." "Créez-le : $(hint_cmd deploy kind)"
  run kind export kubeconfig --name "${CLUSTER_NAME}" --kubeconfig "${LAB_KUBECONFIG}"
  chmod 600 "${LAB_KUBECONFIG}"
  kubeconfig_hint "$(kind_context)"
}
