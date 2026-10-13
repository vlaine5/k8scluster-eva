#!/usr/bin/env bash
# =============================================================================
#  Test d'intégration du chemin kubeadm SANS VMs, par le VRAI CLI :
#    ./k8s-lab deploy existing   (mode « machines existantes »)
#
#  Des conteneurs Docker privilégiés exécutant systemd jouent le rôle de
#  machines Ubuntu, Debian ou Rocky Linux déjà installées. Le test vérifie :
#    - contrôles préalables, site.yml (containerd, kubeadm, CNI, HA kube-vip) ;
#    - l'idempotence (2e déploiement : aucun changement sur les nœuds) ;
#    - le cluster (nœuds Ready, Pods système, test nginx + Service + DNS) ;
#    - en option : mise à niveau kubeadm (UPGRADE_TO) et restauration etcd
#      (RESTORE_TEST=1), avec les commandes make upgrade / backup / restore.
#
#    tests/kubeadm-in-docker/run.sh             crée, déploie, teste, puis nettoie
#    KEEP=1 tests/kubeadm-in-docker/run.sh      conserve le cluster à la fin
#    tests/kubeadm-in-docker/run.sh --destroy   nettoie
#
#  Variables : NODE_OS (ubuntu|debian|rocky), NODE_OS_VERSION, CONTROL_PLANES
#  (1|3|5), WORKERS, CNI (flannel|calico|cilium), KUBERNETES_VERSION,
#  UPGRADE_TO, RESTORE_TEST, ADDON_PROFILE, ADDONS, NODE_EXTRA_CA (certificat
#  d'un proxy TLS à faire confiance dans les nœuds).
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HERE="${ROOT}/tests/kubeadm-in-docker"
# Une variable vide (matrice de CI sans valeur) = non définie.
for variable in KUBERNETES_VERSION UPGRADE_TO RESTORE_TEST CNI NODE_OS_VERSION; do
  [[ -n "${!variable:-}" ]] || unset "${variable}"
done
NODE_OS="${NODE_OS:-ubuntu}"
case "${NODE_OS}" in
  ubuntu) NODE_OS_VERSION="${NODE_OS_VERSION:-24.04}" NODE_USER=ubuntu FAMILY=debian ;;
  debian) NODE_OS_VERSION="${NODE_OS_VERSION:-12}" NODE_USER=debian FAMILY=debian ;;
  rocky) NODE_OS_VERSION="${NODE_OS_VERSION:-9}" NODE_USER=rocky FAMILY=rocky ;;
  *) echo "NODE_OS=${NODE_OS} : ubuntu, debian ou rocky" >&2 && exit 2 ;;
esac
case "${NODE_OS}" in
  ubuntu | debian) BASE_IMAGE="${BASE_IMAGE:-docker.io/library/${NODE_OS}:${NODE_OS_VERSION}}" ;;
  rocky) BASE_IMAGE="${BASE_IMAGE:-docker.io/rockylinux/rockylinux:${NODE_OS_VERSION}}" ;;
esac
CONTROL_PLANES="${CONTROL_PLANES:-1}"
WORKERS="${WORKERS:-2}"
IMAGE="k8s-lab-test-node:${NODE_OS}-${NODE_OS_VERSION}"
NETWORK="k8s-lab-it"
SUBNET_PREFIX="172.31.250"
CLUSTER="k8s-lab-it"
CONTEXT="${CLUSTER}-existing"
STATE="${ROOT}/.lab/it-docker"
INVENTORY="${STATE}/inventory.ini"
ENV_FILE="${STATE}/lab.env"

export LAB_ROOT="${ROOT}"
# shellcheck source=../../scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"
# shellcheck source=../../scripts/lib/kubeconfig.sh
source "${ROOT}/scripts/lib/kubeconfig.sh"

node_names() {
  local i
  for ((i = 1; i <= CONTROL_PLANES; i++)); do echo "k8s-cp-${i}"; done
  for ((i = 1; i <= WORKERS; i++)); do echo "k8s-worker-${i}"; done
}

# Control-planes en .10, .11... ; workers en .20, .21... ; VIP de l'API (HA) en .9.
node_ip() {
  case "$1" in
    k8s-cp-*) echo "${SUBNET_PREFIX}.$((9 + ${1##*-}))" ;;
    k8s-worker-*) echo "${SUBNET_PREFIX}.$((19 + ${1##*-}))" ;;
  esac
}

