# Architecture du dépôt

## Vue d'ensemble

```text
                        config/lab.env  +  .env (vos réglages, vos secrets)
                                      │
                                      ▼
                          ./k8s-lab  (Makefile = raccourcis)
          ┌───────────────┬───────────┴──────────┬──────────────────────────┐
          ▼               ▼                      ▼                          ▼
        kind          minikube             vagrant up               terraform plan/apply
   (local/kind/)                        (vagrant/Vagrantfile)   (terraform/providers/<p>/)
          │               │                      │                  │                │
          │               │                      │          proxmox, vsphere,       eks
          │               │                      │               libvirt             │
          │               │                      └────────┬─────────┘                │
          │               │                               ▼                          │
          │               │                 ansible/inventories/*.ini (généré)       │
          │               │                               ▼                          ▼
          │               │                 ansible-playbook site.yml      cluster EKS + Managed
          │               │                 common → container_runtime     Node Group (AWS),
          │               │                 → kubernetes → control_plane   addons vpc-cni,
          │               │                 (kubeadm init) → cni → worker  kube-proxy, coredns
          │               │                 (kubeadm join) → vérifications           │
          ▼               ▼                               ▼                          ▼
      .kube/config  ◄──────────── un contexte par cluster ─────── aws eks update-kubeconfig
                                      ▼
                          smoke test : nœuds Ready, Pods système prêts
```

## Les dossiers

| Dossier | Contenu | Rôle |
| --- | --- | --- |
| `k8s-lab`, `scripts/lib/` | CLI Bash | interface unique : menu, `deploy`, `destroy`, `doctor`, `status`… |
| `Makefile` | cibles `make` | raccourcis vers `./k8s-lab`, + cibles de qualité (`make lint`) |
| `config/lab.env` | configuration par défaut | **source unique** des réglages (versions, taille, réseaux) |
| `local/kind/` | `kind-config.yaml` | configuration Kind de référence (versionnée) |
| `local/minikube/` | notes | Minikube se configure par options, générées par le CLI |
| `vagrant/` | `Vagrantfile` | VMs locales ; écrit `ansible/inventories/vagrant.ini` |
| `terraform/modules/k8s-nodes/` | module sans provider | noms, rôles, IP statiques et cloud-init de chaque nœud |
| `terraform/modules/ansible-inventory/` | module | écrit l'inventaire Ansible à partir des nœuds |
| `terraform/providers/<p>/` | un « root module » par plateforme | proxmox, vsphere, libvirt : **uniquement** la création des VMs |
| `terraform/providers/eks/` | root module autonome | cluster AWS EKS managé : VPC, IAM, cluster, Managed Node Group, addons (ni VM à installer, ni Ansible) |
| `ansible/` | playbooks + rôles | installation de Kubernetes avec kubeadm, pour toutes les VMs |
| `examples/` | manifestes | nginx + Service pour tester un cluster |
| `tests/kubeadm-in-docker/` | test d'intégration | le vrai `site.yml` sur des nœuds conteneurs systemd (CI) |
| `.github/workflows/` | CI | lint, validation, tests Terraform, tests de bout en bout (Kind, Minikube, kubeadm) ; test EKS réel déclenché à la main |

Fichiers générés (tous ignorés par Git) : `.lab/` (clé SSH du lab, caches, variables Ansible),
`.kube/` (kubeconfigs), `ansible/inventories/*.ini` (sauf l'exemple), `terraform.tfstate`.

## Principes

### 1. Provisionner l'infrastructure ≠ installer Kubernetes

Vagrant et Terraform ne font **que** créer des VMs (avec une IP fixe et une clé SSH), puis
écrivent un inventaire Ansible. Ansible installe Kubernetes, **de la même façon partout**.
Il n'y a qu'un seul code kubeadm dans le dépôt : `ansible/roles/`.

### 1 bis. Exception voulue : EKS, Kubernetes managé

Avec EKS, AWS fournit le control-plane et gère les workers (Managed Node Group) : il n'y a
rien à installer. Le provider `eks` n'utilise donc ni les modules `k8s-nodes` /
`ansible-inventory`, ni Ansible, ni kubeadm ; le CLI obtient le kubeconfig avec
`aws eks update-kubeconfig`. Cette différence est le sujet même du niveau 4 : comparer
« je construis mon cluster » et « le cloud me fournit le control-plane ».

### 2. Pas de duplication entre providers Terraform

Tout ce qui ne dépend pas de la plateforme est dans `terraform/modules/` :

- `k8s-nodes` calcule les nœuds (`k8s-cp-1`, `k8s-worker-1…`), leurs IP (`cidrhost`), et les
  documents cloud-init (utilisateur, clé SSH, réseau statique) ;
- `ansible-inventory` écrit l'inventaire.

Un provider (`terraform/providers/proxmox/main.tf`…) se limite à « transformer chaque nœud en
VM ». **Ajouter un cloud** (OpenStack, AWS, Azure…) = créer `terraform/providers/<nom>/`
qui appelle ces deux modules, puis ajouter le nom dans `scripts/lib/mode_terraform.sh`.
Pour un cloud public, `network_cidr` devient le sous-réseau créé pour le lab et
`ansible_host` l'IP publique (ou un bastion).

### 3. Une seule source de configuration

`config/lab.env` est lue par le CLI (Bash) et par le `Vagrantfile` (Ruby). Le CLI la
transmet à Terraform (variables `TF_VAR_*`) et à Ansible (extra vars). Terraform et Ansible
gardent des valeurs par défaut identiques pour rester utilisables seuls ;
`scripts/check-config-sync.sh` (lancé en CI) vérifie qu'elles ne divergent pas.
Correspondance complète : [configuration.md](configuration.md).

### 4. Rien de destructif sans le demander

`deploy` est **idempotent** : `vagrant up`, `terraform apply` et le playbook Ansible
convergent vers l'état voulu sans recréer ce qui existe. La destruction passe uniquement par
`destroy` (ou `deploy --recreate`), avec confirmation. Un plan Terraform qui détruirait une
ressource est signalé avant confirmation.

### 5. Pédagogie avant généricité

Le CLI affiche chaque commande réellement exécutée. Les fichiers sont commentés en français.
Le lab reste volontairement limité : un seul control-plane, containerd, Flannel par défaut.
Les points d'extension (autre CNI, autre runtime, autre cloud) sont indiqués dans le code
plutôt qu'implémentés à moitié.

## Pourquoi un CLI Bash + un Makefile ?

- `make deploy MODE=kind` est familier et court ; `./k8s-lab` offre en plus un menu pour les
  débutants et des messages d'erreur pédagogiques.
- Le Makefile ne contient **aucune logique** : il appelle `./k8s-lab`. Une seule
  implémentation à maintenir.
- Bash est disponible partout (Linux, macOS, WSL2) et reste lisible par des étudiants.
