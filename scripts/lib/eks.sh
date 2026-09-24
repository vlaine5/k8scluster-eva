#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Mode terraform eks : Kubernetes managé par AWS (niveau 4, cloud).
#
#    terraform apply            -> VPC, IAM, cluster EKS, Managed Node Group
#    aws eks update-kubeconfig  -> contexte kubectl <cluster>-eks
#
#  Pas d'Ansible ni de kubeadm : AWS fournit et opère le control-plane.
#  AWS_TARGET=localstack envoie les mêmes appels vers LocalStack.
# =============================================================================

eks_context() { tf_context eks; }

# Valeur par défaut d'une variable Terraform du provider eks (lue dans variables.tf).
eks_tf_default() {
  awk -v var="$1" '
    $0 ~ "^variable \"" var "\" [{]" { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside && $1 == "default" { sub(/^[^=]*=[ \t]*/, ""); gsub(/"/, ""); print; exit }
  ' "$(tf_dir eks)/variables.tf"
}

# Valeur d'une variable simple de terraform.tfvars (vide si absente).
eks_tfvars_value() {
  local file
  file="$(tf_dir eks)/terraform.tfvars"
  [[ -f "${file}" ]] || return 0
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "${file}" | tail -n1
}

# Région utilisée par Terraform : terraform.tfvars, sinon AWS_REGION, sinon le défaut.
eks_region() {
  local region
  region="$(eks_tfvars_value aws_region)"
  echo "${region:-${AWS_REGION:-${AWS_DEFAULT_REGION:-$(eks_tf_default aws_region)}}}"
}

# Environnement AWS de la commande (hérité par terraform, aws et kubectl).
eks_prepare_env() {
  if [[ "${AWS_TARGET}" == "localstack" ]]; then
    # Adresse et identifiants factices de LocalStack : jamais utilisés pour AWS.
    export AWS_ENDPOINT_URL="${LOCALSTACK_ENDPOINT}"
    export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
    unset AWS_PROFILE AWS_SESSION_TOKEN
  else
    # Vrai AWS : aucune redirection vers un émulateur ne doit subsister.
    unset AWS_ENDPOINT_URL
  fi
}

# Adresse IP publique de ce poste (x.x.x.x), vide si inconnue.
eks_public_ip() {
  local ip
  ip="$(curl -fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')" || ip=""
  if [[ "${ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then echo "${ip}"; fi
}

# Réglages transmis à Terraform. L'API Kubernetes n'est ouverte qu'à votre
# adresse IP publique (api_allowed_cidrs de terraform.tfvars reste prioritaire).
#   eks_export_vars [--destroy]
eks_export_vars() {
  local ip
  eks_prepare_env
  if ((${#CLUSTER_NAME} > 25)); then
    die "CLUSTER_NAME=${CLUSTER_NAME} est trop long pour EKS (25 caractères au plus)." \
      "Les rôles IAM du lab sont préfixés par ce nom. Raccourcissez-le dans .env."
  fi
  export TF_VAR_cluster_name="${CLUSTER_NAME}"
  export TF_VAR_worker_count="${WORKER_COUNT}"
  export TF_VAR_kubernetes_version="${EKS_KUBERNETES_VERSION}"
  export TF_VAR_aws_target="${AWS_TARGET}"
  export TF_VAR_localstack_endpoint="${LOCALSTACK_ENDPOINT}"
  if [[ -n "${AWS_REGION:-${AWS_DEFAULT_REGION:-}}" ]]; then
    export TF_VAR_aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION}}"
  fi

  if [[ "${AWS_TARGET}" == "localstack" || "${1:-}" == "--destroy" ]]; then
    # LocalStack : API locale. Destruction : la valeur n'a plus d'effet.
    export TF_VAR_api_allowed_cidrs='["127.0.0.1/32"]'
    return 0
  fi
  ip="$(eks_public_ip)"
  if [[ -n "${ip}" ]]; then
    info "L'API Kubernetes du cluster ne sera accessible que depuis votre adresse IP publique : ${ip}"
    export TF_VAR_api_allowed_cidrs="[\"${ip}/32\"]"
  elif ! grep -Eq '^[[:space:]]*api_allowed_cidrs[[:space:]]*=' "$(tf_dir eks)/terraform.tfvars" 2>/dev/null; then
    die "Impossible de déterminer votre adresse IP publique (https://checkip.amazonaws.com)." \
      "L'API du cluster EKS n'est ouverte qu'à votre adresse, il faut donc la connaître." \
      "Indiquez-la dans terraform/providers/eks/terraform.tfvars : api_allowed_cidrs = [\"x.x.x.x/32\"]"
  fi
}

require_aws_cli() {
  have aws && return 0
  die "La commande aws (AWS CLI v2) est introuvable." \
    "kubectl l'utilise pour s'authentifier auprès d'EKS (aws eks get-token)." \
    "Installation : https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" \
    "Puis relancez : $(hint_cmd doctor terraform eks)"
}

# Écrit .kube/clusters/<contexte>.yaml avec la commande officielle d'AWS, puis
# l'ajoute à .kube/config. Le jeton d'accès est demandé à AWS par kubectl à
# chaque commande (aws eks get-token) : aucun secret n'est stocké.
eks_write_kubeconfig() {
  local context file region name
  context="$(eks_context)"
  file="${LAB_KUBE_DIR}/clusters/${context}.yaml"
  require_aws_cli
  eks_prepare_env
  region="$(tf_output eks aws_region)" || region=""
  name="$(tf_output eks cluster_name)" || name=""
  if [[ -z "${region}" || -z "${name}" ]]; then
    die "Aucun cluster EKS dans le state Terraform." "Déployez-le d'abord : $(hint_cmd deploy terraform eks)"
  fi

  step "kubeconfig du cluster EKS \"${name}\" (contexte ${context})"
  ensure_state_dirs
  mkdir -p "${LAB_KUBE_DIR}/clusters"
  rm -f "${file}"
  run aws eks update-kubeconfig --region "${region}" --name "${name}" \
    --alias "${context}" --user-alias "${context}-admin" --kubeconfig "${file}" ||
    die "aws eks update-kubeconfig a échoué." \
      "Vérifiez vos identifiants : aws sts get-caller-identity" \
      "Ce sont ceux qui ont créé le cluster qui en sont administrateurs."
  chmod 600 "${file}"
  if [[ "${AWS_TARGET}" == "localstack" ]]; then
    # kubectl appelle "aws eks get-token" : avec LocalStack, les identifiants factices suffisent.
    kubectl --kubeconfig "${file}" config set-credentials "${context}-admin" \
      --exec-env=AWS_ACCESS_KEY_ID=test --exec-env=AWS_SECRET_ACCESS_KEY=test >/dev/null
  fi
  kubeconfig_merge "${file}" "${context}"
}

# Les Services de type LoadBalancer créent des load balancers AWS que Terraform
# ne connaît pas : ils bloqueraient la suppression du VPC (et resteraient facturés).
eks_check_no_load_balancer() {
  local context services
  context="$(eks_context)"
  if ! have kubectl || [[ ! -s "${LAB_KUBECONFIG}" ]]; then
    return 0
  fi
  services="$(kubectl --kubeconfig "${LAB_KUBECONFIG}" --context "${context}" --request-timeout=15s \
    get services --all-namespaces \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null)" || {
    info "Cluster injoignable avec kubectl : vérification des Services LoadBalancer ignorée."
    return 0
  }
  [[ -n "${services}" ]] || return 0
  die "Des Services de type LoadBalancer existent encore dans le cluster :" \
    "${services//$'\n'/ }" \
    "AWS a créé un load balancer pour chacun ; Terraform ne les connaît pas." \
    "Supprimez-les d'abord (kubectl delete service -n <namespace> <nom>), puis relancez : $(hint_cmd destroy terraform eks)"
}
