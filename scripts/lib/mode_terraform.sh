#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode terraform : VMs créées par Terraform (Proxmox, vSphere, libvirt),
#  Kubernetes installé par Ansible + kubeadm (niveau 3, Infrastructure as Code).
#
#    terraform plan/apply  -> VMs + ansible/inventories/terraform-<provider>.ini
#    ansible-playbook      -> kubeadm init / join, CNI, vérifications
# =============================================================================

TERRAFORM_PROVIDERS="proxmox, vsphere, libvirt"

# terraform, ou OpenTofu (tofu) s'il est seul installé. Forçable : TERRAFORM_BIN=tofu
terraform_bin() {
  if [[ -n "${TERRAFORM_BIN:-}" ]]; then
    echo "${TERRAFORM_BIN}"
  elif have terraform; then
    echo terraform
  elif have tofu; then
    echo tofu
  fi
}

tf_check_provider() {
  case "$1" in
    proxmox | vsphere | libvirt) ;;
    "") die "Précisez le provider Terraform." "Exemple : ./k8s-lab deploy terraform proxmox" "Providers : ${TERRAFORM_PROVIDERS}" ;;
    *) die "Provider Terraform inconnu : \"$1\"." "Providers disponibles : ${TERRAFORM_PROVIDERS}" ;;
  esac
}

tf_dir() { echo "${LAB_ROOT}/terraform/providers/$1"; }
tf_context() { echo "${CLUSTER_NAME}-$1"; }
tf_inventory() { echo "inventories/terraform-$1.ini"; }

tf() {
  local provider="$1"
  shift
  run "$(terraform_bin)" -chdir="terraform/providers/${provider}" "$@"
}

# Réglages de config/lab.env transmis à Terraform (variables TF_VAR_*).
# Les réglages propres à l'infrastructure restent dans terraform.tfvars.
tf_export_vars() {
  local provider="$1"
  ensure_ssh_key
  export TF_VAR_cluster_name="${CLUSTER_NAME}"
  export TF_VAR_worker_count="${WORKER_COUNT}"
  export TF_VAR_hostname_prefix="${NODE_HOSTNAME_PREFIX}"
  export TF_VAR_node_cpus="${NODE_CPUS}"
  export TF_VAR_node_memory_mb="${NODE_MEMORY_MB}"
  export TF_VAR_node_disk_gb="${NODE_DISK_GB}"
  export TF_VAR_ssh_private_key_file="${SSH_PRIVATE_KEY_FILE}"
  TF_VAR_ssh_public_key="$(cat "${SSH_PRIVATE_KEY_FILE}.pub")"
  export TF_VAR_ssh_public_key
  case "${provider}" in
    proxmox)
      export TF_VAR_image_url="${VM_IMAGE_URL}"
      export TF_VAR_image_sha256="${VM_IMAGE_SHA256}"
      ;;
    libvirt)
      tf_libvirt_prepare_image
      ;;
  esac
}

# libvirt : l'image est téléchargée une seule fois dans .lab/cache/ et son
# SHA-256 est vérifié AVANT d'être confiée à Terraform.
tf_libvirt_prepare_image() {
  local cache="${LAB_STATE_DIR}/cache/images" file sum
  file="${cache}/$(basename "${VM_IMAGE_URL}")"
  mkdir -p "${cache}"
  if [[ ! -f "${file}" ]]; then
    step "Téléchargement de l'image Ubuntu (une seule fois) : ${VM_IMAGE_URL}"
    run curl -fL --progress-bar -o "${file}.part" "${VM_IMAGE_URL}" ||
      die "Téléchargement impossible : ${VM_IMAGE_URL}" "Vérifiez votre connexion Internet."
    mv "${file}.part" "${file}"
  fi
  if have sha256sum; then
    sum="$(sha256sum "${file}" | awk '{print $1}')"
  else
    sum="$(shasum -a 256 "${file}" | awk '{print $1}')"
  fi
  if [[ "${sum}" != "${VM_IMAGE_SHA256}" ]]; then
    rm -f "${file}"
    die "Empreinte SHA-256 incorrecte pour $(basename "${file}") : fichier supprimé." \
      "Attendu : ${VM_IMAGE_SHA256}" "Obtenu  : ${sum}" \
      "Si vous avez changé VM_IMAGE_URL, mettez aussi à jour VM_IMAGE_SHA256 (fichier SHA256SUMS de la release)."
  fi
  ok "Image vérifiée (SHA-256) : ${file#"${LAB_ROOT}"/}"
  export TF_VAR_image_source="${file}"
}

