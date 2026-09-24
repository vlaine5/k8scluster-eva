# Configuration

## Où régler quoi ?

| Fichier | Versionné ? | Contenu |
| --- | --- | --- |
| `config/lab.env` | oui | valeurs par défaut de **tous** les modes |
| `.env` (copie de `.env.example`) | **non** | vos surcharges + vos identifiants (Proxmox, vCenter, ESXi) |
| `terraform/providers/<p>/terraform.tfvars` (copie du `.example`) | **non** | description de votre infrastructure : nœud Proxmox, datastore, réseau… (aucun secret) |

Priorité (la première valeur trouvée gagne) :

1. variable d'environnement : `WORKER_COUNT=3 ./k8s-lab deploy kind` ;
2. variable `make` : `make deploy MODE=kind WORKERS=3` (ou `WORKER_COUNT=3`) ;
3. `.env` ;
4. `config/lab.env`.

`./k8s-lab config` affiche la configuration effective (secrets masqués).

## Référence des variables

### Forme du cluster

| Variable | Défaut | Utilisée par |
| --- | --- | --- |
| `CLUSTER_NAME` | `k8s-lab` | tous : nom des contextes kubectl (`kind-k8s-lab`, `k8s-lab-vagrant`, `k8s-lab-proxmox`…) |
| `WORKER_COUNT` | `2` | kind, vagrant, terraform (0 = cluster mono-nœud) |

### VMs (Vagrant et Terraform)

| Variable | Défaut | Remarque |
| --- | --- | --- |
| `NODE_HOSTNAME_PREFIX` | `k8s` | `k8s-cp-1`, `k8s-worker-1`… |
| `NODE_CPUS` | `2` | minimum 2 (exigence kubeadm) |
| `NODE_MEMORY_MB` | `2048` | minimum 2048 |
| `NODE_DISK_GB` | `20` | Terraform uniquement (avec Vagrant, la taille dépend de la box) |
| `SSH_PRIVATE_KEY_FILE` | vide | vide = clé dédiée générée dans `.lab/ssh/` (Terraform) |
| `VM_IMAGE_URL`, `VM_IMAGE_SHA256` | Ubuntu 24.04, release datée | Terraform Proxmox et libvirt ; le SHA-256 est vérifié |

### Kubernetes (kubeadm, via Ansible)

| Variable | Défaut | Remarque |
| --- | --- | --- |
| `KUBERNETES_VERSION` | `1.37.1` | version exacte ; le dépôt APT `pkgs.k8s.io/…/v1.37` en est déduit |
| `POD_CIDR` | `10.244.0.0/16` | réseau des Pods (aussi utilisé par kind) |
| `SERVICE_CIDR` | `10.96.0.0/12` | réseau des Services (aussi utilisé par kind) |
| `CNI` | `flannel` | `flannel` ou `none` |
| `FLANNEL_VERSION` | `v0.28.9` | doit avoir un checksum connu dans `ansible/roles/cni/defaults/main.yml` |
| `CONTAINER_RUNTIME` | `containerd` | seul runtime implémenté |
| `CONTAINERD_VERSION` | `2.3.*` | motif de version APT du paquet `containerd.io` |

### Kind

| Variable | Défaut | Remarque |
| --- | --- | --- |
| `KIND_NODE_IMAGE` | `kindest/node:v1.37.0@sha256:…` | image publiée avec kind v0.33.0 |
| `KIND_CONFIG` | vide | chemin d'une config kind personnalisée (sinon générée) |

### Minikube

| Variable | Défaut | Remarque |
| --- | --- | --- |
| `MINIKUBE_KUBERNETES_VERSION` | `v1.37.0` | |
| `MINIKUBE_DRIVER` | vide | vide = choix automatique de minikube |
| `MINIKUBE_NODES`, `MINIKUBE_CPUS`, `MINIKUBE_MEMORY_MB` | `1`, `2`, `2048` | par nœud |
| `MINIKUBE_EXTRA_ARGS` | vide | options ajoutées à `minikube start` |

### Vagrant

