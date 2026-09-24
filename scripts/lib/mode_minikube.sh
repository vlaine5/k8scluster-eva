#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode minikube : cluster local avec addons (niveau 1, découverte).
#  https://minikube.sigs.k8s.io/
#  Le "profil" minikube porte le nom du cluster ; le contexte kubectl aussi.
# =============================================================================

# Sortie JSON : le tableau texte contient des codes couleur difficiles à analyser.
minikube_profile_exists() {
  minikube profile list --output json 2>/dev/null | grep -q "\"Name\":\"${CLUSTER_NAME}\""
}

minikube_is_running() {
  minikube status --profile "${CLUSTER_NAME}" >/dev/null 2>&1
}

minikube_deploy() {
  require_doctor minikube

  if minikube_profile_exists && [[ "${RECREATE:-0}" == "1" ]]; then
    minikube_destroy
  fi

  if minikube_is_running; then
    info "Le cluster minikube \"${CLUSTER_NAME}\" tourne déjà : rien à créer (option --recreate pour le recréer)."
    KUBECONFIG="${LAB_KUBECONFIG}" run minikube update-context --profile "${CLUSTER_NAME}"
  else
    local args=(start --profile "${CLUSTER_NAME}"
      --kubernetes-version "${MINIKUBE_KUBERNETES_VERSION}"
      --nodes "${MINIKUBE_NODES}"
      --cpus "${MINIKUBE_CPUS}"
      --memory "${MINIKUBE_MEMORY_MB}"
      --wait all)
    if [[ -n "${MINIKUBE_DRIVER:-}" ]]; then
      args+=(--driver "${MINIKUBE_DRIVER}")
    fi
    if [[ -n "${MINIKUBE_EXTRA_ARGS:-}" ]]; then
      local extra=()
      read -r -a extra <<<"${MINIKUBE_EXTRA_ARGS}"
      args+=("${extra[@]}")
    fi
    step "Démarrage du cluster minikube \"${CLUSTER_NAME}\" (2 à 5 minutes au premier lancement)"
    KUBECONFIG="${LAB_KUBECONFIG}" run minikube "${args[@]}" ||
      die "Le démarrage de minikube a échoué." \
        "Logs détaillés : minikube logs --profile ${CLUSTER_NAME}" \
        "Nettoyez puis réessayez : ./k8s-lab destroy minikube && ./k8s-lab deploy minikube" \
        "Voir docs/troubleshooting.md"
  fi
  chmod 600 "${LAB_KUBECONFIG}"

  smoke_basic "${CLUSTER_NAME}"
  kubeconfig_hint "${CLUSTER_NAME}"
  printf '\nÀ essayer : minikube dashboard --profile %s   |   minikube addons list --profile %s\n' "${CLUSTER_NAME}" "${CLUSTER_NAME}"
}

minikube_destroy() {
  if ! minikube_profile_exists; then
    info "Aucun cluster minikube \"${CLUSTER_NAME}\" : rien à détruire."
    return 0
  fi
  confirm "Détruire le cluster minikube \"${CLUSTER_NAME}\" ?" || die "Destruction annulée."
  KUBECONFIG="${LAB_KUBECONFIG}" run minikube delete --profile "${CLUSTER_NAME}"
  ok "Cluster minikube \"${CLUSTER_NAME}\" détruit."
}

minikube_status() {
  if ! have minikube; then
    status_line none minikube "(non installé)"
    return 0
  fi
  if minikube_is_running; then
    status_line up minikube "${CLUSTER_NAME} (contexte ${CLUSTER_NAME})"
  elif minikube_profile_exists; then
    status_line stopped minikube "${CLUSTER_NAME} arrêté (./k8s-lab deploy minikube pour le redémarrer)"
  else
    status_line none minikube "aucun cluster"
  fi
}

minikube_kubeconfig() {
  minikube_is_running || die "Le cluster minikube \"${CLUSTER_NAME}\" ne tourne pas." "Démarrez-le : ./k8s-lab deploy minikube"
  KUBECONFIG="${LAB_KUBECONFIG}" run minikube update-context --profile "${CLUSTER_NAME}"
  chmod 600 "${LAB_KUBECONFIG}"
  kubeconfig_hint "${CLUSTER_NAME}"
}