# Vrai si le state Terraform local contient des ressources.
tf_has_resources() {
  local state
  state="$(tf_dir "$1")/terraform.tfstate"
  [[ -s "${state}" ]] && grep -q '"mode": "managed"' "${state}"
}

terraform_deploy() {
  local provider="$1" context plan summary
  tf_check_provider "${provider}"
  context="$(tf_context "${provider}")"
  require_doctor terraform "${provider}"

  if [[ "${RECREATE:-0}" == "1" ]] && tf_has_resources "${provider}"; then
    terraform_destroy "${provider}"
  fi

  tf_export_vars "${provider}"
  mkdir -p "${LAB_STATE_DIR}/terraform"
  plan="${LAB_STATE_DIR}/terraform/${provider}.tfplan"

  step "Terraform : initialisation (téléchargement des providers)"
  (cd "${LAB_ROOT}" && tf "${provider}" init -input=false) ||
    die "terraform init a échoué." "Vérifiez votre accès à registry.terraform.io."

  step "Terraform : calcul du plan (ce qui va être créé / modifié / détruit)"
  # Un plan peut contenir des valeurs sensibles : fichier privé, supprimé après usage.
  (umask 077 && cd "${LAB_ROOT}" && tf "${provider}" plan -input=false -out="${plan}") ||
    die "terraform plan a échoué (voir l'erreur ci-dessus)." \
      "Vérifiez terraform/providers/${provider}/terraform.tfvars et vos identifiants dans .env."

  summary="$("$(terraform_bin)" -chdir="$(tf_dir "${provider}")" show -no-color "${plan}" |
    grep -E '^(Plan:|No changes)')" || summary=""
  if [[ "${summary}" == No\ changes* ]]; then
    ok "L'infrastructure est déjà à jour : rien à créer."
  else
    if [[ "${summary}" =~ ([1-9][0-9]*)\ to\ destroy ]]; then
      warn "Ce plan DÉTRUIT ${BASH_REMATCH[1]} ressource(s) existante(s) (VM recréée ou worker supprimé ?)."
      warn "Relisez le plan ci-dessus avant de confirmer."
    fi
    confirm "Appliquer ce plan (${summary}) ?" || {
      rm -f "${plan}"
      die "Déploiement annulé : rien n'a été modifié."
    }
    (cd "${LAB_ROOT}" && tf "${provider}" apply -input=false "${plan}") || {
      rm -f "${plan}"
      die "terraform apply a échoué (voir l'erreur ci-dessus)." \
        "Relancer est sans danger : Terraform reprend là où il s'est arrêté."
    }
  fi
  rm -f "${plan}"

  ansible_install_kubernetes "$(tf_inventory "${provider}")"
  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  smoke_basic "${context}"
  kubeconfig_hint "${context}"
  printf '\nAdresses et commandes SSH : %s -chdir=terraform/providers/%s output\n' "$(terraform_bin)" "${provider}"
}

terraform_destroy() {
  local provider="$1" context
  tf_check_provider "${provider}"
  context="$(tf_context "${provider}")"
  if ! tf_has_resources "${provider}"; then
    info "Aucune ressource Terraform ${provider} dans le state : rien à détruire."
  else
    [[ -n "$(terraform_bin)" ]] || die "Terraform (ou OpenTofu) est introuvable." "./k8s-lab doctor terraform ${provider}"
    confirm "Détruire TOUTES les VMs Terraform ${provider} du lab (terraform destroy) ?" || die "Destruction annulée."
    known_hosts_forget "$(tf_inventory "${provider}")"
    tf_export_vars "${provider}"
    (cd "${LAB_ROOT}" && tf "${provider}" init -input=false >/dev/null &&
      tf "${provider}" destroy -input=false -auto-approve) ||
      die "terraform destroy a échoué." "Relancez la commande : elle reprend là où elle s'est arrêtée."
  fi
  rm -f "${LAB_KUBE_DIR}/clusters/${context}.yaml"
  kubeconfig_remove "${context}" "${context}" "${context}-admin"
  ok "Lab Terraform ${provider} nettoyé."
}

terraform_status() {
  local provider
  for provider in proxmox vsphere libvirt; do
    if tf_has_resources "${provider}"; then
      status_line up "tf ${provider}" "VMs déployées (contexte $(tf_context "${provider}")) : terraform -chdir=terraform/providers/${provider} output"
    else
      status_line none "tf ${provider}" "aucune VM"
    fi
  done
}

terraform_kubeconfig() {
  local provider="$1" context
  tf_check_provider "${provider}"
  context="$(tf_context "${provider}")"
  ansible_fetch_kubeconfig "$(tf_inventory "${provider}")"
  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  kubeconfig_hint "${context}"
}