# Le CLI lit la configuration du test dans ENV_FILE. Les variables d'environnement
# l'emportent sur ce fichier : celles du harnais (NODE_OS...) et les valeurs par défaut
# exportées par load_config (EXISTING_INVENTORY vide...) sont donc retirées pour
# chaque clé que ENV_FILE définit.
lab() {
  local key unset_args=()
  while IFS= read -r key; do
    unset_args+=(-u "${key}")
  done < <(sed -n -E 's/^([A-Z][A-Z0-9_]*)=.*/\1/p' "${ENV_FILE}")
  env "${unset_args[@]}" LAB_ENV_FILE="${ENV_FILE}" LAB_ANSIBLE_EXTRA_VARS="${HERE}/vars.yml" "${ROOT}/k8s-lab" "$@"
}

# État du cluster en cas d'échec (avant le nettoyage) : Pods, Pods non prêts, événements.
cluster_diagnostics() {
  local cp="k8s-cp-1"
  docker inspect "${cp}" >/dev/null 2>&1 || return 0
  step "Diagnostic du cluster (échec)"
  docker exec "${cp}" sh -c '
    k="kubectl --kubeconfig=/etc/kubernetes/admin.conf --request-timeout=20s"
    $k get nodes -o wide 2>&1
    $k get pods -A -o wide 2>&1
    for p in $($k get pods -A --no-headers 2>/dev/null | awk "\$4 != \"Running\" && \$4 != \"Completed\" {print \$1\"/\"\$2}"); do
      echo "--- $p"; $k -n "${p%%/*}" describe pod "${p#*/}" 2>&1 | tail -n 25
      $k -n "${p%%/*}" logs "${p#*/}" --all-containers --tail=30 2>&1
    done
    $k get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 40
    ip -br addr 2>&1
  ' || :
}

on_exit() {
  local status=$?
  ((status == 0)) || cluster_diagnostics
  destroy
}

destroy() {
  step "Nettoyage du test kubeadm-in-docker"
  local names
  names="$(docker ps -a --filter "label=k8s-lab-test=kubeadm-in-docker" --format '{{.Names}}')"
  if [[ -n "${names}" ]]; then
    # shellcheck disable=SC2086 # une liste de noms
    docker rm -f ${names} >/dev/null
  fi
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
  rm -f "${LAB_KUBE_DIR}/clusters/${CONTEXT}.yaml"
  rm -rf "${STATE}"
  kubeconfig_remove "${CONTEXT}" "${CONTEXT}" "${CONTEXT}-admin"
  ok "Nettoyé."
}

start_nodes() {
  local name ip cgroup_opts=() modules_opts=() dockerfile="${HERE}/Dockerfile.${FAMILY}"
  # cgroup v2 : chaque nœud a son propre espace cgroup ; cgroup v1 : celui de l'hôte.
  if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    cgroup_opts=(--cgroupns=private)
  else
    cgroup_opts=(--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw)
  fi
  # modprobe dans un nœud charge les modules dans le noyau de l'hôte.
  [[ -d /lib/modules ]] && modules_opts=(-v /lib/modules:/lib/modules:ro)

  step "Image des nœuds ${NODE_OS} ${NODE_OS_VERSION} (${BASE_IMAGE})"
  run docker build --quiet --build-arg "BASE_IMAGE=${BASE_IMAGE}" --build-arg "NODE_USER=${NODE_USER}" \
    -f "${dockerfile}" -t "${IMAGE}" "${HERE}"

  docker network inspect "${NETWORK}" >/dev/null 2>&1 ||
    run docker network create --subnet "${SUBNET_PREFIX}.0/24" "${NETWORK}"

  step "Démarrage de ${CONTROL_PLANES} control-plane(s) + ${WORKERS} worker(s)"
  while read -r name; do
    ip="$(node_ip "${name}")"
    if ! docker inspect "${name}" >/dev/null 2>&1; then
      # /var/lib/containerd et /var/lib/kubelet sur des volumes : pas d'overlay imbriqué.
      run docker run -d --name "${name}" --hostname "${name}" --label k8s-lab-test=kubeadm-in-docker \
        --privileged "${cgroup_opts[@]}" ${modules_opts[@]+"${modules_opts[@]}"} \
        --tmpfs /run --tmpfs /run/lock -v /var/lib/containerd -v /var/lib/kubelet \
        --network "${NETWORK}" --ip "${ip}" "${IMAGE}" >/dev/null
    fi
  done < <(node_names)

  ensure_ssh_key
  while read -r name; do
    docker cp "${SSH_PRIVATE_KEY_FILE}.pub" "${name}:/home/${NODE_USER}/.ssh/authorized_keys"
    docker exec "${name}" bash -c "chown ${NODE_USER}:${NODE_USER} /home/${NODE_USER}/.ssh/authorized_keys \
      && chmod 600 /home/${NODE_USER}/.ssh/authorized_keys \
      && printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv-kubelet.conf"
    if [[ -n "${NODE_EXTRA_CA:-}" ]]; then
      docker cp "${NODE_EXTRA_CA}" "${name}:/usr/local/share/ca-certificates/extra-ca.crt"
      docker exec "${name}" sh -c 'update-ca-certificates >/dev/null 2>&1 || update-ca-trust'
    fi
  done < <(node_names)
  wait_nodes
}

