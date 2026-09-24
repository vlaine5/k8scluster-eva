#!/usr/bin/env bash
# =============================================================================
#  Vérifie que les valeurs par défaut recopiées hors de config/lab.env
#  (variables Terraform, group_vars Ansible, config kind versionnée) sont
#  identiques à celles de config/lab.env. Lancé par la CI et "make check-config".
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

echo "Terraform (valeurs par défaut des variables) :"
for provider in proxmox vsphere libvirt; do
  file="${ROOT}/terraform/providers/${provider}/variables.tf"
  expect "${provider}: cluster_name" "$(tf_default "${file}" cluster_name)" "$(lab_value CLUSTER_NAME)"
  expect "${provider}: worker_count" "$(tf_default "${file}" worker_count)" "$(lab_value WORKER_COUNT)"
  expect "${provider}: hostname_prefix" "$(tf_default "${file}" hostname_prefix)" "$(lab_value NODE_HOSTNAME_PREFIX)"
  expect "${provider}: node_cpus" "$(tf_default "${file}" node_cpus)" "$(lab_value NODE_CPUS)"
  expect "${provider}: node_memory_mb" "$(tf_default "${file}" node_memory_mb)" "$(lab_value NODE_MEMORY_MB)"
  expect "${provider}: node_disk_gb" "$(tf_default "${file}" node_disk_gb)" "$(lab_value NODE_DISK_GB)"
done
expect "proxmox: image_url" "$(tf_default "${ROOT}/terraform/providers/proxmox/variables.tf" image_url)" "$(lab_value VM_IMAGE_URL)"
expect "proxmox: image_sha256" "$(tf_default "${ROOT}/terraform/providers/proxmox/variables.tf" image_sha256)" "$(lab_value VM_IMAGE_SHA256)"
expect "libvirt: image_source" "$(tf_default "${ROOT}/terraform/providers/libvirt/variables.tf" image_source)" "$(lab_value VM_IMAGE_URL)"
expect "module k8s-nodes: worker_count" "$(tf_default "${ROOT}/terraform/modules/k8s-nodes/variables.tf" worker_count)" "$(lab_value WORKER_COUNT)"
eks="${ROOT}/terraform/providers/eks/variables.tf"
expect "eks: cluster_name" "$(tf_default "${eks}" cluster_name)" "$(lab_value CLUSTER_NAME)"
expect "eks: worker_count" "$(tf_default "${eks}" worker_count)" "$(lab_value WORKER_COUNT)"
expect "eks: kubernetes_version" "$(tf_default "${eks}" kubernetes_version)" "$(lab_value EKS_KUBERNETES_VERSION)"
expect "eks: aws_target" "$(tf_default "${eks}" aws_target)" "$(lab_value AWS_TARGET)"
expect "eks: localstack_endpoint" "$(tf_default "${eks}" localstack_endpoint)" "$(lab_value LOCALSTACK_ENDPOINT)"
expect "module k8s-nodes: hostname_prefix" "$(tf_default "${ROOT}/terraform/modules/k8s-nodes/variables.tf" hostname_prefix)" "$(lab_value NODE_HOSTNAME_PREFIX)"

echo "Ansible (ansible/group_vars/all.yml) :"
vars="${ROOT}/ansible/group_vars/all.yml"
expect "kubernetes_version" "$(yaml_value "${vars}" kubernetes_version)" "$(lab_value KUBERNETES_VERSION)"
expect "pod_cidr" "$(yaml_value "${vars}" pod_cidr)" "$(lab_value POD_CIDR)"
expect "service_cidr" "$(yaml_value "${vars}" service_cidr)" "$(lab_value SERVICE_CIDR)"
expect "cni" "$(yaml_value "${vars}" cni)" "$(lab_value CNI)"
expect "flannel_version" "$(yaml_value "${vars}" flannel_version)" "$(lab_value FLANNEL_VERSION)"
expect "container_runtime" "$(yaml_value "${vars}" container_runtime)" "$(lab_value CONTAINER_RUNTIME)"
expect "containerd_version" "$(yaml_value "${vars}" containerd_version)" "$(lab_value CONTAINERD_VERSION)"
if grep -q "^  $(lab_value FLANNEL_VERSION): \"sha256:[0-9a-f]\{64\}\"$" "${ROOT}/ansible/roles/cni/defaults/main.yml"; then
  printf '  ok     checksum du manifeste Flannel %s connu\n' "$(lab_value FLANNEL_VERSION)"
else
  printf '  DRIFT  aucun checksum pour Flannel %s dans roles/cni/defaults/main.yml\n' "$(lab_value FLANNEL_VERSION)"
  ERRORS=$((ERRORS + 1))
fi

echo "Kind (local/kind/kind-config.yaml) :"
if diff -u "${ROOT}/local/kind/kind-config.yaml" <(env -i PATH="${PATH}" HOME="${HOME}" NO_COLOR=1 "${ROOT}/k8s-lab" config kind); then
  printf '  ok     identique à la configuration générée par défaut\n'
else
  printf '  DRIFT  régénérez-la : ./k8s-lab config kind > local/kind/kind-config.yaml\n'
  ERRORS=$((ERRORS + 1))
fi

if ((ERRORS > 0)); then
  printf '\n%d incohérence(s) : alignez ces valeurs sur config/lab.env.\n' "${ERRORS}"
  exit 1
fi
printf '\nToutes les valeurs par défaut sont cohérentes avec config/lab.env.\n'
