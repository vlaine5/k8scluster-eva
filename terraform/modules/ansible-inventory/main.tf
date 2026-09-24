# =============================================================================
#  Module ansible-inventory : écrit l'inventaire Ansible à partir des nœuds
#  créés par Terraform. C'est le "pont" Terraform -> Ansible : l'étudiant n'a
#  jamais à recopier d'IP à la main.
# =============================================================================

locals {
  control_plane = [for name in sort(keys(var.nodes)) : var.nodes[name] if var.nodes[name].role == "control_plane"]
  # Tri naturel : worker-2 avant worker-10.
  workers = [
    for n in sort([for name, node in var.nodes : format("%05d|%s", try(tonumber(regex("-([0-9]+)$", name)[0]), 0), name) if node.role == "worker"]) :
    var.nodes[split("|", n)[1]]
  ]
}

resource "local_file" "inventory" {
  filename        = var.inventory_path
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    generated_by         = var.generated_by
    cluster_name         = var.cluster_name
    control_plane        = local.control_plane
    workers              = local.workers
    ssh_user             = var.ssh_user
    ssh_private_key_file = var.ssh_private_key_file
  })
}
