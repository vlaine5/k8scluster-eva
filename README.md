# k8s-lab — Kubernetes Deployment Lab

Un laboratoire pour **créer un cluster Kubernetes de plusieurs façons** et comprendre,
étape par étape, ce qu'il y a sous le capot : du cluster local en une commande jusqu'au
cluster `kubeadm` sur des VMs créées par Terraform.

```bash
git clone https://github.com/vlaine5/k8scluster-eva.git
cd k8scluster-eva

make doctor              # vérifie ce qui est installé sur votre poste
make deploy MODE=kind    # premier cluster en ~1 minute

export KUBECONFIG="$PWD/.kube/config"
kubectl get nodes
kubectl get pods -A
```

> Pas de `make` ? Tout passe par le même script : `./k8s-lab doctor`, `./k8s-lab deploy kind`.
> Et `./k8s-lab` tout seul ouvre un **menu interactif**.

## Quel mode choisir ?

| Je veux… | Mode | Commande |
| --- | --- | --- |
| Kubernetes en 5 minutes | **Kind** | `make deploy MODE=kind` |
| Découvrir Minikube et ses addons | **Minikube** | `make deploy MODE=minikube` |
| Apprendre Vagrant + Ansible + kubeadm | **Vagrant** | `make deploy MODE=vagrant` |
| J'ai un Proxmox | **Terraform + Proxmox** | `make deploy MODE=terraform PROVIDER=proxmox` |
| J'ai un VMware vCenter | **Terraform + vSphere** | `make deploy MODE=terraform PROVIDER=vsphere` |
| J'ai un PC Linux avec KVM | **Terraform + libvirt** | `make deploy MODE=terraform PROVIDER=libvirt` |

| Mode | Infrastructure | Kubernetes installé par | Niveau | Guide |
| --- | --- | --- | --- | --- |
| Kind | conteneurs Docker | kind | débutant | [docs/kind.md](docs/kind.md) |
| Minikube | conteneur ou VM locale | minikube | débutant | [docs/minikube.md](docs/minikube.md) |
| Vagrant | VMs locales (VirtualBox, libvirt, VMware) | Ansible + kubeadm | intermédiaire | [docs/vagrant.md](docs/vagrant.md) |
| Terraform Proxmox | VMs Proxmox VE | Ansible + kubeadm | intermédiaire / avancé | [docs/terraform-proxmox.md](docs/terraform-proxmox.md) |
| Terraform vSphere | VMs VMware vCenter | Ansible + kubeadm | intermédiaire / avancé | [docs/terraform-vsphere.md](docs/terraform-vsphere.md) |
| Terraform libvirt | VMs KVM sur votre PC Linux | Ansible + kubeadm | intermédiaire / avancé | [docs/terraform-libvirt.md](docs/terraform-libvirt.md) |

Par défaut, chaque cluster a **1 control-plane + 2 workers** (sauf Minikube : 1 nœud).
Le nombre de workers se change en une variable : `make deploy MODE=vagrant WORKERS=3`.

## Une progression en trois niveaux

```text
Niveau 1 — découverte            Niveau 2 — Kubernetes sur VMs      Niveau 3 — Infrastructure as Code
Kind, Minikube                   Vagrant + Ansible + kubeadm        Terraform + Ansible + kubeadm
─────────────────────            ───────────────────────────        ─────────────────────────────────
kubectl, Pods, Deployments,      control-plane, workers, CNI,       VMs décrites en code, inventaire
Services, namespaces             containerd, kubelet, kubeadm       généré, Proxmox / vSphere / KVM
```

1. **Niveau 1** : on apprend à *utiliser* Kubernetes. Kind et Minikube cachent l'installation.
2. **Niveau 2** : on voit *comment on construit* un cluster : de vraies VMs, un runtime
   (containerd), `kubeadm init` sur le control-plane, `kubeadm join` sur les workers, un CNI.
3. **Niveau 3** : les VMs sont décrites en code (Terraform). Terraform crée l'infrastructure,
   génère l'inventaire, **le même Ansible** installe Kubernetes.

Comparaison détaillée et conseils pédagogiques : [docs/modes.md](docs/modes.md).

## Les commandes

