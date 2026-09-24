# Déployer Kubernetes avec Proxmox

Ce mode crée des VMs dans Proxmox avec Terraform,
puis Ansible installe Kubernetes avec kubeadm.

```text
Terraform → Proxmox VMs → Ansible → kubeadm → Kubernetes
```

## Ce que vous allez obtenir

- 1 control-plane : la VM `k8s-cp-1`
- 2 workers : les VMs `k8s-worker-1` et `k8s-worker-2`
- des VMs Ubuntu 24.04 avec des IP fixes sur votre réseau
- Kubernetes 1.37 installé avec kubeadm, runtime containerd, réseau des Pods Flannel

## Prérequis

- un Proxmox VE (8.4 ou plus récent) accessible depuis votre machine
- un token API Proxmox (création à l'étape 2)
- Terraform (ou OpenTofu) et Ansible sur votre machine, ainsi que `kubectl`
- une clé SSH : le lab en génère une automatiquement (`.lab/ssh/`), il suffit d'avoir le
  client SSH
- 3 adresses IP libres sur le réseau des VMs (en dehors de la plage DHCP)

## 1. Vérifier votre machine

```bash
make doctor MODE=terraform PROVIDER=proxmox
```

À ce stade, `doctor` signale que la configuration Proxmox manque : c'est l'étape suivante.

## 2. Configurer

### Préparer Proxmox (une seule fois)

1. Autorisez l'import d'images sur le stockage `local` : *Datacenter → Storage → local →
   Edit → Content*, cochez **Import**.
2. Dans le shell d'un nœud Proxmox (root), créez un utilisateur et un token dédiés :

   ```bash
   pveum user add terraform@pve --comment "k8s-lab Terraform"
   pveum role add K8sLab -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate SDN.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.Migrate VM.PowerMgmt"
   pveum aclmod / -user terraform@pve -role K8sLab
   pveum user token add terraform@pve k8s-lab --privsep 0
   ```

   La dernière commande affiche le secret du token **une seule fois** : notez-le.

### Renseigner vos valeurs

```bash
cp .env.example .env
cp terraform/providers/proxmox/terraform.tfvars.example \
   terraform/providers/proxmox/terraform.tfvars
```

Dans `.env` (vos identifiants, jamais versionnés), décommentez et complétez :

```bash
PROXMOX_VE_ENDPOINT=https://proxmox.example.local:8006/
PROXMOX_VE_API_TOKEN=terraform@pve!k8s-lab=<secret du token>
```

Dans `terraform/providers/proxmox/terraform.tfvars` (votre infrastructure, sans secret) :

```hcl
proxmox_node   = "pve"            # nom du nœud Proxmox
vm_datastore   = "local-lvm"      # stockage des disques des VMs
network_bridge = "vmbr0"          # bridge réseau des VMs
network_cidr   = "192.168.1.0/24" # réseau des VMs
ip_start       = 100              # .100 = control-plane, .101 et .102 = workers
```

La passerelle par défaut est la première adresse du réseau (ici `192.168.1.1`) ; sinon,
réglez `gateway` dans le même fichier.

## 3. Déployer

```bash
make doctor MODE=terraform PROVIDER=proxmox
make deploy MODE=terraform PROVIDER=proxmox
```

`doctor` doit maintenant être entièrement vert (il vérifie aussi que l'API Proxmox répond).
`deploy` affiche le plan Terraform (les VMs à créer) et **demande confirmation** avant de
créer quoi que ce soit. Comptez 10 à 20 minutes.

## 4. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
kubectl get pods -A
```

Le contexte kubectl de ce cluster s'appelle `k8s-lab-proxmox`.

## 5. Tester

```bash
make test
```

## 6. Supprimer

```bash
make destroy MODE=terraform PROVIDER=proxmox
```

La commande demande confirmation, puis lance `terraform destroy`.

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| `storage 'local' does not support content-type 'import'` | cochez **Import** sur le stockage (étape 2) |
| `401` ou `permission check failed` | vérifiez `PROXMOX_VE_API_TOKEN` (format `utilisateur!nom=secret`) et le rôle du token |
| `doctor` : API Proxmox injoignable | vérifiez l'URL et le réseau ; certificat auto-signé : `PROXMOX_VE_INSECURE=true` dans `.env` |
| Ansible : `UNREACHABLE` | IP déjà utilisée, mauvais bridge ou VLAN, mauvaise passerelle : corrigez `terraform.tfvars` ; test : `ssh -i .lab/ssh/id_ed25519 ubuntu@<ip>` |
| Une étape échoue en cours de route | corrigez puis relancez `make deploy MODE=terraform PROVIDER=proxmox` : seul ce qui manque est refait |

Plus de cas : [troubleshooting.md](troubleshooting.md).

## Pour aller plus loin

### Autres réglages de `terraform.tfvars`

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `image_datastore` | `local` | stockage où l'image Ubuntu est téléchargée (contenu *Import*) |
| `cloud_init_datastore` | = `vm_datastore` | disques cloud-init |
| `vlan_id` | aucun | VLAN des VMs |
| `gateway` / `dns_servers` | 1ʳᵉ adresse du réseau / `1.1.1.1, 9.9.9.9` | adressage |
| `template_vm_id` | aucun | cloner un template cloud-init existant (disque sur `scsi0`) au lieu d'importer l'image |
| `vm_id_start` | aucun | IDs fixes des VMs (`700`, `701`…) |
| `cpu_type` | `x86-64-v2-AES` | `host` pour de meilleures performances (sans migration à chaud) |
| `tags` | `["k8s-lab"]` | étiquettes des VMs |

La taille du cluster (`WORKER_COUNT`, `NODE_CPUS`, `NODE_MEMORY_MB`, `NODE_DISK_GB`) se règle
dans `.env`, ou au déploiement : `make deploy MODE=terraform PROVIDER=proxmox WORKERS=3`.

### Ce que crée Terraform

- l'image cloud Ubuntu 24.04, téléchargée par Proxmox lui-même depuis une URL datée, avec
  vérification SHA-256 ;
- une VM par nœud, avec le cloud-init natif de Proxmox (IP fixe, utilisateur `ubuntu`, clé SSH).

Le provider utilisé est [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox) :
il passe uniquement par l'API (aucun accès SSH à l'hyperviseur n'est nécessaire).

### Remarques

- Les privilèges du rôle `K8sLab` évoluent avec les versions de Proxmox : vérifiez-les dans la
  documentation de votre version, et restreignez l'ACL (pool, stockage, bridge) plutôt que `/`.
- Réduire le nombre de workers détruit les VMs en trop (le plan l'annonce), mais leurs nœuds
  restent déclarés dans Kubernetes (`NotReady`) : supprimez-les avec `kubectl delete node <nom>`
  puis relancez `deploy`. Plus simple : supprimez le lab et recréez-le.
- Utiliser Terraform directement, outputs, state : [terraform.md](terraform.md).

**Statut : VALIDÉ STATIQUEMENT — TEST SUR PROXMOX RÉEL À FAIRE.**
Le code est vérifié en CI (`terraform validate`, TFLint, `terraform test` des modules communs) ;
le déploiement sur un Proxmox réel n'a pas encore été testé.
