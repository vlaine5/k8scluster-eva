# Architecture

## Vue d'ensemble

```text
 .env + config/lab.env ──► scripts/labctl (résolveur Python)
 config/schema.yaml          │  validation complète, choix résolus, plan des addons,
 config/versions.yaml        │  variables Ansible (sans secret), manifeste
 config/profiles.yaml        ▼
 addons/*/addon.yaml   ./k8s-lab (CLI Bash) ◄── make <cible>
                             │
        ┌──────────────┬─────┴───────┬───────────────┬──────────────┐
        ▼              ▼             ▼               ▼              ▼
     kind /        Vagrant      Terraform        mode existing   mode attach
     minikube      (VMs)        (Proxmox,        (inventaire)    (kubeconfig)
        │            │          vSphere,             │              │
        │            │          libvirt, EKS)        │              │
        │            └────── inventaire Ansible ─────┘              │
        │                          ▼                                │
        │            ansible/site.yml : préparation multi-OS,       │
        │            containerd, kubeadm, HA (kube-vip), CNI        │
        │                          │                                │
        └──────────────────────────┼────────────────────────────────┘
                                   ▼
            ansible/addons.yml (depuis votre poste, API Kubernetes)
            → moteur générique roles/addon : Helm, manifestes, santé, tests
                                   ▼
                   validation : smoke tests, tests des addons, manifeste
```

## Les dossiers

| Dossier | Rôle |
| --- | --- |
| `config/` | configuration par défaut (`lab.env`), schéma, versions verrouillées, profils d'addons |
| `scripts/labctl`, `scripts/labcore/` | résolveur : validation, plan, variables, détection (attach), plans de mise à niveau, documentation générée |
| `k8s-lab`, `scripts/lib/` | CLI Bash : un fichier par mode, addons, exploitation, doctor |
| `terraform/modules/` | `k8s-nodes` (nœuds, IP, cloud-init) et `ansible-inventory`, communs aux providers |
| `terraform/providers/` | proxmox, vsphere, libvirt (VMs) et eks (Kubernetes managé) |
| `vagrant/` | VMs Vagrant (VirtualBox, libvirt, VMware) |
| `ansible/` | playbooks (`site.yml`, `addons.yml`, exploitation) et rôles |
| `addons/` | catalogue : une fiche + valeurs + manifestes + test par addon |
| `tests/` | unitaires (résolveur), rendu des addons, scénarios e2e, kubeadm-in-docker |
| `docs/`, `examples/` | documentation, profils d'exemple, application GitOps |

## Rôles Ansible

| Rôle | Rôle |
| --- | --- |
| `preflight` | contrôles en lecture seule (OS, ressources, conflits, cluster existant) |
| `common` | paquets, noyau, swap, SELinux/AppArmor, pare-feu (Ubuntu/Debian/Rocky) |
| `container_runtime` | containerd (dépôt Docker), cgroup systemd |
| `kubernetes` | kubelet/kubeadm/kubectl gelés |
| `node_prereqs` | prérequis demandés par les addons (iSCSI, NFS, modules) |
| `storage_disk` | disque Longhorn dédié (jamais un disque non vide) |
| `api_endpoint` | kube-vip (VIP de l'API) |
| `control_plane` | `kubeadm init`, jonction des control-planes, vérifications, kubeconfig |
| `cni` | Flannel, Calico, Cilium (+ CRD Gateway API pour Cilium) |
| `cluster_core` | approbation des certificats kubelet, nœud unique |
| `worker` | `kubeadm join` |
| `etcd` | santé, instantanés, restauration, planification |
| `upgrade` | mise à niveau kubeadm nœud par nœud |
| `addon` | moteur générique des addons |

## Principes

### 1. Une seule source de vérité, validée avant d'agir

Toute la configuration passe par le résolveur. Une erreur de frappe, une contradiction ou un
chevauchement de réseau arrête tout **avant** la moindre création. Les valeurs `auto` sont
résolues explicitement et affichées (`make config`). Le Bash ne fait aucun choix : il exécute
le plan (`LAB_R_*`), Ansible reçoit un fichier de variables sans secret.

### 2. Provisionner l'infrastructure ≠ installer Kubernetes ≠ installer les addons

Terraform/Vagrant créent des machines et écrivent un inventaire ; Ansible + kubeadm y
installent Kubernetes ; les addons sont installés ensuite **par l'API**, depuis votre poste,
par un moteur unique. Le mode existing saute la première étape, le mode attach les deux
premières, EKS remplace la deuxième par AWS. Chaque étape se relance seule.

### 3. Catalogue déclaratif

Un addon se décrit (dépendances, compatibilité par plateforme, santé, test) au lieu de se
programmer. Le résolveur calcule l'ordre (dépendances puis phases) et refuse les conflits ;
la documentation de référence et les matrices sont générées depuis le catalogue.

### 4. Versions verrouillées, intégrité vérifiée

Un seul fichier (`config/versions.yaml`) ; SHA-256 pour tout téléchargement ; rien en
`latest` ; `make versions-check` signale les nouveautés sans rien installer.

### 5. Rien de destructif ni de surprenant

Pas de destruction sans confirmation (et nom tapé pour les opérations critiques) ; jamais
de formatage d'un disque non vide, de `kubeadm reset` automatique, de pare-feu ou SELinux
désactivé, de changement de CNI automatique ; aucune modification des équipements externes
(NAS, pare-feu) ; les données (PVC, volumes, sauvegardes, exports) ne sont jamais supprimées
par une désinstallation.

### 6. Idempotence et preuves

Toute commande se relance sans effet de bord ; la CI le vérifie (2e déploiement sans
changement) et déploie réellement ce qui peut l'être sur des runners GitHub : kind avec les
addons, kubeadm multi-OS/HA/mise à niveau/restauration sur des nœuds conteneurs, minikube.
Ce qui ne peut pas l'être (Proxmox, vSphere, libvirt, Vagrant, EKS) est validé
statiquement et indiqué comme tel.

## Pourquoi un CLI Bash + un résolveur Python ?

Le CLI reste lisible par un étudiant (chaque commande exécutée est affichée), tandis que la
logique de validation (réseaux, graphe de dépendances, compatibilité) est testée
unitairement en Python (126 tests, sans réseau ni cluster). PyYAML est la seule dépendance
du résolveur ; `make venv` installe l'environnement épinglé.
