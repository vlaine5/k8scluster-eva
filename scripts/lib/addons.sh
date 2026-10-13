#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Addons : plan, installation, état, tests, mise à jour, désinstallation.
#
#  Les addons sont installés DEPUIS VOTRE POSTE par l'API Kubernetes
#  (kubeconfig + contexte vérifiés), avec le même moteur quel que soit le mode :
#    ansible-playbook addons.yml -e @<variables du plan> -e addon_action=<action>
#  Catalogue : addons/<id>/addon.yaml   Documentation : docs/addons.md
# =============================================================================

# Fichier JSON produit par la détection du mode attach (addons existants, version).
LAB_ATTACH_VARS=""

# Python utilisé par ansible-playbook (il doit disposer de la bibliothèque kubernetes).
ansible_python_path() {
  ansible --version 2>/dev/null | sed -n -E 's/^ *python version = .*\((\/[^)]*)\)$/\1/p' | head -n1
}

addons_require_tools() {
  local missing=() python
  have kubectl || missing+=("kubectl (scripts/install-tools.sh kubectl)")
  have helm || missing+=("helm (scripts/install-tools.sh helm)")
  have ansible-playbook || missing+=("ansible-core (make venv)")
  if have ansible-playbook; then
    python="$(ansible_python_path)"
    if [[ -n "${python}" ]] && ! "${python}" -c 'import kubernetes, yaml' >/dev/null 2>&1; then
      missing+=("bibliothèque Python « kubernetes » pour ${python} (make venv, puis source .venv/bin/activate)")
    fi
  fi
  ((${#missing[@]} == 0)) && return 0
  die "Outils manquants pour installer les addons :" "${missing[@]}" "Diagnostic complet : $(hint_cmd doctor "${LAB_MODE:-}" "${LAB_PROVIDER:-}")"
}

# Le cluster ciblé doit répondre AVEC LE CONTEXTE ATTENDU (jamais le contexte courant par défaut).
addons_check_cluster() {
  kubectl --kubeconfig "${LAB_R_KUBECONFIG}" --context "${LAB_R_CONTEXT}" version --request-timeout=15s >/dev/null 2>&1 ||
    die "Le cluster du contexte \"${LAB_R_CONTEXT}\" ne répond pas (kubeconfig ${LAB_R_KUBECONFIG})." \
      "Le cluster est-il déployé et démarré ? $(hint_cmd status)" \
      "Rafraîchir le kubeconfig : $(hint_cmd kubeconfig "${LAB_MODE:-<mode>}" "${LAB_PROVIDER:-}")"
}

# Mode attach : inventaire du cluster existant (lecture seule), refus des conflits,
# puis nouvelle résolution avec la version détectée (compatibilité des addons).
attach_detect() {
  local file version
  step "Inventaire du cluster existant \"${LAB_R_CONTEXT}\" (lecture seule)"
  file="${LAB_STATE_DIR}/attach/${LAB_R_CONTEXT}.json"
  mkdir -p "${LAB_STATE_DIR}/attach"
  labctl detect --kubeconfig "${LAB_R_KUBECONFIG}" --context "${LAB_R_CONTEXT}" \
    --addons "${LAB_R_ADDONS}" --vars-output "${file}" ||
    die "Le cluster existant présente des conflits avec les addons demandés (détails ci-dessus) : rien n'a été modifié." \
      "Le framework ne prend jamais le contrôle d'un composant installé par un autre outil (Helm, Argo CD, k3s...)." \
      "Options : retirer l'addon d'ADDONS, ou EXISTING_ADDON_POLICY=skip pour utiliser l'existant tel quel." \
      "Voir docs/attach-mode.md"
  LAB_ATTACH_VARS="${file}"
  version="$("$(lab_python)" -c 'import json, sys; print(json.load(open(sys.argv[1]))["attach_server_version"])' "${file}")"
  LAB_CLUSTER_VERSION="${version}" lab_resolve attach
}

# addons_run <apply|status|test|remove> : moteur Ansible sur le plan courant.
addons_run() {
  local action="$1" extra report
  if [[ -z "${LAB_R_ADDONS}" ]]; then
    info "Aucun addon dans le plan (ADDON_PROFILE=${ADDON_PROFILE:-minimal}, ADDONS=${ADDONS:-}) : rien à faire."
    return 0
  fi
  addons_require_tools
  addons_check_cluster
  mkdir -p "${LAB_STATE_DIR}/reports"
  report="${LAB_STATE_DIR}/reports/${LAB_R_CONTEXT}-addons-${action}.json"
  extra=(-e "addon_action=${action}" -e "addon_report_file=${report}")
  [[ -z "${ADDON:-}" ]] || extra+=(-e "addon_only=${ADDON}")
  [[ "${KEEP:-0}" != "1" ]] || extra+=(-e addon_keep_test_resources=true)
  [[ "${DESTRUCTIVE_TESTS:-0}" != "1" ]] || extra+=(-e addon_destructive_tests=true)
  [[ -z "${LAB_ATTACH_VARS}" ]] || extra+=(-e "@${LAB_ATTACH_VARS}")
  ansible_playbook "$(ansible_local_inventory)" addons.yml "${extra[@]}"
}

addons_apply() {
  step "Addons : installation / synchronisation (${LAB_R_ADDONS:-aucun})"
  addons_run apply ||
    die "L'installation des addons a échoué (voir la tâche en erreur ci-dessus)." \
      "Relancer est sans risque (seul ce qui manque ou a changé est appliqué) : $(hint_cmd addons-apply "${LAB_MODE}" "${LAB_PROVIDER}")" \
      "État : $(hint_cmd addons-status "${LAB_MODE}" "${LAB_PROVIDER}")   |   docs/troubleshooting.md#addons"
  ok "Addons installés : ${LAB_R_ADDONS:-aucun}"
}

addons_test() {
  step "Addons : tests fonctionnels"
  addons_run test || die "Des tests d'addons ont échoué (détails ci-dessus ; KEEP=1 conserve les ressources de test)." \
    "Rapport : .lab/reports/${LAB_R_CONTEXT}-addons-test.json"
  ok "Tests des addons réussis."
}

addons_upgrade() {
  local state rc=0
  addons_require_tools
  addons_check_cluster
  step "Addons : versions installées comparées au plan"
  state="$(mktemp "${LAB_STATE_DIR}/.addons-state.XXXXXX")"
  kubectl --kubeconfig "${LAB_R_KUBECONFIG}" --context "${LAB_R_CONTEXT}" -n k8s-lab-system \
    get configmap k8s-lab-addons -o json >"${state}" 2>/dev/null || : >"${state}"
  labctl addons-diff "${LAB_RESOLVE_ARGS[@]}" --state "${state}" || rc=$?
  rm -f "${state}"
  case "${rc}" in
    0) ok "Tous les addons sont à jour : rien à faire." ; return 0 ;;
    10) ;;
    *) die "Mise à jour des addons impossible (voir ci-dessus)." ;;
  esac
  info "Lisez les notes de version des composants mis à jour (docs/upgrades.md#addons) avant de confirmer."
  confirm "Appliquer ces installations / mises à jour d'addons ?" || die "Mise à jour annulée : rien n'a été modifié."
  addons_apply
  [[ "${ENABLE_POST_DEPLOY_TESTS:-true}" != "true" ]] || addons_test
}

