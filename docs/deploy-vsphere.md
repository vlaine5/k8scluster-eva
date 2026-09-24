# Terraform + VMware vSphere (vCenter)

Provider : [`vmware/vsphere`](https://registry.terraform.io/providers/vmware/vsphere) (2.17.x),
le provider officiel maintenu par VMware (successeur de `hashicorp/vsphere`).

## Limitation importante : vCenter obligatoire

La documentation officielle du provider (ressource `vsphere_virtual_machine`) indique :

> *Cloning requires vCenter Server and is not supported on direct ESXi host connections.*
> *An OVF/OVA deployment requires vCenter Server and is not supported on direct ESXi host connections.*

Or créer des VMs Ubuntu prêtes pour cloud-init passe par le clonage d'un template (ou le
déploiement d'un OVA). **Ce mode ne fonctionne donc qu'avec un vCenter.** Pour un **ESXi
autonome** (licence gratuite, homelab…), utilisez le mode historique
[Vagrant + vagrant-vmware-esxi](vagrant.md#mode-historique-esxi-autonome).

## 1. Préparer le template (une fois)

1. Téléchargez l'OVA de l'image cloud Ubuntu 24.04, **datée** :
   `https://cloud-images.ubuntu.com/releases/noble/release-20260911/ubuntu-24.04-server-cloudimg-amd64.ova`
   (SHA-256 dans le fichier `SHA256SUMS` du même dossier).
2. Dans vCenter : *Deploy OVF Template*, sans démarrer la VM.
3. *Edit Settings → VM Options* : **désactivez les options vApp** (sinon cloud-init lit la
   configuration OVF au lieu de la configuration `guestinfo` fournie par Terraform).
4. Convertissez la VM en template, nommée par exemple `ubuntu-24.04-cloudimg-template`.

L'image contient `open-vm-tools` et cloud-init avec la datasource VMware : Terraform lui
transmet la configuration (IP statique, utilisateur, clé SSH) via les propriétés
`guestinfo.metadata` et `guestinfo.userdata` de chaque VM.

## 2. Configurer le lab

`.env` :

```bash
VSPHERE_SERVER=vcenter.example.lan
VSPHERE_USER=terraform@vsphere.local
VSPHERE_PASSWORD=...
# VSPHERE_ALLOW_UNVERIFIED_SSL=true   # seulement pour un certificat auto-signé
```

Créez un compte dédié avec un rôle limité (droits sur le dossier, le pool de ressources, le
datastore et le port group utilisés), plutôt qu'un administrateur.

`terraform/providers/vsphere/terraform.tfvars` :

```hcl
vsphere_datacenter      = "Datacenter"
vsphere_compute_cluster = "Cluster"
vsphere_datastore       = "datastore1"
vsphere_network         = "VM Network"
vsphere_template        = "ubuntu-24.04-cloudimg-template"
# vsphere_folder        = "k8s-lab"
network_cidr            = "10.10.0.0/24"
ip_start                = 100
```

## 3. Déployer

```bash
./k8s-lab doctor terraform vsphere
./k8s-lab deploy terraform vsphere
```

## Remarques

- Le disque est agrandi à `NODE_DISK_GB` (jamais réduit sous la taille du template).
- Mettre à jour le template ne recrée pas les VMs existantes (`ignore_changes` sur le template).
- `wait_for_guest_net_timeout` (5 min) : Terraform attend que VMware Tools remonte l'IP.

## État de validation

Implémenté, validé statiquement (`terraform validate`, TFLint). Le plan nécessite un vCenter
(sources de données). **Nécessite un test d'intégration sur un vCenter réel.**
