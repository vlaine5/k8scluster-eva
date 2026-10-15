# =============================================================================
#  Cluster Kubernetes sur Proxmox VE : création des VMs uniquement.
#  Kubernetes est ensuite installé par Ansible (ansible/site.yml) grâce à
#  l'inventaire généré à la fin de ce fichier.
#
#  - 1, 3 ou 5 control-planes (HA) + workers, IP statiques (cloud-init)
#  - image cloud de l'OS choisi (NODE_OS / NODE_OS_VERSION : catalogue
#    config/versions.yaml), téléchargée PAR Proxmox avec vérification SHA-256,
#    ou clone d'un template existant (template_vm_id)
#  - répartition possible sur plusieurs nœuds Proxmox (proxmox_nodes)
#  - disque Longhorn dédié (scsi1, numéro de série k8slab-longhorn) sur les
#    nœuds de stockage si longhorn_disk_gb > 0 : jamais formaté par Terraform
# =============================================================================

locals {
  context_name   = "${var.cluster_name}-proxmox"
  inventory_path = coalesce(var.inventory_path, abspath("${path.root}/../../../ansible/inventories/terraform-proxmox.ini"))
  use_template   = var.template_vm_id != null

  # Placement : nœuds Proxmox utilisés à tour de rôle (control-planes d'abord).
  hypervisors = length(var.proxmox_nodes) > 0 ? var.proxmox_nodes : [var.proxmox_node]
  placement   = { for name, node in module.nodes.nodes : name => local.hypervisors[node.index % length(local.hypervisors)] }

  # Le type "import" exige l'extension du format réel de l'image (qcow2).
  image_file_name = "${var.cluster_name}-${var.node_os}-${replace(var.node_os_version, ".", "")}-${trimsuffix(trimsuffix(basename(var.image_url), ".img"), ".qcow2")}.qcow2"
}

# 1. Description des nœuds (noms, IP, cloud-init) : commune à tous les providers.
module "nodes" {
  source = "../../modules/k8s-nodes"

  hostname_prefix     = var.hostname_prefix
  control_plane_count = var.control_plane_count
  worker_count        = var.worker_count
  network_cidr        = var.network_cidr
  node_ip_cidr        = var.node_ip_cidr
  ip_start            = var.ip_start
  worker_ip_offset    = var.worker_ip_offset
  gateway             = var.gateway
  dns_servers         = var.dns_servers
  ssh_user            = var.ssh_user
  os_family           = var.os_family
  ssh_public_key      = var.ssh_public_key
  longhorn_disk_gb    = var.longhorn_disk_gb
}

# 2. Image cloud téléchargée PAR chaque serveur Proxmox utilisé (checksum vérifié).
#    Ignorée si vous clonez un template existant (template_vm_id).
resource "proxmox_download_file" "image" {
  for_each = local.use_template ? toset([]) : toset(local.hypervisors)

  node_name          = each.value
  datastore_id       = var.image_datastore
  content_type       = "import"
  url                = var.image_url
  checksum           = var.image_sha256
  checksum_algorithm = "sha256"
  file_name          = local.image_file_name
  overwrite          = false
}

# 3. Une VM par nœud.
resource "proxmox_virtual_environment_vm" "node" {
  for_each = module.nodes.nodes

  name        = each.key
  description = "Kubernetes ${each.value.role} of ${local.context_name} (${var.node_os} ${var.node_os_version}) - managed by Terraform (k8s-lab)"
  tags        = distinct(concat(var.tags, [var.cluster_name, replace(each.value.role, "_", "-"), var.node_os]))
  node_name   = local.placement[each.key]
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

  # Les images cloud écrivent leur console sur le port série.
  serial_device {}

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    import_from  = local.use_template ? null : proxmox_download_file.image[local.placement[each.key]].id
    size         = var.node_disk_gb
    discard      = "on"
  }

  # Disque Longhorn dédié : vierge, identifié par son numéro de série. Le rôle Ansible
  # storage_disk ne le formate que s'il est vide (jamais un disque contenant des données).
  dynamic "disk" {
    for_each = each.value.longhorn_disk ? [1] : []
    content {
      datastore_id = coalesce(var.longhorn_datastore, var.vm_datastore)
      interface    = "scsi1"
      size         = var.longhorn_disk_gb
      discard      = "on"
      file_format  = "raw"
      serial       = module.nodes.longhorn_disk_serial
    }
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

  lifecycle {
    # Une nouvelle image (config/versions.yaml) ne doit jamais recréer les VMs existantes :
    # seules les nouvelles VMs l'utilisent. Mise à jour de l'OS : make os-update.
    ignore_changes = [disk[0].import_from, clone]
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
