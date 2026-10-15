#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode terraform : l'infrastructure est décrite en code (Terraform).
#
#  proxmox, vsphere, libvirt (niveau 3) : Terraform crée des VMs, Ansible y
#  installe Kubernetes avec kubeadm.
#    terraform plan/apply  -> VMs + ansible/inventories/terraform-<provider>.ini
#    ansible-playbook      -> kubeadm init / join, CNI, vérifications
#
#  eks (niveau 4) : Terraform crée un cluster AWS EKS, Kubernetes managé.
#  Ni Ansible ni kubeadm : voir scripts/lib/eks.sh.
# =============================================================================

TERRAFORM_PROVIDERS="proxmox, vsphere, libvirt, eks"

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
    proxmox | vsphere | libvirt | eks) ;;
    "") die "Précisez le provider Terraform." "Exemple : $(hint_cmd deploy terraform proxmox)" "Providers : ${TERRAFORM_PROVIDERS}" ;;
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

# Valeur d'un output Terraform (sans affichage de la commande).
tf_output() {
  "$(terraform_bin)" -chdir="$(tf_dir "$1")" output -raw "$2" 2>/dev/null
}

# Réglages résolus (scripts/labctl) transmis à Terraform (variables TF_VAR_*).
# Les réglages propres à l'infrastructure restent dans terraform.tfvars.
tf_export_vars() {
  local provider="$1"
  if [[ "${provider}" == "eks" ]]; then
    eks_export_vars "${2:-}"
    return 0
  fi
  ensure_ssh_key
  export TF_VAR_cluster_name="${CLUSTER_NAME}"
  export TF_VAR_control_plane_count="${LAB_R_CP_COUNT:-${CONTROL_PLANE_COUNT}}"
  export TF_VAR_worker_count="${LAB_R_WORKER_COUNT:-${WORKER_COUNT}}"
  export TF_VAR_hostname_prefix="${NODE_HOSTNAME_PREFIX}"
  export TF_VAR_node_cpus="${NODE_CPUS}"
  export TF_VAR_node_memory_mb="${NODE_MEMORY_MB}"
  export TF_VAR_node_disk_gb="${NODE_DISK_GB}"
  export TF_VAR_ssh_user="${LAB_R_SSH_USER:-ubuntu}"
  export TF_VAR_os_family="${LAB_R_OS_FAMILY:-debian}"
  export TF_VAR_ssh_private_key_file="${SSH_PRIVATE_KEY_FILE}"
  TF_VAR_ssh_public_key="$(cat "${SSH_PRIVATE_KEY_FILE}.pub")"
  export TF_VAR_ssh_public_key
  # Disque Longhorn dédié (LONGHORN_DEDICATED_DISK=true et Longhorn dans le plan).
  if [[ "${LAB_R_LONGHORN_DISK:-false}" == true ]]; then
    export TF_VAR_longhorn_disk_gb="${LONGHORN_DISK_SIZE_GB}"
    [[ -z "${LONGHORN_DISK_DATASTORE:-}" ]] || export TF_VAR_longhorn_datastore="${LONGHORN_DISK_DATASTORE}"
  else
    export TF_VAR_longhorn_disk_gb=0
  fi
  case "${provider}" in
    proxmox)
      export TF_VAR_node_os="${LAB_R_OS_NAME}" TF_VAR_node_os_version="${LAB_R_OS_VERSION}"
      export TF_VAR_cpu_type="${NODE_CPU_TYPE}"
      if [[ "${LAB_R_IMAGE_SOURCE}" == template ]]; then
        export TF_VAR_template_vm_id="${LAB_R_TEMPLATE}"
      else
        export TF_VAR_image_url="${LAB_R_IMAGE_URL}" TF_VAR_image_sha256="${LAB_R_IMAGE_SHA256}"
      fi
      ;;
    vsphere)
      [[ -z "${LAB_R_TEMPLATE:-}" ]] || export TF_VAR_vsphere_template="${LAB_R_TEMPLATE}"
      ;;
    libvirt)
      export TF_VAR_node_os="${LAB_R_OS_NAME}" TF_VAR_node_os_version="${LAB_R_OS_VERSION}"
      tf_libvirt_prepare_image
      ;;
  esac
}

