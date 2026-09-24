# Les identifiants ne sont JAMAIS écrits dans un fichier versionné.
# Par défaut (variables à null), le provider lit l'environnement, alimenté par
# votre fichier .env (chargé par ./k8s-lab) :
#   PROXMOX_VE_ENDPOINT   ex : https://pve.example.lan:8006/
#   PROXMOX_VE_API_TOKEN  ex : terraform@pve!k8s-lab=<secret>
#   PROXMOX_VE_INSECURE   true uniquement pour un certificat auto-signé
# Doc : https://registry.terraform.io/providers/bpg/proxmox/latest/docs
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}
