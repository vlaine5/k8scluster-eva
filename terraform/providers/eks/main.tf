# =============================================================================
#  AWS EKS : Kubernetes managé dans le cloud.
#
#    VPC (2 sous-réseaux publics dans 2 zones) + rôles IAM
#      -> cluster EKS (control-plane opéré par AWS)
#      -> addons vpc-cni et kube-proxy
#      -> Managed Node Group (les workers, des instances EC2 gérées par EKS)
#      -> addon coredns (il lui faut des workers pour démarrer)
#
#  À comparer avec terraform/providers/proxmox|vsphere|libvirt : ici, pas de
#  VM à installer, ni d'Ansible, ni de kubeadm. AWS fournit le control-plane.
# =============================================================================

locals {
  context_name = "${var.cluster_name}-eks"

  # Deux zones suffisent (minimum exigé par EKS) : le lab reste simple.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Addons EKS gérés : le réseau des Pods (vpc-cni) et kube-proxy doivent exister
  # avant les workers ; CoreDNS a besoin de workers pour démarrer.
  # LocalStack (k3s) fournit déjà réseau et DNS : ces addons ne sont créés que sur AWS.
  addons_before_nodes = local.localstack ? [] : ["vpc-cni", "kube-proxy"]
  addons_after_nodes  = local.localstack ? [] : ["coredns"]
}

# Zones de disponibilité classiques de la région, sans celles qu'EKS refuse
# pour le control-plane (documentation AWS : exigences réseau d'EKS).
data "aws_availability_zones" "available" {
  state            = "available"
  exclude_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# -----------------------------------------------------------------------------
#  Réseau : un VPC, deux sous-réseaux publics, une passerelle Internet.
#  Pas de NAT ni de sous-réseau privé : c'est le modèle « sous-réseaux publics
#  uniquement » documenté par AWS, suffisant (et moins cher) pour un lab. Les
#  workers ont une IP publique mais aucun port ouvert depuis Internet : le
#  groupe de sécurité créé par EKS n'accepte que le trafic interne au cluster.
# -----------------------------------------------------------------------------

resource "aws_vpc" "lab" {
  cidr_block = var.vpc_cidr

  # Obligatoire pour EKS : sans DNS, les workers ne peuvent pas s'enregistrer.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.context_name
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = local.context_name
  }
}

resource "aws_subnet" "public" {
  for_each = { for index, az in local.azs : az => index }

  vpc_id            = aws_vpc.lab.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, each.value)

  # Exigé par les Managed Node Groups placés dans des sous-réseaux publics.
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.context_name}-public-${each.key}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  # Sortie vers Internet (images de conteneurs, API AWS) par la passerelle.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${local.context_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
#  IAM : un rôle pour le control-plane, un rôle pour les workers, avec
#  uniquement les politiques gérées recommandées par AWS.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name_prefix = "${var.cluster_name}-eks-cluster-"
  description = "EKS control-plane of the ${var.cluster_name} lab"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  name_prefix = "${var.cluster_name}-eks-node-"
  description = "EKS workers of the ${var.cluster_name} lab"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",          # le kubelet décrit les ressources EC2 du VPC
    "AmazonEC2ContainerRegistryPullOnly", # images des addons (Amazon ECR), en lecture seule
    "AmazonEKS_CNI_Policy",               # vpc-cni attribue les IP des Pods
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

# -----------------------------------------------------------------------------
#  Le cluster EKS : AWS crée et opère le control-plane (API server, etcd,
#  scheduler, controller-manager). L'API est publique mais filtrée par
#  api_allowed_cidrs ; les workers la joignent par le point d'accès privé.
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "lab" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Aucun addon installé « en douce » : Terraform les déclare plus bas.
  bootstrap_self_managed_addons = false

  # Droits d'accès gérés par l'API EKS ; l'identité AWS qui crée le cluster
  # en devient administratrice (c'est elle qu'utilisera kubectl).
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.public : subnet.id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.api_allowed_cidrs
  }

  # En fin de support standard, AWS met le cluster à jour au lieu de passer en
  # support étendu (facturé en plus).
  upgrade_policy {
    support_type = "STANDARD"
  }

  # Les droits IAM doivent exister avant le cluster et disparaître après lui,
  # sinon EKS ne peut pas nettoyer ce qu'il a créé (groupes de sécurité...).
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Version d'addon recommandée par AWS pour la version de Kubernetes du cluster
# (rien n'est figé en dur : elle suit les recommandations d'AWS).
data "aws_eks_addon_version" "recommended" {
  for_each = toset(concat(local.addons_before_nodes, local.addons_after_nodes))

  addon_name         = each.value
  kubernetes_version = aws_eks_cluster.lab.version
}

resource "aws_eks_addon" "before_nodes" {
  for_each = toset(local.addons_before_nodes)

  cluster_name  = aws_eks_cluster.lab.name
  addon_name    = each.value
  addon_version = data.aws_eks_addon_version.recommended[each.value].version
}

# -----------------------------------------------------------------------------
#  Les workers : un Managed Node Group. EKS crée, met à jour et remplace les
#  instances EC2 (image Amazon Linux 2023 optimisée pour EKS).
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.lab.name
  node_group_name = "${var.cluster_name}-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for subnet in aws_subnet.public : subnet.id]
  version         = aws_eks_cluster.lab.version

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type

  # WORKER_COUNT workers ; de la marge pour en ajouter à la main.
  scaling_config {
    desired_size = var.worker_count
    min_size     = 1
    max_size     = var.worker_count + 2
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_nodes,
    aws_route_table_association.public,
  ]
}

resource "aws_eks_addon" "after_nodes" {
  for_each = toset(local.addons_after_nodes)

  cluster_name  = aws_eks_cluster.lab.name
  addon_name    = each.value
  addon_version = data.aws_eks_addon_version.recommended[each.value].version

  depends_on = [aws_eks_node_group.workers]
}