# Diagnostic d'un nœud injoignable en SSH. Chaque commande peut échouer (unité ou
# fichier absent selon la distribution) : le diagnostic ne doit jamais interrompre le script.
node_ssh_diagnostics() {
  local name="$1"
  docker exec "${name}" sh -c '
    echo "--- /run/nologin, /etc/nologin"; ls -l /run/nologin /etc/nologin 2>&1
    echo "--- unités en échec"; systemctl --failed --no-pager 2>&1
    echo "--- /etc/pam.d/sshd"; cat /etc/pam.d/sshd 2>&1
    echo "--- compte"; getent shadow '"${NODE_USER}"' | cut -d: -f2- 2>&1; chage -l '"${NODE_USER}"' 2>&1
    echo "--- sudo"; su -s /bin/sh '"${NODE_USER}"' -c "sudo -n true && echo sudo-ok" 2>&1
    echo "--- journal (sshd, sudo, pam)"; journalctl --no-pager -n 300 2>&1 | grep -Ei "sshd|sudo|pam" | tail -n 60
  ' || :
}

# Attend la fin du démarrage de systemd puis l'ouverture de SSH sur chaque nœud :
# make doctor vérifie SSH dès le début du déploiement.
wait_nodes() {
  local name state="" attempt
  while read -r name; do
    for ((attempt = 1; attempt <= 90; attempt++)); do
      # « degraded » (une unité sans objet dans un conteneur a échoué) suffit ;
      # is-system-running renvoie un code non nul tant que l'état n'est pas « running ».
      state="$(docker exec "${name}" systemctl is-system-running 2>/dev/null || :)"
      [[ "${state}" == running || "${state}" == degraded ]] && break
      sleep 2
    done
    [[ "${state}" == running || "${state}" == degraded ]] ||
      die "${name} : systemd n'a pas fini de démarrer (état : ${state:-inconnu})."
    # Une machine démarrée n'a pas de /run/nologin ; dans un conteneur Rocky, il peut
    # subsister (pam_nologin refuse alors toute connexion SSH) : signalé puis retiré.
    if docker exec "${name}" test -e /run/nologin; then
      info "${name} : /run/nologin présent après le démarrage (systemd ${state}) : retiré."
      docker exec "${name}" systemctl --failed --no-pager --plain || :
      docker exec "${name}" rm -f /run/nologin
    fi
    for ((attempt = 1; attempt <= 30; attempt++)); do
      if ssh -n -i "${SSH_PRIVATE_KEY_FILE}" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${NODE_USER}@$(node_ip "${name}")" true; then
        # Ansible a besoin de sudo sans mot de passe : vérifié ici, avec le diagnostic au besoin.
        if ssh -n -i "${SSH_PRIVATE_KEY_FILE}" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${NODE_USER}@$(node_ip "${name}")" sudo -n true; then
          continue 2
        fi
        node_ssh_diagnostics "${name}"
        die "${name} : sudo sans mot de passe refusé pour ${NODE_USER}."
      fi
      sleep 2
    done
    node_ssh_diagnostics "${name}"
    die "${name} : connexion SSH impossible (${NODE_USER}@$(node_ip "${name}"), clé ${SSH_PRIVATE_KEY_FILE})."
  done < <(node_names)
  ok "Nœuds démarrés, SSH disponible."
}

# Inventaire et configuration du mode existing, comme les écrirait un utilisateur.
write_configuration() {
  local name
  mkdir -p "${STATE}"
  {
    echo "# Inventaire du test tests/kubeadm-in-docker (généré)."
    echo "[control_plane]"
    while read -r name; do
      [[ "${name}" == k8s-cp-* ]] && echo "${name} ansible_host=$(node_ip "${name}") node_ip=$(node_ip "${name}")"
    done < <(node_names)
    printf '\n[workers]\n'
    while read -r name; do
      [[ "${name}" == k8s-worker-* ]] && echo "${name} ansible_host=$(node_ip "${name}") node_ip=$(node_ip "${name}")"
    done < <(node_names)
    printf '\n[k8s_cluster:children]\ncontrol_plane\nworkers\n\n'
    printf '[k8s_cluster:vars]\nansible_user=%s\nansible_ssh_private_key_file=%s\n' "${NODE_USER}" "${SSH_PRIVATE_KEY_FILE}"
  } >"${INVENTORY}"
  {
    echo "# Configuration du test tests/kubeadm-in-docker (générée)."
    echo "DEPLOYMENT_MODE=existing"
    echo "CLUSTER_NAME=${CLUSTER}"
    echo "EXISTING_INVENTORY=${INVENTORY}"
    echo "CONTROL_PLANE_COUNT=${CONTROL_PLANES}"
    echo "WORKER_COUNT=${WORKERS}"
    echo "NODE_OS=auto"
    echo "NODE_NETWORK_CIDR=${SUBNET_PREFIX}.0/24"
    echo "CNI=${CNI:-auto}"
    echo "KUBERNETES_VERSION=${KUBERNETES_VERSION:-$(sed -n 's/^KUBERNETES_VERSION=//p' "${ROOT}/config/lab.env")}"
    echo "ADDON_PROFILE=${ADDON_PROFILE:-minimal}"
    echo "ADDONS=${ADDONS:-}"
    if ((CONTROL_PLANES > 1)); then
      echo "HA_MODE=stacked-etcd"
      echo "CONTROL_PLANE_VIP=${SUBNET_PREFIX}.9"
    fi
  } >"${ENV_FILE}"
  info "Inventaire : ${INVENTORY#"${ROOT}"/}   Configuration : ${ENV_FILE#"${ROOT}"/}"
}

