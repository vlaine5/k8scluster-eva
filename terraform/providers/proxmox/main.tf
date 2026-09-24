# =============================================================================
#  Cluster Kubernetes sur Proxmox VE : création des VMs uniquement.
#  Kubernetes est ensuite installé par Ansible (ansible/site.yml) grâce à
#  l'inventaire généré à la fin de ce fichier.
# =============================================================================

locals {
  context_name   = "${var.cluster_name}-proxmox"
  inventory_path = coalesce(var.inventory_path, abspath("${path.root}/../../../ansible/inventories/terraform-proxmox.ini"))
  use_template   = var.template_vm_id != null
}

# 1. Description des nœuds (noms, IP, cloud-init) : commune à tous les providers.
module "nodes" {
  source = "../../modules/k8s-nodes"

  hostname_prefix = var.hostname_prefix
  worker_count    = var.worker_count
  network_cidr    = var.network_cidr
  ip_start        = var.ip_start
  gateway         = var.gateway
  dns_servers     = var.dns_servers
  ssh_user        = var.ssh_user
  ssh_public_key  = var.ssh_public_key
}

# 2. Image cloud Ubuntu téléchargée PAR le serveur Proxmox (checksum vérifié).
#    Ignorée si vous clonez un template existant (template_vm_id).
resource "proxmox_download_file" "image" {
  count = local.use_template ? 0 : 1

  node_name          = var.proxmox_node
  datastore_id       = var.image_datastore
  content_type       = "import"
  url                = var.image_url
  checksum           = var.image_sha256
  checksum_algorithm = "sha256"
  # Le type "import" exige l'extension du format réel de l'image (qcow2).
  file_name = "${var.cluster_name}-${trimsuffix(basename(var.image_url), ".img")}.qcow2"
  overwrite = false
}

# 3. Une VM par nœud.
resource "proxmox_virtual_environment_vm" "node" {
  for_each = module.nodes.nodes

  name        = each.key
  description = "Kubernetes ${each.value.role} of ${local.context_name} - managed by Terraform (k8s-lab)"
  tags        = distinct(concat(var.tags, [var.cluster_name, replace(each.value.role, "_", "-")]))
  node_name   = var.proxmox_node
  vm_id       = var.vm_id_start == null ? null : var.vm_id_start + each.value.index

  # Sans agent QEMU dans l'image, Proxmox ne peut pas éteindre proprement la VM :
  # on force l'arrêt à la destruction.
  agent {
    enabled = false
  }
  stop_on_destroy = true

  dynamic "clone" {
    for_each = local.use_template ? [var.template_vm_id] : []
    content {
      vm_id     = clone.value
      node_name = coalesce(var.template_node, var.proxmox_node)
      full      = true
    }
  }

  cpu {
    cores = var.node_cpus
    type  = var.cpu_type
  }

  memory {
    dedicated = var.node_memory_mb
  }

  operating_system {
    type = "l26"
  }

  # Les images cloud Ubuntu écrivent leur console sur le port série.
  serial_device {}

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    import_from  = local.use_template ? null : proxmox_download_file.image[0].id
    size         = var.node_disk_gb
    discard      = "on"
  }

  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_id
  }

  # cloud-init natif de Proxmox : IP statique + utilisateur + clé SSH.
  initialization {
    datastore_id = coalesce(var.cloud_init_datastore, var.vm_datastore)

    ip_config {
      ipv4 {
        address = each.value.address
        gateway = module.nodes.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.ssh_user
      keys     = [trimspace(var.ssh_public_key)]
    }
  }
}

# 4. Inventaire Ansible généré automatiquement (pont Terraform -> Ansible).
module "inventory" {
  source = "../../modules/ansible-inventory"

  inventory_path       = local.inventory_path
  cluster_name         = local.context_name
  nodes                = module.nodes.nodes
  ssh_user             = var.ssh_user
  ssh_private_key_file = var.ssh_private_key_file
  generated_by         = "terraform/providers/proxmox"

  # L'inventaire n'est écrit qu'une fois les VMs créées.
  depends_on = [proxmox_virtual_environment_vm.node]
}