| `make …` | `./k8s-lab …` | Effet |
| --- | --- | --- |
| `make help` | `./k8s-lab help` | aide |
| — | `./k8s-lab` | menu interactif |
| `make doctor [MODE=…]` | `./k8s-lab doctor [mode]` | vérifie les prérequis et explique comment les installer |
| `make deploy MODE=…` | `./k8s-lab deploy <mode>` | crée le cluster (**ne détruit jamais** l'existant) |
| `make status` | `./k8s-lab status` | clusters existants, contexte kubectl actif |
| `make kubeconfig` | `./k8s-lab kubeconfig` | comment utiliser kubectl avec le lab |
| `make test` | `./k8s-lab test` | test applicatif : nginx + Service + DNS |
| `make destroy MODE=…` | `./k8s-lab destroy <mode>` | détruit le cluster (confirmation demandée) |

Pour Terraform, ajoutez le provider : `PROVIDER=proxmox` (make) ou `terraform proxmox` (CLI).
Options utiles : `YES=1` / `--yes` (pas de question, pour la CI), `RECREATE=1` / `--recreate`
(détruire puis recréer, après confirmation).

Chaque commande **affiche les vraies commandes exécutées** (`kind`, `vagrant`, `terraform`,
`ansible-playbook`, `kubectl`) : le but est de les comprendre, puis de savoir s'en passer.

## kubectl et le kubeconfig

Votre `~/.kube/config` n'est **jamais modifié**. Tous les clusters du lab sont rangés dans
`.kube/config` (dans le dépôt, ignoré par Git), un contexte par cluster :

```bash
export KUBECONFIG="$PWD/.kube/config"
kubectl config get-contexts        # kind-k8s-lab, k8s-lab-vagrant, k8s-lab-proxmox...
kubectl config use-context k8s-lab-vagrant
```

## Configuration

Tout se règle dans **un seul fichier** : `config/lab.env` (valeurs par défaut, versionnées).
Pour vos réglages et vos secrets, copiez `.env.example` en `.env` (ignoré par Git) :

```bash
cp .env.example .env
# puis par exemple : WORKER_COUNT=3, NODE_MEMORY_MB=4096, identifiants Proxmox...
```

Correspondance avec Terraform, Ansible, Vagrant et Kind : [docs/configuration.md](docs/configuration.md).

## Organisation du dépôt

```text
k8s-lab                 le CLI (menu, deploy, destroy, doctor…) — Makefile = raccourcis
config/lab.env          LA configuration par défaut (versions, taille du cluster, réseaux)
local/                  modes locaux : config Kind versionnée, notes Minikube
vagrant/Vagrantfile     VMs Vagrant (VirtualBox, libvirt, VMware, ESXi historique)
terraform/modules/      logique commune : nœuds, IP, cloud-init, inventaire Ansible
terraform/providers/    proxmox/, vsphere/, libvirt/ : uniquement la création des VMs
ansible/                installation de Kubernetes avec kubeadm (commune à Vagrant et Terraform)
examples/               manifestes simples pour tester un cluster (nginx)
tests/                  test d'intégration Ansible + kubeadm (nœuds conteneurs, utilisé en CI)
docs/                   la documentation détaillée
```

Le principe clé : **les outils d'infrastructure créent les VMs, Ansible installe Kubernetes.**

```text
Vagrant ─┐                     ┌─> inventaire Ansible ─> Ansible + kubeadm ─> Kubernetes
Terraform┴─> VMs + IP statiques┘   (généré, jamais recopié à la main)
```

Détails : [docs/architecture.md](docs/architecture.md).

## Versions utilisées

Vérifiées en septembre 2026, toutes épinglées dans `config/lab.env` (rien en `latest` ni `master`) :

| Composant | Version |
| --- | --- |
| Kubernetes (kubeadm, VMs) | 1.37.1 — dépôt officiel `pkgs.k8s.io` |
| Kind / image de nœud | kind v0.33.0 / `kindest/node:v1.37.0` (épinglée par digest) |
| Minikube | v1.39.0, Kubernetes v1.37.0 |
| OS des VMs | Ubuntu 24.04 LTS (image cloud datée, SHA-256 vérifié) |
| containerd | 2.3.x (paquet `containerd.io`), driver cgroup systemd, cgroup v2 |
| CNI | Flannel v0.28.9 (manifeste de release, SHA-256 vérifié) |
| Terraform | ≥ 1.9 (testé avec 1.16.4) — OpenTofu compatible |
| Providers Terraform | `bpg/proxmox` 0.114, `vmware/vsphere` 2.17, `dmacvicar/libvirt` 0.9.9 |
| Ansible | ansible-core ≥ 2.18 (testé avec 2.21) |

Mettre à jour une version : [docs/maintenance.md](docs/maintenance.md).

## État de validation

| Mode | Statut |
| --- | --- |
| Kind | **testé** : déploiement réel + redéploiement idempotent + test nginx, en local et en CI (GitHub Actions) |
| Minikube | **testé en CI** (GitHub Actions, driver docker : déploiement + test nginx) ; voir [docs/minikube.md](docs/minikube.md#état-de-validation) |
| Ansible + kubeadm | **testé en CI** sur des nœuds conteneurs systemd Ubuntu 24.04 (cgroup v2, driver systemd) : init, Flannel, join, idempotence, test nginx ; voir [docs/ansible-kubeadm.md](docs/ansible-kubeadm.md#état-de-validation) |
| Vagrant | implémenté — Vagrantfile validé (`vagrant validate`, génération d'inventaire) ; **nécessite un test d'intégration** sur une machine avec VirtualBox/libvirt |
| Terraform Proxmox | implémenté — validé statiquement + `terraform plan` ; **nécessite un test d'intégration** sur un Proxmox |
| Terraform vSphere | implémenté — validé statiquement ; **nécessite un test d'intégration** sur un vCenter |
| Terraform libvirt | implémenté — validé statiquement ; **nécessite un test d'intégration** sur un hôte KVM |

## Documentation

- [Démarrage rapide](docs/quickstart.md) — premier cluster et premiers exercices
- [Choisir un mode](docs/modes.md) — Kind vs Minikube vs kubeadm sur VMs
- [Architecture](docs/architecture.md) — organisation et principes du dépôt
- [Configuration](docs/configuration.md) — toutes les variables
- [Ansible + kubeadm](docs/ansible-kubeadm.md) — ce que fait chaque étape
- Modes : [Kind](docs/kind.md) · [Minikube](docs/minikube.md) · [Vagrant](docs/vagrant.md) ·
  [Terraform](docs/terraform.md) ([Proxmox](docs/terraform-proxmox.md), [vSphere](docs/terraform-vsphere.md), [libvirt](docs/terraform-libvirt.md))
- [Sécurité et secrets](docs/security.md)
- [Dépannage](docs/troubleshooting.md)
- [Maintenance des versions](docs/maintenance.md)
- [Migration depuis la version historique](docs/migration.md)
