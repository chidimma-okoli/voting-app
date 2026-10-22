output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.voting.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.voting.endpoint
}

output "cluster_region" {
  description = "AWS region hosting the cluster"
  value       = var.aws_region
}

output "node_group_name" {
  description = "Name of the EKS managed node group"
  value       = aws_eks_node_group.voting.node_group_name
}