| Variable | Défaut | Remarque |
| --- | --- | --- |
| `VAGRANT_PROVIDER` | `virtualbox` | `virtualbox`, `libvirt`, `vmware_desktop`, `vmware_esxi` |
| `VAGRANT_BOX` | `bento/ubuntu-24.04` | box multi-providers |
| `VAGRANT_BOX_VERSION` | vide | vide = dernière version disponible pour le provider |
| `VAGRANT_NETWORK_PREFIX` | `192.168.56` | réseau privé des VMs |
| `VAGRANT_IP_START` | `10` | `.10` = control-plane, `.11`, `.12`… = workers |
| `ESXI_HOSTNAME`, `ESXI_USERNAME`, `ESXI_PASSWORD`, `ESXI_DATASTORE`, `ESXI_NETWORKS` | — | mode `vmware_esxi` uniquement, dans `.env` |

### Identifiants (dans `.env` uniquement)

| Variable | Lue par |
| --- | --- |
| `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`, `PROXMOX_VE_INSECURE` | provider Terraform `bpg/proxmox` |
| `VSPHERE_SERVER`, `VSPHERE_USER`, `VSPHERE_PASSWORD`, `VSPHERE_ALLOW_UNVERIFIED_SSL` | provider Terraform `vmware/vsphere` |
| `ESXI_PASSWORD` | plugin `vagrant-vmware-esxi` (syntaxe `env:ESXI_PASSWORD`) |

### Options avancées (environnement)

| Variable | Effet |
| --- | --- |
| `TERRAFORM_BIN=tofu` | utiliser OpenTofu au lieu de Terraform |
| `K8S_LAB_SKIP_DOCTOR=1` | ne pas bloquer le déploiement sur les prérequis (à vos risques) |
| `NO_COLOR=1` | sortie sans couleurs |
| `DEBUG=1` | trace Bash complète du CLI |

## Correspondance entre outils

Le CLI traduit `config/lab.env` pour chaque outil. Quand un outil est utilisé **seul**, il
retombe sur ses propres valeurs par défaut, identiques (vérifié par
`scripts/check-config-sync.sh`).

| `config/lab.env` | Terraform (`TF_VAR_…`) | Ansible (`-e`, `group_vars/all.yml`) | Vagrantfile | kind / minikube |
| --- | --- | --- | --- | --- |
| `CLUSTER_NAME` | `cluster_name` | `cluster_name` (dans l'inventaire généré) | lu directement | nom du cluster / profil |
| `WORKER_COUNT` | `worker_count` | — (déduit de l'inventaire) | lu directement | nœuds `worker` |
| `NODE_HOSTNAME_PREFIX` | `hostname_prefix` | — | lu directement | — |
| `NODE_CPUS` / `NODE_MEMORY_MB` / `NODE_DISK_GB` | `node_cpus` / `node_memory_mb` / `node_disk_gb` | — | lu directement (sauf disque) | — |
| `VM_IMAGE_URL` / `VM_IMAGE_SHA256` | `image_url` / `image_sha256` (proxmox), `image_source` (libvirt) | — | — | — |
| clé SSH du lab | `ssh_public_key`, `ssh_private_key_file` | `ansible_ssh_private_key_file` (inventaire) | clé gérée par Vagrant | — |
| `KUBERNETES_VERSION` | — | `kubernetes_version` | — | — (voir `KIND_NODE_IMAGE`, `MINIKUBE_KUBERNETES_VERSION`) |
| `POD_CIDR` / `SERVICE_CIDR` | — | `pod_cidr` / `service_cidr` | — | `networking.podSubnet` / `serviceSubnet` (kind) |
| `CNI` / `FLANNEL_VERSION` | — | `cni` / `flannel_version` | — | — |
| `CONTAINER_RUNTIME` / `CONTAINERD_VERSION` | — | `container_runtime` / `containerd_version` | — | — |

Les réglages **propres à une plateforme** (nœud Proxmox, datastore, bridge, VLAN, template
vSphere, réseau libvirt…) ne sont pas dans `config/lab.env` : ils sont dans
`terraform/providers/<p>/terraform.tfvars`, documentés dans chaque `terraform.tfvars.example`.
