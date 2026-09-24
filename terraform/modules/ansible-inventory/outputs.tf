output "path" {
  description = "Path of the generated Ansible inventory."
  value       = local_file.inventory.filename
}

output "content" {
  description = "Content of the generated Ansible inventory (no secret inside)."
  value       = local_file.inventory.content
}
