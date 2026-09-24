# Terraform + Proxmox VE

Provider : [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox) (0.114.x),
le provider Proxmox le plus actif aujourd'hui. Il utilise uniquement l'**API** Proxmox (pas
d'accès SSH à l'hyperviseur nécessaire pour ce lab).

Ce que crée Terraform :

- l'image cloud Ubuntu 24.04, **téléchargée par Proxmox lui-même** depuis une URL datée, avec
  vérification SHA-256 (`proxmox_download_file`) ;
- une VM par nœud (`proxmox_virtual_environment_vm`) : disque importé depuis l'image,
  cloud-init **natif** de Proxmox (IP statique, utilisateur `ubuntu`, clé SSH).

## 1. Préparer Proxmox (une fois)

### Autoriser le type de contenu « Import »

L'image est importée depuis le stockage `local` (par défaut). Dans l'interface web :
*Datacenter → Storage → local → Edit → Content* : cochez **Import**.
(Ou, en ligne de commande sur le nœud : `pvesm set local --content iso,vztmpl,backup,import`
— gardez les types déjà présents.)

### Créer un utilisateur et un token API dédiés

Sur un nœud Proxmox (shell root) :

```bash
pveum user add terraform@pve --comment "k8s-lab Terraform"
pveum role add K8sLab -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate SDN.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.Migrate VM.PowerMgmt"
pveum aclmod / -user terraform@pve -role K8sLab
pveum user token add terraform@pve k8s-lab --privsep 0
```

La dernière commande affiche le secret **une seule fois**. Vérifiez la liste des privilèges
avec la documentation de votre version de Proxmox (elle évolue, notamment en PVE 9) et
restreignez-les au besoin (ACL sur un pool, un stockage et un bridge plutôt que `/`).

## 2. Configurer le lab

`.env` (jamais versionné) :

```bash
PROXMOX_VE_ENDPOINT=https://pve.example.lan:8006/
PROXMOX_VE_API_TOKEN=terraform@pve!k8s-lab=<secret affiché à la création>
# PROXMOX_VE_INSECURE=true      # seulement pour un certificat auto-signé
```

`terraform/providers/proxmox/terraform.tfvars` (copie du `.example`, sans secret) :

```hcl
proxmox_node    = "pve"
vm_datastore    = "local-lvm"
image_datastore = "local"
network_bridge  = "vmbr0"
# vlan_id       = 20
network_cidr    = "192.168.1.0/24"
ip_start        = 100          # .100 = control-plane, .101, .102 = workers
# gateway       = "192.168.1.1"
# dns_servers   = ["192.168.1.1"]
```

Choisissez une plage d'IP **libre** (hors DHCP de votre routeur) : les VMs reçoivent des IP
statiques, il n'y a plus besoin de réservation DHCP par adresse MAC.

## 3. Déployer

```bash
./k8s-lab doctor terraform proxmox
./k8s-lab deploy terraform proxmox
```

## Variables utiles

| Variable (`terraform.tfvars`) | Défaut | Rôle |
| --- | --- | --- |
| `proxmox_node` | — (obligatoire) | nœud qui héberge les VMs |
| `vm_datastore` | `local-lvm` | disques des VMs |
| `cloud_init_datastore` | = `vm_datastore` | disques cloud-init |
| `image_datastore` | `local` | stockage de l'image (contenu *Import*) |
| `network_bridge` / `vlan_id` | `vmbr0` / aucun | réseau des VMs |
| `network_cidr` / `ip_start` / `gateway` / `dns_servers` | — / `100` / `.1` / `1.1.1.1, 9.9.9.9` | adressage |
| `template_vm_id` | aucun | cloner un template cloud-init existant au lieu d'importer l'image |
| `vm_id_start` | aucun | IDs fixes des VMs (`700`, `701`…) |
| `cpu_type` | `x86-64-v2-AES` | `host` pour de meilleures performances (sans migration) |
| `tags` | `["k8s-lab"]` | étiquettes des VMs |

Taille du cluster (`WORKER_COUNT`, `NODE_CPUS`, `NODE_MEMORY_MB`, `NODE_DISK_GB`) : dans `.env`.

### Cloner un template existant

Si vous avez déjà un template cloud-init (disque sur `scsi0`) :

```hcl
template_vm_id = 9000
```

L'image n'est alors pas téléchargée ; le disque cloné est agrandi à `NODE_DISK_GB`.

## Remarques

- L'agent QEMU n'est pas activé (l'image cloud n'en contient pas) : à la destruction,
  les VMs sont arrêtées de force (`stop_on_destroy`), ce qui est sans conséquence ici.
- Pour un cluster Proxmox multi-nœuds, toutes les VMs sont créées sur `proxmox_node`.

## État de validation

Implémenté, validé statiquement (`terraform validate`, TFLint) et par `terraform plan` avec un
endpoint factice (création de l'image et des VMs, variante « template »).
**Nécessite un test d'intégration sur un Proxmox VE réel** (création, cloud-init, Ansible).
