# Adresses IP des noeuds Kubernetes sur Proxmox

Ce guide explique comment placer les VM Kubernetes dans une plage logique du VLAN
sans creer de nouveau sous-reseau.

## Exemple : VLAN 20 en /16

Le VLAN utilise **10.20.0.0/16**, avec la passerelle **10.20.0.1**.
On souhaite :

- noeud control-plane : **10.20.50.10/16** ;
- trois workers : **10.20.50.11/16** a **10.20.50.13/16** ;
- services MetalLB : **10.20.80.100** a **10.20.80.200**.

### 1. Configuration Proxmox

Dans `terraform/providers/proxmox/terraform.tfvars` (fichier local, non versionne) :

```hcl
network_cidr  = "10.20.0.0/16" # vrai reseau et masque des VM
node_ip_prefix = "10.20.50"   # trois premiers octets des IP des VM
ip_start      = 10             # derniere partie de la premiere IP
gateway       = "10.20.0.1"
```

**Important :** `node_ip_prefix` n'est pas un CIDR. Il ne contient **pas**
de `/16` ni de `/24`. Le masque applique a chaque VM vient exclusivement
de `network_cidr`. Ne pas utiliser l'ancien parametre `node_ip_cidr`.

Sans `node_ip_prefix`, le calcul historique des adresses reste actif.

### 2. Configuration du cluster

Dans `.env` (fichier local, non versionne) :

```dotenv
NODE_NETWORK_CIDR=10.20.0.0/16
LOADBALANCER_PROVIDER=metallb
LOADBALANCER_MODE=l2
LOADBALANCER_IP_POOL=10.20.80.100-10.20.80.200
```

La plage MetalLB est independante de la plage des noeuds. Toutes les IP
doivent etre libres et exclues du DHCP.

### 3. Mettre a jour le framework sans perdre la configuration

```bash
cd ~/k8scluster-eva
mkdir -p /root/k8s-config-backup
cp -a .env /root/k8s-config-backup/.env
cp -a terraform/providers/proxmox/terraform.tfvars /root/k8s-config-backup/terraform.tfvars
git fetch origin feature/node-ip-subnet
git switch feature/node-ip-subnet
```

Ne pas utiliser `git clean -fdx` : cela pourrait supprimer des fichiers locaux.

### 4. Previsualiser les quatre adresses

```bash
source .venv/bin/activate
make doctor MODE=terraform PROVIDER=proxmox
make config MODE=terraform PROVIDER=proxmox
make validate MODE=terraform PROVIDER=proxmox
```

Avec `WORKER_COUNT=3` dans `.env`, la partie **Noeuds prevus** de
`make config` doit afficher :

- `k8s-cp-1` : `10.20.50.10`
- `k8s-worker-1` : `10.20.50.11`
- `k8s-worker-2` : `10.20.50.12`
- `k8s-worker-3` : `10.20.50.13`

### 5. Afficher le VRAI plan Terraform, sans creer de VM

```bash
make plan MODE=terraform PROVIDER=proxmox
```

Cette commande transmet automatiquement les parametres de `.env` et de
`terraform.tfvars` a Terraform, puis lance `terraform plan` **sans
`terraform apply`**. Aucune VM n'est creee ou modifiee.

Controlez le plan : quatre VM, adresses `10.20.50.10/16` a
`10.20.50.13/16`, CPU, memoire, stockage et **aucune destruction imprevue**.
Si le plan propose une destruction ou ne correspond pas a vos attentes,
**ne lancez pas `make deploy`**.

### 6. Deployez seulement apres avoir controle le plan

```bash
make deploy MODE=terraform PROVIDER=proxmox
```

Cette commande demande confirmation avant `terraform apply`.
Contrairement a `make plan`, elle peut effectivement creer les VM.

### 7. Points de controle

- Le bridge Proxmox pointe bien vers le VLAN voulu.
- La passerelle et le DNS sont accessibles depuis les futures VM.
- Les IP des noeuds et de MetalLB sont disponibles.
- Le stockage Proxmox dispose d'assez d'espace.
- Le token API Proxmox reste exclusivement dans `.env`, jamais dans Git.
