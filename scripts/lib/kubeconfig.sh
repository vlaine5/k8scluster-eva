#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Gestion du kubeconfig du lab : .kube/config (dans le dépôt, ignoré par Git).
#
#  Votre ~/.kube/config n'est JAMAIS modifié. Tous les clusters du lab sont
#  rassemblés dans .kube/config, un "contexte" par cluster :
#    export KUBECONFIG="$PWD/.kube/config"
#    kubectl config get-contexts
# =============================================================================

# Fusionne le kubeconfig d'un cluster kubeadm dans .kube/config et l'active.
#   kubeconfig_merge <fichier> <contexte>
kubeconfig_merge() {
  local file="$1" context="$2" tmp
  [[ -f "${file}" ]] || die "kubeconfig introuvable : ${file}" \
    "Il est normalement écrit par Ansible à la fin du déploiement." \
    "Relancez : $(hint_cmd kubeconfig "${LAB_MODE:-<mode>}" "${LAB_PROVIDER:-}")"
  ensure_state_dirs
  kubeconfig_remove "${context}" "${context}" "${context}-admin"
  tmp="$(mktemp "${LAB_KUBE_DIR}/.config.XXXXXX")"
  chmod 600 "${tmp}"
  if [[ -s "${LAB_KUBECONFIG}" ]]; then
    # Le premier fichier est prioritaire : son current-context devient l'actif.
    KUBECONFIG="${file}:${LAB_KUBECONFIG}" kubectl config view --flatten >"${tmp}"
  else
    KUBECONFIG="${file}" kubectl config view --flatten >"${tmp}"
  fi
  mv "${tmp}" "${LAB_KUBECONFIG}"
  kubectl --kubeconfig "${LAB_KUBECONFIG}" config use-context "${context}" >/dev/null
  ok "Contexte kubectl \"${context}\" ajouté à .kube/config"
}

# Supprime un contexte (et son cluster / utilisateur) de .kube/config.
#   kubeconfig_remove <contexte> <cluster> <utilisateur>
kubeconfig_remove() {
  local context="$1" cluster="$2" user="$3" current
  [[ -f "${LAB_KUBECONFIG}" ]] || return 0
  local kc=(kubectl --kubeconfig "${LAB_KUBECONFIG}" config)
  current="$("${kc[@]}" current-context 2>/dev/null || true)"
  "${kc[@]}" delete-context "${context}" >/dev/null 2>&1 || true
  "${kc[@]}" delete-cluster "${cluster}" >/dev/null 2>&1 || true
  "${kc[@]}" delete-user "${user}" >/dev/null 2>&1 || true
  if [[ "${current}" == "${context}" ]]; then
    "${kc[@]}" unset current-context >/dev/null 2>&1 || true
  fi
}

kubeconfig_hint() {
  local context="$1"
  printf '\n%sUtiliser kubectl avec ce cluster :%s\n' "${C_BOLD}" "${C_RESET}"
  printf '  export KUBECONFIG="%s"\n' "${LAB_KUBECONFIG}"
  printf '  kubectl config use-context %s\n' "${context}"
  printf '  kubectl get nodes\n'
}