# libvirt : l'image est téléchargée une seule fois dans .lab/cache/ et son
# SHA-256 est vérifié AVANT d'être confiée à Terraform.
tf_libvirt_prepare_image() {
  local cache="${LAB_STATE_DIR}/cache/images" file sum url="${LAB_R_IMAGE_URL}" expected="${LAB_R_IMAGE_SHA256}"
  file="${cache}/$(basename "${url}")"
  mkdir -p "${cache}"
  if [[ ! -f "${file}" ]]; then
    step "Téléchargement de l'image ${LAB_R_OS_NAME} ${LAB_R_OS_VERSION} (une seule fois) : ${url}"
    run curl -fL --progress-bar -o "${file}.part" "${url}" ||
      die "Téléchargement impossible : ${url}" "Vérifiez votre connexion Internet."
    mv "${file}.part" "${file}"
  fi
  if have sha256sum; then
    sum="$(sha256sum "${file}" | awk '{print $1}')"
  else
    sum="$(shasum -a 256 "${file}" | awk '{print $1}')"
  fi
  if [[ "${sum}" != "${expected}" ]]; then
    rm -f "${file}"
    die "Empreinte SHA-256 incorrecte pour $(basename "${file}") : fichier supprimé." \
      "Attendu : ${expected}" "Obtenu  : ${sum}" \
      "Image personnalisée : NODE_IMAGE_URL et NODE_IMAGE_SHA256 doivent correspondre (fichier SHA256SUMS de la release)."
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

# Affiche le vrai plan d'infrastructure, avec EXACTEMENT les memes variables
# (.env + terraform.tfvars) que deploy. Ne lance JAMAIS terraform apply.
# Accessible aux debutants via : make plan MODE=terraform PROVIDER=proxmox
terraform_plan() {
  local provider="$1"
  tf_check_provider "${provider}"
  require_doctor terraform "${provider}"
  tf_export_vars "${provider}"

  step "Terraform : initialisation (aucune VM creee)"
  (cd "${LAB_ROOT}" && tf "${provider}" init -input=false) ||
    die "terraform init a echoue."

  step "Terraform : apercu des modifications, sans application"
  (cd "${LAB_ROOT}" && tf "${provider}" plan -input=false) ||
    die "terraform plan a echoue. Verifiez .env et terraform.tfvars."

  ok "Plan affiche : aucune VM creee ou modifiee. Pour deployer, utilisez make deploy."
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
  if [[ "${provider}" == "eks" && "${AWS_TARGET}" == "aws" ]]; then
    warn "AWS EKS utilise de vraies ressources payantes (cluster, instances EC2)."
    warn "Quand le TP est terminé : $(hint_cmd destroy terraform eks)"
  fi

  step "Terraform : initialisation (téléchargement des providers)"
  (cd "${LAB_ROOT}" && tf "${provider}" init -input=false) ||
    die "terraform init a échoué." "Vérifiez votre accès à registry.terraform.io."

  step "Terraform : calcul du plan (ce qui va être créé / modifié / détruit)"
  # Un plan peut contenir des valeurs sensibles : fichier privé, supprimé après usage.
  (umask 077 && cd "${LAB_ROOT}" && tf "${provider}" plan -input=false -out="${plan}") ||
    die "terraform plan a échoué (voir l'erreur ci-dessus)." \
      "Vérifiez terraform/providers/${provider}/terraform.tfvars et vos identifiants (.env, ou aws configure pour EKS)."

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

  if [[ "${provider}" == "eks" ]]; then
    # Kubernetes managé : AWS a déjà installé le control-plane, pas d'Ansible.
    eks_write_kubeconfig
  else
    ansible_install_kubernetes "$(tf_inventory "${provider}")"
    kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  fi
  post_deploy "${context}"
  if [[ "${provider}" == "eks" ]]; then
    printf '\nInformations du cluster : %s -chdir=terraform/providers/eks output\n' "$(terraform_bin)"
    [[ "${AWS_TARGET}" == "aws" ]] && warn "Le cluster EKS est facturé tant qu'il existe. Fin du TP : $(hint_cmd destroy terraform eks)"
  else
    printf '\nAdresses et commandes SSH : %s -chdir=terraform/providers/%s output\n' "$(terraform_bin)" "${provider}"
  fi
}

terraform_destroy() {
  local provider="$1" context
  tf_check_provider "${provider}"
  context="$(tf_context "${provider}")"
  if ! tf_has_resources "${provider}"; then
    info "Aucune ressource Terraform ${provider} dans le state : rien à détruire."
  else
    [[ -n "$(terraform_bin)" ]] || die "Terraform (ou OpenTofu) est introuvable." "Diagnostic : $(hint_cmd doctor terraform "${provider}")"
    if [[ "${provider}" == "eks" ]]; then
      eks_prepare_env
      eks_check_no_load_balancer
      confirm "Détruire le cluster EKS du lab et toutes ses ressources AWS (terraform destroy) ?" || die "Destruction annulée."
      tf_export_vars "${provider}" --destroy
    else
      confirm "Détruire TOUTES les VMs Terraform ${provider} du lab (terraform destroy) ?" || die "Destruction annulée."
      known_hosts_forget "$(tf_inventory "${provider}")"
      tf_export_vars "${provider}"
    fi
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
  # Lecture du state local uniquement : rapide, sans appel à AWS.
  if tf_has_resources eks; then
    status_line up "tf eks" "cluster EKS déployé (contexte $(tf_context eks)), facturé tant qu'il existe"
  else
    status_line none "tf eks" "aucun cluster"
  fi
}

terraform_kubeconfig() {
  local provider="$1" context
  tf_check_provider "${provider}"
  context="$(tf_context "${provider}")"
  if [[ "${provider}" == "eks" ]]; then
    eks_write_kubeconfig
    kubeconfig_hint "${context}"
    return 0
  fi
  ansible_fetch_kubeconfig "$(tf_inventory "${provider}")"
  kubeconfig_merge "${LAB_KUBE_DIR}/clusters/${context}.yaml" "${context}"
  kubeconfig_hint "${context}"
}
