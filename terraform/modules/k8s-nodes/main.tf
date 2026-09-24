# =============================================================================
#  Module k8s-nodes : décrit les nœuds du cluster, indépendamment du provider.
#
#  Il calcule, pour chaque nœud : nom, rôle, IP statique, et les fichiers
#  cloud-init (user-data, meta-data, network-config). Chaque provider
#  (Proxmox, vSphere, libvirt...) n'a plus qu'à créer les VMs à partir de ça :
#  aucune logique "Kubernetes" n'est dupliquée entre providers.
# =============================================================================

locals {
  prefix_length = tonumber(split("/", var.network_cidr)[1])
  gateway       = coalesce(var.gateway, cidrhost(var.network_cidr, 1))

  control_plane = [{
    name  = "${var.hostname_prefix}-cp-1"
    role  = "control_plane"
    index = 0
  }]

  workers = [for i in range(var.worker_count) : {
    name  = "${var.hostname_prefix}-worker-${i + 1}"
    role  = "worker"
    index = i + 1
  }]

  # Map nom -> description complète du nœud (utilisée avec for_each).
  nodes = {
    for n in concat(local.control_plane, local.workers) : n.name => merge(n, {
      ip      = cidrhost(var.network_cidr, var.ip_start + n.index)
      address = "${cidrhost(var.network_cidr, var.ip_start + n.index)}/${local.prefix_length}"
    })
  }

  cloud_init = {
    for name, node in local.nodes : name => {
      user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
        hostname       = name
        ssh_user       = var.ssh_user
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

  # Configuration réseau "netplan v2" comprise par cloud-init.
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
