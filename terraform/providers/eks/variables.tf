# =============================================================================
#  Variables communes (fournies par ./k8s-lab depuis config/lab.env via
#  TF_VAR_*). Les valeurs par défaut sont identiques à celles de lab.env.
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster (the kubectl context is <cluster_name>-eks)."
  type        = string
  default     = "k8s-lab"

  validation {
    # 25 caractères au plus : les rôles IAM sont préfixés par ce nom (38 max).
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,24}$", var.cluster_name))
    error_message = "cluster_name: 1 to 25 letters, digits or dashes, starting with a letter."
  }
}

variable "worker_count" {
  description = "Number of worker nodes wanted in the managed node group (desired size)."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "worker_count: EKS needs at least 1 worker (CoreDNS runs on the workers); the lab allows up to 10."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS control-plane. It must be offered by EKS (see docs/deploy-eks.md): it can differ from the version installed by kubeadm."
  type        = string
  default     = "1.36"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version: use a minor version such as \"1.36\"."
  }
}

# =============================================================================
#  Variables propres à EKS (terraform.tfvars ; valeurs par défaut adaptées à un
#  lab). Le réseau et les droits sont volontairement simples : voir main.tf.
# =============================================================================

variable "aws_region" {
  description = "AWS region of the cluster (./k8s-lab passes AWS_REGION when terraform.tfvars does not set it)."
  type        = string
  default     = "eu-west-3"
}

variable "node_instance_types" {
  description = "EC2 instance types of the workers (x86_64 types, e.g. t3.medium)."
  type        = list(string)
  default     = ["t3.medium"]

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types: give at least one instance type."
  }
}

variable "node_capacity_type" {
  description = "ON_DEMAND (default) or SPOT (cheaper, but AWS can reclaim the instances)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type: ON_DEMAND or SPOT."
  }
}

variable "api_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the public Kubernetes API endpoint. ./k8s-lab passes your public IP (x.x.x.x/32)."
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && alltrue([for c in var.api_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "api_allowed_cidrs: give at least one valid IPv4 CIDR block, e.g. [\"203.0.113.10/32\"]."
  }
}

variable "vpc_cidr" {
  description = "IPv4 range of the VPC created for the lab (two public subnets are carved from it)."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr: give a valid IPv4 CIDR block."
  }
}

# =============================================================================
#  Cible : AWS réel (défaut) ou LocalStack (émulateur local, voir providers.tf)
# =============================================================================

variable "aws_target" {
  description = "aws (real AWS, default) or localstack (local emulator)."
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "localstack"], var.aws_target)
    error_message = "aws_target: aws or localstack."
  }
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint, used only when aws_target = \"localstack\"."
  type        = string
  default     = "http://localhost:4566"
}
