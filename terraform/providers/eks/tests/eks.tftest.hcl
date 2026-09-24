# =============================================================================
#  Tests du code EKS, sans compte AWS : le provider AWS est simulé
#  (mock_provider). Ils vérifient la logique du code (réseau, droits, taille
#  du node group, cible LocalStack), pas le comportement réel d'AWS.
#
#    cd terraform/providers/eks && terraform init -backend=false && terraform test
# =============================================================================

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
      zone_ids = ["euw3-az1", "euw3-az2", "euw3-az3"]
    }
  }

  # Les valeurs simulées doivent avoir un format valide (vérifié par le provider).
  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/k8s-lab-mock"
    }
  }
}

variables {
  api_allowed_cidrs = ["203.0.113.10/32"]
}

run "default_lab" {
  assert {
    condition     = length(aws_subnet.public) == 2 && alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch])
    error_message = "Two public subnets expected, with public IPs for the workers."
  }

  assert {
    condition     = toset(keys(aws_subnet.public)) == toset(["eu-west-3a", "eu-west-3b"])
    error_message = "The subnets must use two different availability zones."
  }

  assert {
    condition     = contains(data.aws_availability_zones.available.exclude_zone_ids, "use1-az3")
    error_message = "Availability zones refused by EKS must be excluded."
  }

  assert {
    condition     = aws_vpc.lab.enable_dns_support && aws_vpc.lab.enable_dns_hostnames
    error_message = "EKS needs DNS support and DNS hostnames in the VPC."
  }

  assert {
    condition     = aws_eks_cluster.lab.version == "1.36" && aws_eks_node_group.workers.version == "1.36"
    error_message = "Control-plane and workers must use the default EKS version."
  }

  assert {
    condition     = aws_eks_cluster.lab.vpc_config[0].public_access_cidrs == toset(["203.0.113.10/32"])
    error_message = "The public API must only be open to api_allowed_cidrs."
  }

  assert {
    condition     = aws_eks_cluster.lab.vpc_config[0].endpoint_private_access
    error_message = "Workers reach the API through the private endpoint."
  }

  assert {
    condition     = aws_eks_cluster.lab.access_config[0].authentication_mode == "API" && aws_eks_cluster.lab.upgrade_policy[0].support_type == "STANDARD"
    error_message = "Unexpected access or upgrade policy."
  }

  assert {
    condition     = aws_eks_node_group.workers.scaling_config[0].desired_size == 2 && aws_eks_node_group.workers.scaling_config[0].min_size == 1 && aws_eks_node_group.workers.scaling_config[0].max_size == 4
    error_message = "The node group must have WORKER_COUNT (2) workers, between 1 and 4."
  }

  assert {
    condition     = aws_eks_node_group.workers.instance_types == tolist(["t3.medium"]) && aws_eks_node_group.workers.ami_type == "AL2023_x86_64_STANDARD"
    error_message = "Unexpected instance type or AMI type for the workers."
  }

  assert {
    condition = toset([for a in aws_iam_role_policy_attachment.node : a.policy_arn]) == toset([
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
      "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    ])
    error_message = "The workers must only get the three AWS policies recommended for EKS nodes."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.cluster.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    error_message = "The control-plane role must only get AmazonEKSClusterPolicy."
  }

  assert {
    condition     = toset(keys(aws_eks_addon.before_nodes)) == toset(["vpc-cni", "kube-proxy"]) && toset(keys(aws_eks_addon.after_nodes)) == toset(["coredns"])
    error_message = "vpc-cni and kube-proxy must be installed before the workers, coredns after."
  }

  assert {
    condition     = output.kubectl_command == "aws eks update-kubeconfig --region eu-west-3 --name k8s-lab --alias k8s-lab-eks"
    error_message = "Unexpected kubectl_command output: ${output.kubectl_command}"
  }
}

run "worker_count_drives_the_node_group" {
  variables {
    worker_count       = 3
    node_capacity_type = "SPOT"
  }

  assert {
    condition     = aws_eks_node_group.workers.scaling_config[0].desired_size == 3 && aws_eks_node_group.workers.scaling_config[0].max_size == 5
    error_message = "WORKER_COUNT=3 must give 3 workers (max 5)."
  }

  assert {
    condition     = aws_eks_node_group.workers.capacity_type == "SPOT"
    error_message = "node_capacity_type must reach the node group."
  }
}

run "localstack_target" {
  variables {
    aws_target = "localstack"
  }

  assert {
    condition     = length(aws_eks_addon.before_nodes) == 0 && length(aws_eks_addon.after_nodes) == 0
    error_message = "No EKS add-on on LocalStack (k3s already provides networking and DNS)."
  }

  assert {
    condition     = output.kubectl_command == "aws --endpoint-url http://localhost:4566 eks update-kubeconfig --region eu-west-3 --name k8s-lab --alias k8s-lab-eks"
    error_message = "The kubectl command must target LocalStack: ${output.kubectl_command}"
  }
}

run "rejects_zero_worker" {
  command = plan

  variables {
    worker_count = 0
  }

  expect_failures = [var.worker_count]
}

run "rejects_unknown_target" {
  command = plan

  variables {
    aws_target = "gcp"
  }

  expect_failures = [var.aws_target]
}

run "rejects_empty_api_access_list" {
  command = plan

  variables {
    api_allowed_cidrs = []
  }

  expect_failures = [var.api_allowed_cidrs]
}

run "rejects_too_long_cluster_name" {
  command = plan

  variables {
    cluster_name = "a-cluster-name-that-is-far-too-long"
  }

  expect_failures = [var.cluster_name]
}
