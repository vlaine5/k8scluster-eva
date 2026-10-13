# Kubernetes Lab

Un framework pour déployer des clusters Kubernetes **reproductibles**, du poste de travail
au homelab : kind ou minikube en local, kubeadm sur des VMs (Vagrant, Proxmox, vSphere,
libvirt) ou sur vos propres machines, Kubernetes managé (AWS EKS), ou simplement des
addons sur un cluster existant. Tout est piloté par un fichier `.env` validé **avant**
d'agir.

```text
.env ─► résolveur (validation, plan) ─► Terraform / Vagrant / kind / minikube
                                          ─► Ansible + kubeadm (multi-OS, HA, CNI)
                                          ─► addons (moteur unique, testés)
                                          ─► validation (tests, santé, manifeste)
```

## Démarrage rapide

Il vous faut Docker, `kind`, `kubectl`, `helm` et Python 3 : `make doctor` vérifie tout et
explique comment installer ce qui manque (`scripts/install-tools.sh`, `make venv`).

```bash
git clone https://github.com/vlaine5/k8scluster-eva.git && cd k8scluster-eva
make venv                       # Ansible et dépendances Python épinglées (.venv)
make doctor MODE=kind
make deploy MODE=kind
export KUBECONFIG="$PWD/.kube/config"
kubectl get nodes
make destroy MODE=kind
```

Avec des addons : `make deploy MODE=kind ADDONS=metrics-server,cert-manager`, ou un profil
complet : `LAB_ENV_FILE=examples/profiles/kind-observability.env make deploy`.

## Modes

| Mode | Commande | Ce qui est créé | Guide |
| --- | --- | --- | --- |
| kind | `MODE=kind` | nœuds = conteneurs Docker | [deploy-kind.md](docs/deploy-kind.md) |
| minikube | `MODE=minikube` | conteneur ou VM locale | [deploy-minikube.md](docs/deploy-minikube.md) |
| Vagrant | `MODE=vagrant` | VMs locales + kubeadm | [deploy-vagrant.md](docs/deploy-vagrant.md) |
| Proxmox | `MODE=terraform PROVIDER=proxmox` | VMs Proxmox + kubeadm | [deploy-proxmox.md](docs/deploy-proxmox.md), [homelab-pv05.md](docs/homelab-pv05.md) |
| vSphere | `MODE=terraform PROVIDER=vsphere` | VMs vCenter + kubeadm | [deploy-vsphere.md](docs/deploy-vsphere.md) |
| libvirt | `MODE=terraform PROVIDER=libvirt` | VMs KVM + kubeadm | [deploy-libvirt.md](docs/deploy-libvirt.md) |
| existing | `MODE=existing` | rien : kubeadm sur **vos** machines (inventaire) | [existing-mode.md](docs/existing-mode.md) |
| attach | `MODE=attach` | rien : addons sur un cluster **existant** | [attach-mode.md](docs/attach-mode.md) |
| EKS | `MODE=terraform PROVIDER=eks` | Kubernetes managé AWS (payant) | [deploy-eks.md](docs/deploy-eks.md) |

Comparaison et parcours conseillé : [modes.md](docs/modes.md).

## Ce que le framework sait faire

- **Nœuds** : Ubuntu 24.04/26.04, Debian 12/13, Rocky Linux 9/10 ([os.md](docs/os.md)) ;
  1, 3 ou 5 control-planes avec VIP kube-vip ([high-availability.md](docs/high-availability.md)).
- **Réseau** : Flannel, Calico, Cilium (avec ou sans kube-proxy) ou votre CNI
  ([cni.md](docs/cni.md)) ; Gateway API avec Traefik, Envoy Gateway ou Cilium
  ([gateway-api.md](docs/gateway-api.md)) ; LoadBalancer MetalLB ou Cilium L2/BGP
  ([loadbalancer.md](docs/loadbalancer.md)).
- **Stockage** : NFS CSI (NAS existant) et Longhorn sur disques dédiés
  ([storage.md](docs/storage.md)).
- **Addons** : un catalogue déclaratif de 31 addons (certificats, supervision, journaux,
  traces, GitOps, politiques, sécurité, sauvegardes, maillage…), profils `minimal`,
  `homelab`, `observability`, `enterprise-lab`, dépendances et ordre calculés, test
  fonctionnel pour chacun ([addons.md](docs/addons.md)).