addons_remove() {
  [[ -n "${ADDON:-}" ]] || die "Précisez le ou les addons à désinstaller." \
    "Exemple : make addons-remove MODE=${LAB_MODE:-kind} ADDON=reloader   |   ./k8s-lab addons-remove ${LAB_MODE:-kind} --addon reloader"
  step "Addons : désinstallation de ${ADDON}"
  info "Les données (PVC, volumes, sauvegardes) et les CRD sont conservées. Notes par addon : docs/addons.md"
  confirm "Désinstaller ${ADDON} du cluster \"${LAB_R_CONTEXT}\" ?" || die "Désinstallation annulée."
  addons_run remove || die "La désinstallation a échoué (voir ci-dessus)."
  ok "Désinstallé : ${ADDON}. Pour ne plus le réinstaller, retirez-le d'ADDONS / du profil."
}

# cmd_addons <action> [mode] [provider]
cmd_addons() {
  local action="$1"
  shift
  if [[ "${action}" == catalog ]]; then
    labctl catalog
    return
  fi
  select_mode "$@"
  lab_resolve "${LAB_MODE}" "${LAB_PROVIDER}"
  if [[ "${action}" == plan ]]; then
    labctl plan "${LAB_RESOLVE_ARGS[@]}"
    return
  fi
  [[ "${LAB_R_PLATFORM}" != attach ]] || attach_detect
  case "${action}" in
    apply) addons_apply ;;
    status) addons_run status ;;
    test) addons_test ;;
    upgrade) addons_upgrade ;;
    remove) addons_remove ;;
    *) die "Action d'addons inconnue : ${action}" ;;
  esac
}

# Fin de tout déploiement : vérification du cluster, addons, tests, manifeste.
#   post_deploy <contexte>
post_deploy() {
  local context="$1"
  smoke_basic "${context}"
  if [[ -n "${LAB_R_ADDONS}" ]]; then
    addons_apply
    [[ "${ENABLE_POST_DEPLOY_TESTS:-true}" != "true" ]] || addons_test
  fi
  lab_write_manifest
  kubeconfig_hint "${context}"
}
