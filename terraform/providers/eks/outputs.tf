output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.lab.name
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API (public access limited to api_allowed_cidrs)."
  value       = aws_eks_cluster.lab.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the control-plane."
  value       = aws_eks_cluster.lab.version
}

output "aws_region" {
  description = "AWS region of the cluster."
  value       = var.aws_region
}

output "node_group_name" {
  description = "Name of the managed node group (the workers)."
  value       = aws_eks_node_group.workers.node_group_name
}

output "kubectl_command" {
  description = "Command that configures kubectl for this cluster (./k8s-lab runs it with --kubeconfig .kube/clusters/<context>.yaml)."
  value = join(" ", compact([
    "aws",
    local.localstack ? "--endpoint-url ${var.localstack_endpoint}" : "",
    "eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.lab.name} --alias ${local.context_name}",
  ]))
}
