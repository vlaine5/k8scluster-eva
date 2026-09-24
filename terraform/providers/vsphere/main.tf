# =============================================================================
#  Cluster Kubernetes sur VMware vSphere (vCenter) : création des VMs
#  uniquement, par clonage d'un template "image cloud Ubuntu".
#  cloud-init reçoit sa configuration via les propriétés "guestinfo" de la VM
#  (datasource VMware de cloud-init). Kubernetes est ensuite installé par
#  Ansible grâce à l'inventaire généré à la fin de ce fichier.
# =============================================================================

locals {
  context_name   = "${var.cluster_name}-vsphere"
  inventory_path = coalesce(var.inventory_path, abspath("${path.root}/../../../ansible/inventories/terraform-vsphere.ini"))

  # meta-data au format de la datasource VMware : identité + réseau.
  vmware_metadata = {
    for name, node in module.nodes.nodes : name => yamlencode({
      "instance-id"    = name
      "local-hostname" = name
      "network"        = module.nodes.network_config[name]
    })
  }
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

# 2. Objets vCenter existants (lecture seule).
data "vsphere_datacenter" "this" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "this" {
  name          = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_datastore" "this" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vsphere_template
  datacenter_id = data.vsphere_datacenter.this.id
}

# 3. Une VM par nœud, clonée depuis le template.
resource "vsphere_virtual_machine" "node" {
  for_each = module.nodes.nodes

  name             = each.key
  annotation       = "Kubernetes ${each.value.role} of ${local.context_name} - managed by Terraform (k8s-lab)"
  resource_pool_id = data.vsphere_compute_cluster.this.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id
  folder           = var.vsphere_folder

  num_cpus = var.node_cpus
  memory   = var.node_memory_mb
  guest_id = data.vsphere_virtual_machine.template.guest_id
  firmware = data.vsphere_virtual_machine.template.firmware

  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = max(var.node_disk_gb, data.vsphere_virtual_machine.template.disks[0].size)
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  # cloud-init (datasource VMware) : https://cloudinit.readthedocs.io/en/latest/reference/datasources/vmware.html
  extra_config = {
    "guestinfo.metadata"          = base64encode(local.vmware_metadata[each.key])
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = base64encode(module.nodes.cloud_init[each.key].user_data)
    "guestinfo.userdata.encoding" = "base64"
  }

  wait_for_guest_net_timeout = var.wait_for_guest_net_timeout

  lifecycle {
    # Mettre à jour le template ne doit pas recréer les VMs existantes.
    ignore_changes = [clone[0].template_uuid]
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
  generated_by         = "terraform/providers/vsphere"

  depends_on = [vsphere_virtual_machine.node]
}