check_idempotence() {
  local log="${STATE}/second-deploy.log"
  step "Vérification de l'idempotence (2e déploiement)"
  lab deploy existing --yes 2>&1 | tee "${log}"
  # Récapitulatifs Ansible des NŒUDS (localhost = addons, hors de ce contrôle).
  if grep -E '^k8s-[a-z0-9-]+ +: .*changed=[1-9]' "${log}"; then
    die "Le 2e déploiement a modifié des nœuds : le playbook n'est pas idempotent."
  fi
  ok "Idempotence vérifiée : aucun changement sur les nœuds au 2e déploiement."
}

check_upgrade() {
  local version
  step "Mise à niveau kubeadm vers ${UPGRADE_TO} (make upgrade-plan, puis make upgrade)"
  sed -i "s/^KUBERNETES_VERSION=.*/KUBERNETES_VERSION=${UPGRADE_TO}/" "${ENV_FILE}"
  lab upgrade-plan existing
  UPGRADE_CONFIRM="${CONTEXT}" lab upgrade existing --yes
  version="$(kubectl --context "${CONTEXT}" get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u)"
  [[ "${version}" == "v${UPGRADE_TO}" ]] || die "Après la mise à niveau, les kubelets sont en : ${version//$'\n'/ }"
  ok "Tous les nœuds sont en v${UPGRADE_TO}."
}

check_restore() {
  local snapshot
  step "Exercice de restauration etcd (make backup, modification, make restore)"
  kubectl --context "${CONTEXT}" create configmap restore-before -n default --from-literal=state=before
  lab backup existing
  snapshot="$(find "${ROOT}/.lab/backups/${CONTEXT}" -name 'etcd-*.db' -newer "${ENV_FILE}" | sort | tail -n1)"
  [[ -n "${snapshot}" ]] || die "Aucun instantané etcd récupéré dans .lab/backups/${CONTEXT}/"
  kubectl --context "${CONTEXT}" create configmap restore-after -n default --from-literal=state=after
  SNAPSHOT="${snapshot}" RESTORE_CONFIRM="${CONTEXT}" lab restore existing --yes
  kubectl --context "${CONTEXT}" wait --for=condition=Ready nodes --all --timeout=300s
  kubectl --context "${CONTEXT}" get configmap restore-before -n default >/dev/null ||
    die "La ConfigMap créée AVANT l'instantané est absente après la restauration."
  if kubectl --context "${CONTEXT}" get configmap restore-after -n default >/dev/null 2>&1; then
    die "La ConfigMap créée APRÈS l'instantané existe encore : la restauration n'a pas eu lieu."
  fi
  ok "Restauration etcd vérifiée (état de l'instantané retrouvé)."
}

main() {
  if [[ "${1:-}" == "--destroy" ]]; then
    load_config
    destroy
    return
  fi
  have docker || die "Docker est requis pour ce test."
  have ansible-playbook || die "Ansible est requis pour ce test." "make venv"
  load_config
  ensure_state_dirs
  [[ "${KEEP:-0}" == "1" ]] || trap on_exit EXIT

  start_nodes
  write_configuration

  step "Déploiement par le CLI : ./k8s-lab deploy existing"
  lab deploy existing --yes
  check_idempotence

  export KUBECONFIG="${LAB_KUBECONFIG}"
  kubectl config use-context "${CONTEXT}" >/dev/null
  lab test
  [[ -z "${UPGRADE_TO:-}" ]] || check_upgrade
  [[ "${RESTORE_TEST:-0}" != "1" ]] || check_restore
  ok "Test kubeadm-in-docker réussi (${NODE_OS} ${NODE_OS_VERSION}, ${CONTROL_PLANES} CP + ${WORKERS} worker(s), CNI ${CNI:-auto})."
}

main "$@"
