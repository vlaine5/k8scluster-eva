#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode attach : addons du catalogue installés sur un cluster Kubernetes qui
#  existe déjà (k3s, RKE2, kubeadm, EKS, AKS...), via EXISTING_KUBECONFIG et
#  EXISTING_CONTEXT (toujours nommé explicitement).
#
#  Le framework ne touche JAMAIS : les nœuds, le système, kubeadm, containerd,
#  le CNI. Il détecte d'abord (lecture seule) la version, la distribution, le
#  CNI, les StorageClasses, les CRD, les releases Helm et les applications Argo
#  CD, puis refuse tout conflit avec un composant géré par un autre outil.
# =============================================================================

attach_deploy() {
  info "Mode attach : aucun cluster n'est créé ; les addons du plan sont installés sur ${LAB_R_CONTEXT}."
  require_doctor attach
  attach_detect
  addons_apply
  [[ "${ENABLE_POST_DEPLOY_TESTS:-true}" != "true" || -z "${LAB_R_ADDONS}" ]] || addons_test
  lab_write_manifest
}

attach_destroy() {
  die "Le mode attach ne détruit jamais un cluster existant." \
    "Pour retirer un addon installé par le framework : $(hint_cmd addons-remove attach) (ADDON=<nom>)" \
    "Voir docs/attach-mode.md"
}

attach_status() {
  if [[ -z "${EXISTING_KUBECONFIG:-}" || -z "${EXISTING_CONTEXT:-}" ]]; then
    status_line none attach "EXISTING_KUBECONFIG / EXISTING_CONTEXT non définis"
  elif kubectl --kubeconfig "${EXISTING_KUBECONFIG/#\~/${HOME}}" --context "${EXISTING_CONTEXT}" \
    version --request-timeout=5s >/dev/null 2>&1; then
    status_line up attach "${EXISTING_CONTEXT} (${EXISTING_KUBECONFIG}) répond"
  else
    status_line stopped attach "${EXISTING_CONTEXT} (${EXISTING_KUBECONFIG}) ne répond pas"
  fi
}

attach_kubeconfig() {
  info "Mode attach : le kubeconfig du cluster existant est utilisé tel quel, il n'est jamais copié ni modifié."
  printf '  export KUBECONFIG="%s"\n  kubectl config use-context %s\n' "${LAB_R_KUBECONFIG}" "${LAB_R_CONTEXT}"
}
