#!/usr/bin/env bash
# =============================================================================
#  Test d'intégration du rôle Ansible "kubeadm" SANS VMs.
#
#  Des conteneurs Docker privilégiés exécutant systemd jouent le rôle de VMs
#  Ubuntu 24.04 ; le VRAI playbook ansible/site.yml y construit un cluster
#  (containerd, kubeadm init/join, Flannel). Le test vérifie ensuite :
#    - l'idempotence (2e exécution : aucun changement) ;
#    - le cluster (nœuds Ready, Pods système) et un test nginx + Service + DNS.
#
#    tests/kubeadm-in-docker/run.sh             crée, déploie, teste, puis nettoie
#    KEEP=1 tests/kubeadm-in-docker/run.sh      conserve le cluster à la fin
#    tests/kubeadm-in-docker/run.sh --destroy   nettoie
#
#  Variables : WORKERS (défaut 2), BASE_IMAGE (image Ubuntu 24.04),
#  NODE_EXTRA_CA (certificat d'un proxy TLS d'entreprise à faire confiance
#  dans les nœuds), EXTRA_VARS_FILE (variables Ansible supplémentaires).
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HERE="${ROOT}/tests/kubeadm-in-docker"
WORKERS="${WORKERS:-2}"
BASE_IMAGE="${BASE_IMAGE:-docker.io/library/ubuntu:24.04}"
IMAGE="k8s-lab-test-node:24.04"
NETWORK="k8s-lab-it"
SUBNET_PREFIX="172.31.250"
CONTEXT="k8s-lab-docker"
INVENTORY_REL="inventories/it-docker.ini"

export LAB_ROOT="${ROOT}"
# shellcheck source=../../scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"
# shellcheck source=../../scripts/lib/kubeconfig.sh
source "${ROOT}/scripts/lib/kubeconfig.sh"
# shellcheck source=../../scripts/lib/smoke.sh
source "${ROOT}/scripts/lib/smoke.sh"
# shellcheck source=../../scripts/lib/ansible.sh
source "${ROOT}/scripts/lib/ansible.sh"

node_names() {
  local i
  echo "k8s-cp-1"
  for ((i = 1; i <= WORKERS; i++)); do echo "k8s-worker-${i}"; done
}

node_ip() {
  case "$1" in
    k8s-cp-1) echo "${SUBNET_PREFIX}.10" ;;
    k8s-worker-*) echo "${SUBNET_PREFIX}.$((10 + ${1##*-}))" ;;
  esac
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
  known_hosts_forget "${INVENTORY_REL}"
  rm -f "${ROOT}/ansible/${INVENTORY_REL}" "${LAB_KUBE_DIR}/clusters/${CONTEXT}.yaml"
  kubeconfig_remove "${CONTEXT}" "${CONTEXT}" "${CONTEXT}-admin"
  ok "Nettoyé."
}

