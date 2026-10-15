# =============================================================================
#  Module k8s-nodes : décrit les nœuds du cluster, indépendamment du provider.
#
#  Il calcule, pour chaque nœud : nom, rôle, IP statique, présence d'un disque
#  Longhorn dédié, et les fichiers cloud-init (user-data, meta-data,
#  network-config). Chaque provider (Proxmox, vSphere, libvirt...) n'a plus
#  qu'à créer les VMs : aucune logique "Kubernetes" n'est dupliquée.
#
#  Adresses : control-planes à ip_start, ip_start+1... ; workers à
#  ip_start + worker_ip_offset (par défaut juste après le dernier control-plane).
# =============================================================================

locals {
  prefix_length = tonumber(split("/", var.network_cidr)[1])
  # Le prefixe ne change jamais le masque des VM : il choisit seulement leurs IP.
  # Exemple : 10.20.50 + 10 -> 10.20.50.10, avec le masque /16 du VLAN.
  gateway          = coalesce(var.gateway, cidrhost(var.network_cidr, 1))
  worker_ip_offset = coalesce(var.worker_ip_offset, var.control_plane_count)

  # Groupe sudo selon la famille de l'OS (Ubuntu/Debian : sudo ; Rocky : wheel).
  admin_group = var.os_family == "redhat" ? "wheel" : "sudo"

  control_planes = [for i in range(var.control_plane_count) : {
    name      = "${var.hostname_prefix}-cp-${i + 1}"
    role      = "control_plane"
    index     = i
    ip_offset = i
  }]

  workers = [for i in range(var.worker_count) : {
    name      = "${var.hostname_prefix}-worker-${i + 1}"
    role      = "worker"
    index     = var.control_plane_count + i
    ip_offset = local.worker_ip_offset + i
  }]

  # Nœuds de stockage Longhorn : les workers, ou les control-planes s'il n'y a pas de worker.
  storage_role = var.worker_count > 0 ? "worker" : "control_plane"

  # Map nom -> description complète du nœud (utilisée avec for_each).
  nodes = {
    for n in concat(local.control_planes, local.workers) : n.name => merge(n, {
      ip            = (var.node_ip_prefix == null ? cidrhost(var.network_cidr, var.ip_start + n.ip_offset) : "${var.node_ip_prefix}.${var.ip_start + n.ip_offset}")
      address       = "${(var.node_ip_prefix == null ? cidrhost(var.network_cidr, var.ip_start + n.ip_offset) : "${var.node_ip_prefix}.${var.ip_start + n.ip_offset}")}/${local.prefix_length}"
      longhorn_disk = var.longhorn_disk_gb > 0 && n.role == local.storage_role
    })
  }

  cloud_init = {
    for name, node in local.nodes : name => {
      user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
        hostname       = name
        ssh_user       = var.ssh_user
        admin_group    = local.admin_group
        ssh_public_key = trimspace(var.ssh_public_key)
        packages       = var.extra_packages
      })

      meta_data = yamlencode({
        "instance-id"    = name
        "local-hostname" = name
      })

      network_config = yamlencode(local.network_config[name])
    }
  }

  # Configuration réseau "netplan v2" comprise par cloud-init (Ubuntu, Debian, Rocky).
  network_config = {
    for name, node in local.nodes : name => {
      version = 2
      ethernets = {
        primary = {
          match     = { name = var.interface_match }
          dhcp4     = false
          addresses = [node.address]
          routes    = [{ to = "default", via = local.gateway }]
          nameservers = {
            addresses = var.dns_servers
            search    = var.dns_search_domains
          }
        }
      }
    }
  }
}
