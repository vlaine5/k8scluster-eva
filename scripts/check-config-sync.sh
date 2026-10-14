#!/usr/bin/env bash
# =============================================================================
#  Vérifie que les valeurs par défaut recopiées hors de config/lab.env et de
#  config/versions.yaml (variables Terraform, group_vars Ansible, boîtes
#  Vagrant, config kind versionnée) leur sont identiques. Lancé par la CI et
#  "make check-config".
#
#  Pourquoi des copies ? Terraform et Ansible doivent rester utilisables seuls
#  (sans ./k8s-lab). Ce script empêche qu'elles divergent.
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ERRORS=0

lab_value() {
  sed -n -E "s/^$1=(.*)$/\1/p" "${ROOT}/config/lab.env" | tail -n1
}

# Valeur "default" d'une variable Terraform (chaîne ou nombre).
tf_default() {
  awk -v var="$2" '
    $0 ~ "^variable \"" var "\" [{]" { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside && $1 == "default" { sub(/^[^=]*=[ \t]*/, ""); gsub(/"/, ""); print; exit }
  ' "$1"
}

yaml_value() {
  sed -n -E "s/^$2:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/p" "$1" | head -n1
}

expect() {
  local label="$1" actual="$2" expected="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    printf '  ok     %s\n' "${label}"
  else
    printf '  DRIFT  %s : "%s" au lieu de "%s" (config/lab.env)\n' "${label}" "${actual}" "${expected}"
    ERRORS=$((ERRORS + 1))
  fi
}

# Valeur résolue par scripts/labctl avec la configuration PAR DÉFAUT (sans .env).
resolved() {
  LAB_ENV_FILE=/dev/null env -i PATH="${PATH}" HOME="${HOME}" LAB_ENV_FILE=/dev/null \
    python3 "${ROOT}/scripts/labctl" get "$2" --mode "$1" ${3:+--provider "$3"}
}

# Valeur de config/versions.yaml (chemin pointé : os.ubuntu.24.04.image_url).
locked() {
  python3 - "${ROOT}/config/versions.yaml" "$1" <<'PY'
import sys, yaml
value = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
key = sys.argv[2]
if key.startswith("os."):
    name, rest = key[3:].split(".", 1)
    version, field = rest.rsplit(".", 1)
    path = ["os", name, version, field]
else:
    path = key.split(".")
for part in path:
    value = value[part]
print(value)
PY
}

echo "Terraform (valeurs par défaut des variables) :"
for provider in proxmox vsphere libvirt; do
  file="${ROOT}/terraform/providers/${provider}/variables.tf"
  expect "${provider}: cluster_name" "$(tf_default "${file}" cluster_name)" "$(lab_value CLUSTER_NAME)"
  expect "${provider}: control_plane_count" "$(tf_default "${file}" control_plane_count)" "$(lab_value CONTROL_PLANE_COUNT)"
  expect "${provider}: worker_count" "$(tf_default "${file}" worker_count)" "$(lab_value WORKER_COUNT)"
  expect "${provider}: hostname_prefix" "$(tf_default "${file}" hostname_prefix)" "$(lab_value NODE_HOSTNAME_PREFIX)"
  expect "${provider}: node_cpus" "$(tf_default "${file}" node_cpus)" "$(lab_value NODE_CPUS)"
  expect "${provider}: node_memory_mb" "$(tf_default "${file}" node_memory_mb)" "$(lab_value NODE_MEMORY_MB)"
  expect "${provider}: node_disk_gb" "$(tf_default "${file}" node_disk_gb)" "$(lab_value NODE_DISK_GB)"
done
default_os="$(lab_value NODE_OS).$(lab_value NODE_OS_VERSION)"
expect "proxmox: image_url" "$(tf_default "${ROOT}/terraform/providers/proxmox/variables.tf" image_url)" "$(locked "os.${default_os}.image_url")"
expect "proxmox: image_sha256" "$(tf_default "${ROOT}/terraform/providers/proxmox/variables.tf" image_sha256)" "$(locked "os.${default_os}.image_sha256")"
expect "proxmox: cpu_type" "$(tf_default "${ROOT}/terraform/providers/proxmox/variables.tf" cpu_type)" "$(lab_value NODE_CPU_TYPE)"
expect "libvirt: image_source" "$(tf_default "${ROOT}/terraform/providers/libvirt/variables.tf" image_source)" "$(locked "os.${default_os}.image_url")"
expect "module k8s-nodes: worker_count" "$(tf_default "${ROOT}/terraform/modules/k8s-nodes/variables.tf" worker_count)" "$(lab_value WORKER_COUNT)"
expect "module k8s-nodes: control_plane_count" "$(tf_default "${ROOT}/terraform/modules/k8s-nodes/variables.tf" control_plane_count)" "$(lab_value CONTROL_PLANE_COUNT)"
expect "module k8s-nodes: hostname_prefix" "$(tf_default "${ROOT}/terraform/modules/k8s-nodes/variables.tf" hostname_prefix)" "$(lab_value NODE_HOSTNAME_PREFIX)"
eks="${ROOT}/terraform/providers/eks/variables.tf"
expect "eks: cluster_name" "$(tf_default "${eks}" cluster_name)" "$(lab_value CLUSTER_NAME)"
expect "eks: worker_count" "$(tf_default "${eks}" worker_count)" "$(lab_value WORKER_COUNT)"
expect "eks: kubernetes_version" "$(tf_default "${eks}" kubernetes_version)" "$(lab_value EKS_KUBERNETES_VERSION)"
expect "eks: aws_target" "$(tf_default "${eks}" aws_target)" "$(lab_value AWS_TARGET)"
expect "eks: localstack_endpoint" "$(tf_default "${eks}" localstack_endpoint)" "$(lab_value LOCALSTACK_ENDPOINT)"

echo "Ansible (ansible/group_vars/all.yml, utilisé seul sans ./k8s-lab) :"
vars="${ROOT}/ansible/group_vars/all.yml"
expect "kubernetes_version" "$(yaml_value "${vars}" kubernetes_version)" "$(lab_value KUBERNETES_VERSION)"
expect "pod_cidr" "$(yaml_value "${vars}" pod_cidr)" "$(lab_value POD_CIDR)"
expect "service_cidr" "$(yaml_value "${vars}" service_cidr)" "$(lab_value SERVICE_CIDR)"
expect "cni (CNI=auto en kubeadm)" "$(yaml_value "${vars}" cni)" "$(resolved vagrant cni)"
expect "flannel_version" "$(yaml_value "${vars}" flannel_version)" "$(locked components.flannel.version)"
expect "containerd_version" "$(yaml_value "${vars}" containerd_version)" "$(locked containerd.version)"

echo "Vagrant (boîtes par OS de vagrant/Vagrantfile) :"
for entry in ubuntu.24.04 ubuntu.26.04 debian.12 debian.13 rocky.9 rocky.10; do
  key="${entry%%.*}-${entry#*.}"
  box="$(sed -n -E "s/.*\"${key}\" => \"([^\"]+)\".*/\\1/p" "${ROOT}/vagrant/Vagrantfile" | head -n1)"
  expect "box ${key}" "${box}" "$(locked "os.${entry}.vagrant_box")"
done

echo "Kind (local/kind/kind-config.yaml) :"
generated="$(env -i PATH="${PATH}" HOME="${HOME}" NO_COLOR=1 LAB_ENV_FILE=/dev/null "${ROOT}/k8s-lab" config kind-config)" ||
  generated=""
if [[ -z "${generated}" ]]; then
  printf '  DRIFT  ./k8s-lab config kind-config a échoué\n'
  ERRORS=$((ERRORS + 1))
elif diff -u "${ROOT}/local/kind/kind-config.yaml" <(printf '%s\n' "${generated}"); then
  printf '  ok     identique à la configuration générée par défaut\n'
else
  printf '  DRIFT  régénérez-la : LAB_ENV_FILE=/dev/null ./k8s-lab config kind-config > local/kind/kind-config.yaml\n'
  ERRORS=$((ERRORS + 1))
fi

if ((ERRORS > 0)); then
  printf '\n%d incohérence(s) : alignez ces valeurs sur config/lab.env.\n' "${ERRORS}"
  exit 1
fi
printf '\nToutes les valeurs par défaut sont cohérentes avec config/lab.env.\n'
