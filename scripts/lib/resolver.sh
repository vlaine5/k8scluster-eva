#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Pont entre le CLI Bash et le résolveur Python (scripts/labctl).
#
#  Le résolveur est la SEULE source de vérité : il valide toute la
#  configuration (schéma, cohérence, réseaux, compatibilité des versions),
#  calcule le plan des addons et produit les variables d'Ansible. Le CLI ne
#  fait qu'exécuter ce plan. Rien n'est modifié tant que la validation échoue.
# =============================================================================

# Python du lab : l'environnement virtuel de « make venv » s'il existe.
lab_python() {
  if [[ -x "${LAB_ROOT}/.venv/bin/python" ]]; then
    echo "${LAB_ROOT}/.venv/bin/python"
  else
    echo python3
  fi
}

labctl() {
  "$(lab_python)" "${LAB_ROOT}/scripts/labctl" "$@"
}

# Arguments --mode/--provider du dernier mode résolu (réutilisés par les autres appels).
LAB_RESOLVE_ARGS=()

# lab_resolve <mode> [provider] : valide la configuration puis exporte les
# valeurs résolues (LAB_R_CONTEXT, LAB_R_ADDONS, LAB_R_CNI...). Quitte en cas d'erreur.
lab_resolve() {
  local mode="$1" provider="${2:-}" exports
  LAB_RESOLVE_ARGS=(--mode "${mode}")
  [[ -z "${provider}" ]] || LAB_RESOLVE_ARGS+=(--provider "${provider}")
  [[ -z "${LAB_CLUSTER_VERSION:-}" ]] || LAB_RESOLVE_ARGS+=(--cluster-version "${LAB_CLUSTER_VERSION}")
  step "Validation de la configuration (${mode}${provider:+ ${provider}})"
  labctl validate --quiet "${LAB_RESOLVE_ARGS[@]}" ||
    die "Configuration invalide : rien n'a été créé ni modifié." \
      "Configuration effective et explications : $(hint_cmd config "${mode}" "${provider}")" \
      "Référence des variables : docs/configuration.md"
  exports="$(labctl shell "${LAB_RESOLVE_ARGS[@]}")" ||
    die "Le résolveur de configuration a échoué (scripts/labctl shell)."
  eval "${exports}"
  ok "Configuration valide : contexte ${LAB_R_CONTEXT}, addons : ${LAB_R_ADDONS:-aucun}"
}

# Variables Ansible du plan (JSON 0600, sans aucun secret) ; affiche le chemin.
lab_ansible_vars() {
  local file="${LAB_STATE_DIR}/ansible/${LAB_R_CONTEXT}-vars.json"
  mkdir -p "${LAB_STATE_DIR}/ansible"
  labctl ansible-vars "${LAB_RESOLVE_ARGS[@]}" --output "${file}" >&2 ||
    die "Impossible de produire les variables Ansible (scripts/labctl ansible-vars)."
  echo "${file}"
}

# Manifeste du déploiement (versions, options, addons ; sans secret) : .lab/manifests/<contexte>.yaml
lab_write_manifest() {
  local file="${LAB_STATE_DIR}/manifests/${LAB_R_CONTEXT}.yaml"
  mkdir -p "${LAB_STATE_DIR}/manifests"
  if labctl manifest "${LAB_RESOLVE_ARGS[@]}" --output "${file}"; then
    ok "Manifeste du déploiement : ${file#"${LAB_ROOT}"/}"
  else
    warn "Le manifeste du déploiement n'a pas pu être écrit (scripts/labctl manifest)."
  fi
}

# Vrai si le mode installe Kubernetes avec kubeadm (VMs ou machines existantes).
lab_is_kubeadm() {
  case "${LAB_R_PLATFORM:-}" in
    vagrant | proxmox | vsphere | libvirt | existing) return 0 ;;
  esac
  return 1
}

# Inventaire Ansible du mode courant (relatif à ansible/, ou absolu pour le mode existing).
lab_inventory() {
  case "${LAB_R_PLATFORM:-}" in
    vagrant) echo "${VAGRANT_INVENTORY}" ;;
    proxmox | vsphere | libvirt) tf_inventory "${LAB_R_PLATFORM}" ;;
    existing) echo "${LAB_R_EXISTING_INVENTORY}" ;;
    *) die "Le mode ${LAB_MODE:-?} n'a pas d'inventaire Ansible (pas de nœuds gérés par kubeadm)." ;;
  esac
}
