# =============================================================================
#  Cluster Kubernetes sur KVM/libvirt (votre propre machine Linux).
#
#  Terraform crée : un pool de stockage, un réseau NAT, l'image Ubuntu de
#  base, puis pour chaque nœud un disque (copy-on-write sur l'image de base),
#  un disque cloud-init et la VM. Kubernetes est ensuite installé par Ansible
#  grâce à l'inventaire généré à la fin de ce fichier.
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

  hostname_prefix = var.hostname_prefix
  worker_count    = var.worker_count
  network_cidr    = var.network_cidr
  ip_start        = var.ip_start
  gateway         = local.gateway
  dns_servers     = [local.gateway]
  ssh_user        = var.ssh_user
  ssh_public_key  = var.ssh_public_key
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

# 4. Image Ubuntu de base (lecture seule, partagée par tous les nœuds).
resource "libvirt_volume" "base" {
  name = "${var.cluster_name}-ubuntu-base.qcow2"
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
    disks = [
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
    ]

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
