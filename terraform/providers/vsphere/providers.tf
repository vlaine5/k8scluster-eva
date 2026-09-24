# Les identifiants ne sont JAMAIS écrits dans un fichier versionné.
# Par défaut (variables à null), le provider lit l'environnement, alimenté par
# votre fichier .env (chargé par ./k8s-lab) :
#   VSPHERE_SERVER, VSPHERE_USER, VSPHERE_PASSWORD
#   VSPHERE_ALLOW_UNVERIFIED_SSL=true (uniquement pour un certificat auto-signé)
#
# IMPORTANT : VSPHERE_SERVER doit être un vCenter. Le clonage de template
# n'est pas supporté par le provider sur un ESXi autonome (voir
# docs/terraform-vsphere.md ; pour un ESXi seul, utilisez le mode Vagrant).
provider "vsphere" {
  vsphere_server       = var.vsphere_server
  user                 = var.vsphere_user
  password             = var.vsphere_password
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
}
