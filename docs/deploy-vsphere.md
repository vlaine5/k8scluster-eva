# Déployer Kubernetes avec VMware vSphere

**Ce mode nécessite VMware vCenter.**
Un ESXi standalone (sans vCenter) n'est pas pris en charge par ce mode Terraform.
Pour un ESXi standalone, utilisez si nécessaire le mode Vagrant historique : voir
[deploy-vagrant.md](deploy-vagrant.md), section « Mode historique : ESXi autonome ».

Ce mode crée des VMs dans vCenter avec Terraform,
puis Ansible installe Kubernetes avec kubeadm.

```text
Terraform → VMs vSphere → Ansible → kubeadm → Kubernetes
```

## Ce que vous allez obtenir

- 1 control-plane : la VM `k8s-cp-1`
- 2 workers : les VMs `k8s-worker-1` et `k8s-worker-2`
- des VMs Ubuntu 24.04 avec des IP fixes sur votre réseau
- Kubernetes 1.37 installé avec kubeadm, runtime containerd, réseau des Pods Flannel

## Prérequis

- un vCenter Server accessible depuis votre machine, et un compte autorisé à créer des VMs
- un template Ubuntu 24.04 dans vCenter (préparation à l'étape 2)
- Terraform (ou OpenTofu) et Ansible sur votre machine, ainsi que `kubectl` et le client SSH
- 3 adresses IP libres sur le réseau des VMs

## 1. Vérifier votre machine

```bash
make doctor MODE=terraform PROVIDER=vsphere
```

À ce stade, `doctor` signale que la configuration vSphere manque : c'est l'étape suivante.

## 2. Configurer

### Préparer le template (une seule fois)

1. Téléchargez l'image cloud Ubuntu 24.04 au format OVA (version datée) :
   `https://cloud-images.ubuntu.com/releases/noble/release-20260911/ubuntu-24.04-server-cloudimg-amd64.ova`
2. Dans vCenter : *Deploy OVF Template*, sans démarrer la VM.
3. *Edit Settings → VM Options* : **désactivez les options vApp** (sinon la configuration
   fournie par Terraform est ignorée).
4. Convertissez la VM en template, nommé `ubuntu-24.04-cloudimg-template`.

### Renseigner vos valeurs

```bash
cp .env.example .env
cp terraform/providers/vsphere/terraform.tfvars.example \
   terraform/providers/vsphere/terraform.tfvars
```

Dans `.env` (vos identifiants, jamais versionnés), décommentez et complétez :

```bash
VSPHERE_SERVER=vcenter.example.lan
VSPHERE_USER=terraform@vsphere.local
VSPHERE_PASSWORD=...
```

Dans `terraform/providers/vsphere/terraform.tfvars` (votre infrastructure, sans secret) :

```hcl
vsphere_datacenter      = "Datacenter"
vsphere_compute_cluster = "Cluster"
vsphere_datastore       = "datastore1"
vsphere_network         = "VM Network"
vsphere_template        = "ubuntu-24.04-cloudimg-template"
network_cidr            = "10.10.0.0/24"
ip_start                = 100   # .100 = control-plane, .101 et .102 = workers
```

## 3. Déployer

```bash
make doctor MODE=terraform PROVIDER=vsphere
make deploy MODE=terraform PROVIDER=vsphere
```

`deploy` affiche le plan Terraform (les VMs à créer) et **demande confirmation** avant de
créer quoi que ce soit. Comptez 10 à 20 minutes.

## 4. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
kubectl get pods -A
```

Le contexte kubectl de ce cluster s'appelle `k8s-lab-vsphere`.

## 5. Tester

```bash
make test
```

## 6. Supprimer

```bash
make destroy MODE=terraform PROVIDER=vsphere
```

La commande demande confirmation, puis lance `terraform destroy`.

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| Erreur de clonage avec un ESXi autonome | ce mode exige un vCenter (voir le début de ce guide) |
| VM sans IP, cloud-init ignoré | les options vApp sont actives sur le template : désactivez-les |
| Erreur de certificat (`x509`) | certificat auto-signé : `VSPHERE_ALLOW_UNVERIFIED_SSL=true` dans `.env` |
| Erreur de droits | le compte doit pouvoir créer des VMs dans le dossier, le pool de ressources, le datastore et le réseau choisis |
| Ansible : `UNREACHABLE` | IP déjà utilisée ou mauvaise passerelle : corrigez `terraform.tfvars` ; test : `ssh -i .lab/ssh/id_ed25519 ubuntu@<ip>` |

Plus de cas : [troubleshooting.md](troubleshooting.md).

## Pour aller plus loin

- Autres réglages de `terraform.tfvars` : `vsphere_folder`, `gateway` (défaut : 1ʳᵉ adresse
  du réseau), `dns_servers`, `wait_for_guest_net_timeout`.
- Terraform transmet la configuration cloud-init (IP fixe, utilisateur `ubuntu`, clé SSH) par
  les propriétés `guestinfo.metadata` et `guestinfo.userdata` de chaque VM.
- Le disque est agrandi à `NODE_DISK_GB` ; mettre à jour le template ne recrée pas les VMs.
- Préférez un compte dédié avec un rôle limité plutôt qu'un administrateur.
- Pourquoi un vCenter ? La documentation du provider
  [`vmware/vsphere`](https://registry.terraform.io/providers/vmware/vsphere) indique que le
  clonage d'une VM et le déploiement d'un OVA ne sont pas possibles sur un ESXi seul.
- Utiliser Terraform directement, outputs, state : [terraform.md](terraform.md).

**Statut : VALIDÉ STATIQUEMENT — TEST SUR VCENTER RÉEL À FAIRE.**
Le code est vérifié en CI (`terraform validate`, TFLint, `terraform test` des modules communs) ;
le déploiement sur un vCenter réel n'a pas encore été testé.
