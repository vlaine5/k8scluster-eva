#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode kind : Kubernetes dans des conteneurs Docker (niveau 1, découverte, CI).
#  https://kind.sigs.k8s.io/
#
#  Image des nœuds épinglée par condensé (config/versions.yaml), certificats
#  des kubelets signés par la CA du cluster (metrics-server et Prometheus les
#  vérifient), CNI natif (kindnet) ou Cilium/Calico installés depuis votre poste.
# =============================================================================

kind_context() { echo "kind-${CLUSTER_NAME}"; }
kind_kubeconfig_file() { echo "${LAB_STATE_DIR}/kind/${CLUSTER_NAME}.kubeconfig"; }

kind_cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"
}

# Configuration kind générée depuis la configuration résolue (make config MODE=kind).
kind_render_config() {
  local i image="${LAB_R_KIND_NODE_IMAGE:-${KIND_NODE_IMAGE}}"
  cat <<KIND
# Configuration kind du lab (générée par ./k8s-lab depuis la configuration résolue).
# Doc : https://kind.sigs.k8s.io/docs/user/configuration/
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
KIND
  if [[ "${LAB_R_CNI_INSTALL:-platform}" != platform ]]; then
    printf '  # %s est installé après la création du cluster (CNI natif désactivé).\n  disableDefaultCNI: true\n' "${LAB_R_CNI}"
  fi
  if [[ "${LAB_R_KUBE_PROXY_MODE:-}" == cilium ]]; then
    printf '  # Cilium remplace kube-proxy.\n  kubeProxyMode: "none"\n'
  fi
  cat <<'KIND'
# Certificats de service des kubelets signés par la CA du cluster (pas de TLS non vérifié).
kubeadmConfigPatches:
  - |
    kind: KubeletConfiguration
    serverTLSBootstrap: true
nodes:
KIND
  printf '  - role: control-plane\n    image: %s\n' "${image}"
  for ((i = 1; i <= WORKER_COUNT; i++)); do
    printf '  - role: worker\n    image: %s\n' "${image}"
  done
}

# Approuve les CSR « kubelet-serving » des nœuds de CE cluster uniquement
# (demandeur system:node:<nœud du cluster>, signataire kubernetes.io/kubelet-serving).
kind_approve_kubelet_certificates() {
  local nodes total issued=0 csr requestor cert tries
  nodes="$(kind get nodes --name "${CLUSTER_NAME}" | sort)"
  total="$(wc -l <<<"${nodes}")"
  for ((tries = 0; tries < 36; tries++)); do
    issued=0
    while read -r csr requestor cert; do
      [[ -n "${csr}" ]] || continue
      grep -qx "${requestor#system:node:}" <<<"${nodes}" || continue
      if [[ -n "${cert}" ]]; then
        issued=$((issued + 1))
      else
        kubectl --context "$(kind_context)" certificate approve "${csr}" >/dev/null || true
      fi
    done < <(kubectl --context "$(kind_context)" get csr -o \
      jsonpath='{range .items[?(@.spec.signerName=="kubernetes.io/kubelet-serving")]}{.metadata.name} {.spec.username} {.status.certificate}{"\n"}{end}')
    if ((issued >= total)); then
      ok "Certificats de service des ${total} kubelets émis par la CA du cluster."
      return 0
    fi
    sleep 5
  done
  warn "Certificats kubelet émis : ${issued}/${total} (kubectl get csr). kubectl logs/exec et metrics-server en dépendent."
}

# Cilium/Calico sur kind : rôle cni (mêmes valeurs Helm que kubeadm), depuis votre poste.
kind_install_cni() {
  local inventory="${LAB_STATE_DIR}/kind/inventory.ini" kubeconfig
  kubeconfig="$(kind_kubeconfig_file)"
  kind get kubeconfig --name "${CLUSTER_NAME}" >"${kubeconfig}"
  chmod 600 "${kubeconfig}"
  cat >"${inventory}" <<INV
# Généré par ./k8s-lab : le CNI de kind est installé depuis ce poste.
[control_plane]
localhost ansible_connection=local ansible_python_interpreter="{{ ansible_playbook_python }}"
[k8s_cluster:children]
control_plane
INV
  step "Installation du CNI ${LAB_R_CNI} sur kind (Helm, depuis votre poste)"
  ansible_playbook "${inventory}" cni-local.yml -e "lab_kubeconfig_file=${kubeconfig}" \
    -e "control_plane_endpoint=${CLUSTER_NAME}-control-plane:6443" ||
    die "L'installation du CNI ${LAB_R_CNI} a échoué (voir ci-dessus)." \
      "Le cluster existe sans réseau de Pods : relancez $(hint_cmd deploy kind), ou recréez-le avec RECREATE=1."
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
    mkdir -p "${LAB_STATE_DIR}/kind"
    if [[ -n "${KIND_CONFIG:-}" ]]; then
      config_file="${KIND_CONFIG}"
      [[ "${config_file}" == /* ]] || config_file="${LAB_ROOT}/${config_file}"
      [[ -f "${config_file}" ]] || die "KIND_CONFIG=${KIND_CONFIG} : fichier introuvable."
      warn "Configuration kind personnalisée : ${config_file} (CNI, image et certificats kubelet sont sous votre responsabilité)."
    else
      config_file="${LAB_STATE_DIR}/kind/kind-config.yaml"
      kind_render_config >"${config_file}"
      info "Configuration kind générée : ${config_file#"${LAB_ROOT}"/} (1 control-plane + ${WORKER_COUNT} worker(s), image ${LAB_R_KIND_NODE_IMAGE})"
    fi
    step "Création du cluster kind \"${CLUSTER_NAME}\" (1 à 3 minutes)"
    local wait=(--wait 5m)
    # Sans CNI, les nœuds restent NotReady : on n'attend pas leur disponibilité ici.
    [[ "${LAB_R_CNI_INSTALL:-platform}" == platform ]] || wait=()
    run kind create cluster --name "${CLUSTER_NAME}" --config "${config_file}" \
      --kubeconfig "${LAB_KUBECONFIG}" ${wait[@]+"${wait[@]}"} ||
      die "La création du cluster kind a échoué." \
        "Vérifiez que Docker fonctionne : docker info" \
        "Nettoyez puis réessayez : $(hint_cmd destroy kind)  puis  $(hint_cmd deploy kind)" \
        "Voir docs/troubleshooting.md"
  fi
  chmod 600 "${LAB_KUBECONFIG}"
  export KUBECONFIG="${LAB_KUBECONFIG}"
  [[ "${LAB_R_CNI_INSTALL:-platform}" != helm-local ]] || kind_install_cni
  kind_approve_kubelet_certificates

  post_deploy "${context}"
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
  rm -f "$(kind_kubeconfig_file)"
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