start_nodes() {
  local name ip cgroup_opts=() modules_opts=()
  # cgroup v2 : chaque nœud a son propre espace cgroup ; cgroup v1 : celui de l'hôte.
  if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    cgroup_opts=(--cgroupns=private)
  else
    cgroup_opts=(--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw)
  fi
  # modprobe dans un nœud charge les modules dans le noyau de l'hôte.
  [[ -d /lib/modules ]] && modules_opts=(-v /lib/modules:/lib/modules:ro)

  step "Image des nœuds (${BASE_IMAGE})"
  run docker build --quiet --build-arg "BASE_IMAGE=${BASE_IMAGE}" -t "${IMAGE}" "${HERE}"

  docker network inspect "${NETWORK}" >/dev/null 2>&1 ||
    run docker network create --subnet "${SUBNET_PREFIX}.0/24" "${NETWORK}"

  step "Démarrage de 1 control-plane + ${WORKERS} worker(s)"
  while read -r name; do
    ip="$(node_ip "${name}")"
    if ! docker inspect "${name}" >/dev/null 2>&1; then
      run docker run -d --name "${name}" --hostname "${name}" --label k8s-lab-test=kubeadm-in-docker \
        --privileged "${cgroup_opts[@]}" ${modules_opts[@]+"${modules_opts[@]}"} \
        --tmpfs /run --tmpfs /run/lock -v /var/lib/containerd -v /var/lib/kubelet \
        --network "${NETWORK}" --ip "${ip}" "${IMAGE}" >/dev/null
    fi
  done < <(node_names)

  ensure_ssh_key
  while read -r name; do
    docker cp "${SSH_PRIVATE_KEY_FILE}.pub" "${name}:/home/ubuntu/.ssh/authorized_keys"
    docker exec "${name}" bash -c 'chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys && chmod 600 /home/ubuntu/.ssh/authorized_keys
      printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv-kubelet.conf'
    if [[ -n "${NODE_EXTRA_CA:-}" ]]; then
      docker cp "${NODE_EXTRA_CA}" "${name}:/usr/local/share/ca-certificates/extra-ca.crt"
      docker exec "${name}" update-ca-certificates >/dev/null
    fi
  done < <(node_names)
}

write_inventory() {
  local name file="${ROOT}/ansible/${INVENTORY_REL}"
  {
    echo "# Inventaire du test tests/kubeadm-in-docker (généré)."
    echo "[control_plane]"
    echo "k8s-cp-1 ansible_host=$(node_ip k8s-cp-1) node_ip=$(node_ip k8s-cp-1)"
    echo
    echo "[workers]"
    while read -r name; do
      [[ "${name}" == k8s-worker-* ]] && echo "${name} ansible_host=$(node_ip "${name}") node_ip=$(node_ip "${name}")"
    done < <(node_names)
    echo
    printf '[k8s_cluster:children]\ncontrol_plane\nworkers\n\n'
    printf '[k8s_cluster:vars]\nansible_user=ubuntu\nansible_ssh_private_key_file=%s\ncluster_name=%s\n' \
      "${SSH_PRIVATE_KEY_FILE}" "${CONTEXT}"
  } >"${file}"
  info "Inventaire : ansible/${INVENTORY_REL}"
}

playbook_args() {
  PLAYBOOK_ARGS=(-e "@${HERE}/vars.yml")
  if [[ -n "${EXTRA_VARS_FILE:-}" ]]; then
    PLAYBOOK_ARGS+=(-e "@${EXTRA_VARS_FILE}")
  fi
}

main() {
  if [[ "${1:-}" == "--destroy" ]]; then
    load_config
    destroy
    return
  fi
  have docker || die "Docker est requis pour ce test."
  have ansible-playbook || die "Ansible est requis pour ce test." "pip install -r requirements-dev.txt"
  load_config
  ensure_state_dirs
  [[ "${KEEP:-0}" == "1" ]] || trap destroy EXIT

  start_nodes
  write_inventory
  playbook_args

  # 1re exécution : construction du cluster.
  ansible_install_kubernetes "${INVENTORY_REL}" "${PLAYBOOK_ARGS[@]}"

  # 2e exécution : rien ne doit changer (idempotence).
  step "Vérification de l'idempotence (2e exécution du playbook)"
  local log="${LAB_STATE_DIR}/ansible/it-docker-second-run.log"
  ansible_install_kubernetes "${INVENTORY_REL}" "${PLAYBOOK_ARGS[@]}" | tee "${log}"
  if grep -E '^[a-z0-9-]+ +: .*changed=[1-9]' "${log}"; then
    die "La 2e exécution du playbook a modifié des nœuds : le playbook n'est pas idempotent."
  fi
  ok "Idempotence vérifiée : aucun changement à la 2e exécution."

  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${CONTEXT}.yaml" "${CONTEXT}"
  smoke_basic "${CONTEXT}"
  smoke_app --cleanup
  ok "Test kubeadm-in-docker réussi."
}

main "$@"