- **Exploitation** : mises à niveau planifiées de Kubernetes et des addons, mises à jour de
  l'OS nœud par nœud, sauvegarde et restauration etcd, Velero, santé, retrait de nœud
  ([day2.md](docs/day2.md)).

## Commandes

| Commande | Effet |
| --- | --- |
| `make doctor` | vérifie les outils, l'accès à l'infrastructure et la configuration |
| `make config` · `make validate` | configuration résolue et vérifiée (lecture seule) |
| `make deploy` | crée ou complète le cluster, puis installe et teste les addons |
| `make status` · `make test` · `make kubeconfig` | état, test applicatif, accès `kubectl` |
| `make destroy` | supprime un cluster créé par le lab (confirmation ; refusé en modes existing et attach) |
| `make addons-plan` · `addons-apply` · `addons-status` · `addons-test` · `addons-upgrade` · `addons-remove` | cycle de vie des addons |
| `make upgrade-plan` · `upgrade` · `os-update` · `backup` · `restore` · `health` · `node-remove` | exploitation des clusters kubeadm |

Le mode vient de `MODE=` ou de `DEPLOYMENT_MODE` dans `.env`. Sans `make` :
`./k8s-lab help` ; lancé seul, `./k8s-lab` ouvre un menu. Chaque commande exécutée est
affichée.

## Configuration et sécurité

- `config/lab.env` : toutes les valeurs par défaut, commentées ; `.env` (non versionné) :
  vos réglages et **vos secrets** ; `LAB_ENV_FILE=…` : un autre fichier (profils de
  [examples/profiles](examples/profiles/README.md)). Référence : [configuration.md](docs/configuration.md).
- Versions verrouillées dans `config/versions.yaml` (SHA-256 de chaque téléchargement,
  jamais `latest`) : [versions.md](docs/versions.md).
- Rien de destructif sans confirmation ; jamais de formatage d'un disque non vide, de
  `kubeadm reset` automatique, de modification d'un équipement externe (NAS, pare-feu) ; une
  désinstallation ne supprime jamais de données ([security.md](docs/security.md)).

## État de validation

**Testé en CI** signifie que GitHub Actions déploie réellement le cluster, installe les
addons et exécute leurs tests fonctionnels à chaque push.

| Élément | Statut |
| --- | --- |
| Résolveur, catalogue, rendu de chaque addon et des rôles kubeadm (helm template, Pod Security), Terraform (tests avec API simulées), Ansible (lint) | testés en CI (statique) |
| kind, minikube (commandes des guides) | testés en CI |
| kind + addons : sécurité (Kyverno enforce, Falco, Trivy, Istio), Cilium sans kube-proxy (Gateway, LB L2, Hubble, Tetragon), observabilité (Prometheus, Grafana, Loki, Tempo, OpenTelemetry), réseau (Envoy Gateway, MetalLB, cert-manager, External Secrets, Reloader) | **testés en CI** : déploiement, tests fonctionnels, état, 2e installation sans changement |
| kind + addons : stockage (NFS CSI, snapshots, Velero, Argo CD, KEDA, Descheduler, NFD) | en cours de validation en CI (Velero) |
| mode attach (refus de reprendre un composant d'un autre outil, `skip`, idempotence, destroy refusé) | **testé en CI** |
| kubeadm sur nœuds conteneurs (mode existing) : Ubuntu, Debian, Rocky, Flannel/Calico/Cilium, HA, mise à niveau, restauration | contrôles préalables et `kubeadm init` validés en CI ; cluster complet en cours de validation |
| Vagrant, Proxmox, vSphere, libvirt, EKS | **validés statiquement uniquement** : aucun déploiement réel par la CI |
| Longhorn (disques, réplicas, perte de nœud) | rendu vérifié ; nécessite des VMs (non testé en CI) |

La colonne « Testé en CI » de [compatibility.md](docs/compatibility.md) est générée depuis
le catalogue : elle ne mentionne que les environnements effectivement couverts.

## Documentation

Index complet : [docs/README.md](docs/README.md) — architecture, guides par mode,
configuration, addons, exploitation, dépannage, [migration](docs/migration.md).

## Licence

[MIT](LICENSE).
