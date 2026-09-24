# Kubernetes Lab

Déployez facilement un cluster Kubernetes pour apprendre Kubernetes : en local en une
commande (Kind, Minikube), puis sur de vraies VMs installées avec Ansible et kubeadm
(Vagrant, Proxmox, vSphere, libvirt).

## Démarrage rapide

### Le plus simple : Kind

Il vous faut Docker, `kind` et `kubectl` : `make doctor` vérifie tout et explique comment
installer ce qui manque.

```bash
git clone https://github.com/vlaine5/k8scluster-eva.git
cd k8scluster-eva

make doctor MODE=kind
make deploy MODE=kind

export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
```

Pour supprimer le cluster :

```bash
make destroy MODE=kind
```

Guide pas à pas : [docs/deploy-kind.md](docs/deploy-kind.md).

## Quel mode choisir ?

| Je veux… | Utiliser |
| --- | --- |
| Découvrir Kubernetes rapidement | [Kind](docs/deploy-kind.md) |
| Tester Minikube | [Minikube](docs/deploy-minikube.md) |
| Comprendre kubeadm sur des VMs | [Vagrant](docs/deploy-vagrant.md) |
| Déployer sur mon Proxmox | [Terraform + Proxmox](docs/deploy-proxmox.md) |
| Déployer sur VMware vCenter | [Terraform + vSphere](docs/deploy-vsphere.md) |
| Utiliser des VMs KVM locales | [Terraform + libvirt](docs/deploy-libvirt.md) |

Parcours conseillé : Kind → Minikube → Vagrant → Terraform. Pourquoi ? [docs/modes.md](docs/modes.md).

## Les commandes

| Commande | Effet |
| --- | --- |
| `make doctor MODE=…` | vérifie votre machine et explique quoi installer |
| `make deploy MODE=…` | crée le cluster (ne détruit jamais un cluster existant) |
| `make status` | montre les clusters du lab |
| `make test` | teste le cluster actif (nginx + Service + DNS) |
| `make kubeconfig` | explique comment utiliser `kubectl` avec le lab |
| `make destroy MODE=…` | supprime le cluster (confirmation demandée) |

Modes : `MODE=kind`, `MODE=minikube`, `MODE=vagrant`,
`MODE=terraform PROVIDER=proxmox` (ou `vsphere`, `libvirt`).
Options : `WORKERS=3` (nombre de workers), `RECREATE=1` (recréer le cluster), `YES=1` (sans
question, pour les scripts).

Sans `make`, le même outil s'utilise directement : `./k8s-lab help`. Lancé seul, `./k8s-lab`
ouvre un menu.

Tous les clusters du lab sont rangés dans `.kube/config` (un contexte par cluster) : votre
`~/.kube/config` n'est jamais modifié. Vos réglages et identifiants vont dans un fichier
`.env` (copie de `.env.example`, ignoré par Git).

## État de validation

| Mode | Statut |
| --- | --- |
| Kind | **TESTÉ EN CI** |
| Minikube | **TESTÉ EN CI** |
| Ansible + kubeadm | **TESTÉ EN CI** (sur des nœuds conteneurs) |
| Vagrant | VALIDÉ STATIQUEMENT — TEST D'INTÉGRATION VM À FAIRE |
| Terraform Proxmox | VALIDÉ STATIQUEMENT — TEST SUR PROXMOX RÉEL À FAIRE |
| Terraform vSphere | VALIDÉ STATIQUEMENT — TEST SUR VCENTER RÉEL À FAIRE |
| Terraform libvirt | VALIDÉ STATIQUEMENT — TEST SUR KVM RÉEL À FAIRE |

**TESTÉ EN CI** : à chaque push, GitHub Actions crée réellement le cluster, le teste (nginx,
Service, DNS) puis le supprime. L'installation Ansible + kubeadm est testée avec 1
control-plane + 2 workers simulés par des conteneurs systemd.
**VALIDÉ STATIQUEMENT** : le code est vérifié (`vagrant validate`, `terraform validate`,
TFLint, `terraform test`), mais le déploiement demande une infrastructure réelle que la CI
n'a pas.

## Documentation

Guides étudiants (courts, pas à pas) : [choisir un déploiement](docs/deployment.md), puis
[Kind](docs/deploy-kind.md) · [Minikube](docs/deploy-minikube.md) ·
[Vagrant](docs/deploy-vagrant.md) · [Proxmox](docs/deploy-proxmox.md) ·
[vSphere](docs/deploy-vsphere.md) · [libvirt](docs/deploy-libvirt.md).

Documentation technique :

- [Architecture](docs/architecture.md) — organisation du dépôt et principes
- [Ansible + kubeadm](docs/ansible-kubeadm.md) — ce que fait chaque étape de l'installation
- [Configuration](docs/configuration.md) — toutes les variables
- [Terraform](docs/terraform.md) — utilisation directe, outputs, state, ajout d'un provider
- [Sécurité et secrets](docs/security.md)
- [Dépannage](docs/troubleshooting.md)
- [Maintenance des versions](docs/maintenance.md)
- [Migration depuis la version historique](docs/migration.md)

## Licence

[MIT](LICENSE).
