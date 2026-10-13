# =============================================================================
#  Cluster Kubernetes sur KVM/libvirt (votre propre machine Linux).
#
#  Terraform crée : un pool de stockage, un réseau NAT, l'image de base de
#  l'OS choisi (Ubuntu, Debian, Rocky ; téléchargée et vérifiée par ./k8s-lab),
#  puis pour chaque nœud un disque (copy-on-write sur l'image de base), un
#  disque cloud-init, un disque Longhorn dédié optionnel et la VM.
#  Kubernetes est ensuite installé par Ansible grâce à l'inventaire généré.
# =============================================================================

locals {
  context_name   = "${var.cluster_name}-libvirt"
  inventory_path = coalesce(var.inventory_path, abspath("${path.root}/../../../ansible/inventories/terraform-libvirt.ini"))
  prefix_length  = tonumber(split("/", var.network_cidr)[1])
  # libvirt (dnsmasq) écoute sur la 1re adresse du réseau : passerelle + DNS.
  gateway = cidrhost(var.network_cidr, 1)
}

# 1. Description des nœuds (noms, IP, cloud-init) : commune à tous les providers.
module "nodes" {
  source = "../../modules/k8s-nodes"

  hostname_prefix     = var.hostname_prefix
  control_plane_count = var.control_plane_count
  worker_count        = var.worker_count
  network_cidr        = var.network_cidr
  ip_start            = var.ip_start
  worker_ip_offset    = var.worker_ip_offset
  gateway             = local.gateway
  dns_servers         = [local.gateway]
  ssh_user            = var.ssh_user
  os_family           = var.os_family
  ssh_public_key      = var.ssh_public_key
  longhorn_disk_gb    = var.longhorn_disk_gb
}

# 2. Pool de stockage dédié au lab.
resource "libvirt_pool" "lab" {
  name = "${var.cluster_name}-pool"
  type = "dir"
  target = {
    path = var.storage_pool_path
  }
  create = {
    build     = true
    start     = true
    autostart = true
  }
}

# 3. Réseau NAT dédié : les VMs sortent sur Internet via l'hôte et sont
#    joignables depuis l'hôte. Le DHCP n'est utilisé par personne (IP statiques)
#    mais reste disponible sur la seconde moitié du réseau.
resource "libvirt_network" "lab" {
  name      = "${var.cluster_name}-net"
  autostart = true

  forward = {
    mode = "nat"
  }

  domain = {
    name = "${var.cluster_name}.lab"
  }

  ips = [{
    address = local.gateway
    prefix  = local.prefix_length
    dhcp = {
      ranges = [{
        start = cidrhost(var.network_cidr, pow(2, 32 - local.prefix_length) / 2)
        end   = cidrhost(var.network_cidr, -2)
      }]
    }
  }]
}

# 4. Image de base de l'OS (lecture seule, partagée par tous les nœuds).
resource "libvirt_volume" "base" {
  name = "${var.cluster_name}-${var.node_os}-${replace(var.node_os_version, ".", "")}-base.qcow2"
  pool = libvirt_pool.lab.name
  target = {
    format = {
      type = "qcow2"
    }
  }
  create = {
    content = {
      url = var.image_source
    }
  }

  lifecycle {
    # Les disques des nœuds sont des « overlays » de cette image : la remplacer (nouvelle
    # image datée dans config/versions.yaml, ancien nom de fichier) recréerait TOUTES les
    # VMs. Elle reste donc celle de la création du cluster ; mises à jour : make os-update.
    ignore_changes = [name, create]
  }
}

# 5. Disque système de chaque nœud : "overlay" copy-on-write sur l'image de base.
resource "libvirt_volume" "root" {
  for_each = module.nodes.nodes

  name          = "${each.key}.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = var.node_disk_gb
  capacity_unit = "GiB"
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    path = libvirt_volume.base.path
    format = {
      type = "qcow2"
    }
  }

  lifecycle {
    # Un disque existant n'est jamais recréé à cause de son image de base.
    ignore_changes = [backing_store]
  }
}

# 5 bis. Disque Longhorn dédié (vierge) des nœuds de stockage, avec un numéro de série
#        que le rôle Ansible storage_disk reconnaît (il ne formate qu'un disque vide).
resource "libvirt_volume" "longhorn" {
  for_each = { for name, node in module.nodes.nodes : name => node if node.longhorn_disk }

  name          = "${each.key}-longhorn.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = var.longhorn_disk_gb
  capacity_unit = "GiB"
  target = {
    format = {
      type = "qcow2"
    }
  }
}

# 6. Disque cloud-init (ISO "cidata") de chaque nœud.
resource "libvirt_cloudinit_disk" "node" {
  for_each = module.nodes.nodes

  name           = "${each.key}-cloudinit"
  user_data      = module.nodes.cloud_init[each.key].user_data
  meta_data      = module.nodes.cloud_init[each.key].meta_data
  network_config = module.nodes.cloud_init[each.key].network_config
}

resource "libvirt_volume" "cloudinit" {
  for_each = module.nodes.nodes

  name = "${each.key}-cloudinit.iso"
  pool = libvirt_pool.lab.name
  target = {
    format = {
      type = "raw"
    }
  }
  create = {
    content = {
      url = libvirt_cloudinit_disk.node[each.key].path
    }
  }
}

# 7. Les VMs.
resource "libvirt_domain" "node" {
  for_each = module.nodes.nodes

  name        = each.key
  type        = var.domain_type
  vcpu        = var.node_cpus
  memory      = var.node_memory_mb
  memory_unit = "MiB"
  running     = true
  autostart   = false

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  # Avec KVM, on expose le vrai CPU de l'hôte (performances). En émulation
  # logicielle (domain_type = "qemu"), on laisse QEMU choisir.
  cpu = var.domain_type == "kvm" ? { mode = "host-passthrough" } : null

  devices = {
    disks = concat([
      {
        source = {
          volume = {
            pool   = libvirt_pool.lab.name
            volume = libvirt_volume.root[each.key].name
          }
        }
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device    = "cdrom"
        read_only = true
        source = {
          volume = {
            pool   = libvirt_pool.lab.name
            volume = libvirt_volume.cloudinit[each.key].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      },
      ], each.value.longhorn_disk ? [{
        source = {
          volume = {
            pool   = libvirt_pool.lab.name
            volume = libvirt_volume.longhorn[each.key].name
          }
        }
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        serial = module.nodes.longhorn_disk_serial
        target = {
          dev = "vdb"
          bus = "virtio"
        }
    }] : [])

    interfaces = [{
      model = {
        type = "virtio"
      }
      source = {
        network = {
          network = libvirt_network.lab.name
        }
      }
    }]

  }
}

# 8. Inventaire Ansible généré automatiquement (pont Terraform -> Ansible).
module "inventory" {
  source = "../../modules/ansible-inventory"

  inventory_path       = local.inventory_path
  cluster_name         = local.context_name
  nodes                = module.nodes.nodes
  ssh_user             = var.ssh_user
  ssh_private_key_file = var.ssh_private_key_file
  generated_by         = "terraform/providers/libvirt"

  depends_on = [libvirt_domain.node]
}
