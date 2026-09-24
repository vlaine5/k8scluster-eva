# qemu:///system = l'hyperviseur KVM local, géré par le démon libvirtd.
# Votre utilisateur doit appartenir au groupe "libvirt" (voir docs/terraform-libvirt.md).
# Un hôte distant est possible : qemu+ssh://user@serveur/system
provider "libvirt" {
  uri = var.libvirt_uri
}
