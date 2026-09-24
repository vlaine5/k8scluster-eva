# Mode Minikube

[Minikube](https://minikube.sigs.k8s.io/) crée un cluster local orienté « poste de
développeur » : addons prêts à l'emploi, tableau de bord, choix du driver.

## Prérequis

- `minikube` (conseillé : v1.39.0) et `kubectl`
- Un **driver** : Docker (le plus simple), Podman, KVM (`kvm2`), VirtualBox, ou vfkit/qemu sur macOS

```bash
./k8s-lab doctor minikube
```

## Utilisation

```bash
./k8s-lab deploy minikube
./k8s-lab destroy minikube
```

Le CLI lance l'équivalent de :

```bash
KUBECONFIG=.kube/config minikube start --profile k8s-lab --kubernetes-version v1.37.0 \
  --nodes 1 --cpus 2 --memory 2048 --wait all
```

Réglages (`.env`) : `MINIKUBE_DRIVER` (vide = automatique), `MINIKUBE_NODES`,
`MINIKUBE_CPUS`, `MINIKUBE_MEMORY_MB`, `MINIKUBE_EXTRA_ARGS` (ex :
`--addons=ingress,metrics-server`). Le profil et le contexte kubectl s'appellent
`CLUSTER_NAME` (`k8s-lab`).

## À essayer

```bash
minikube dashboard --profile k8s-lab           # interface web
minikube addons list --profile k8s-lab
minikube addons enable ingress --profile k8s-lab
minikube ssh --profile k8s-lab                 # dans le nœud : sudo crictl ps
minikube service list --profile k8s-lab
```

## Kind ou Minikube ?

Les deux fournissent un Kubernetes local complet. Kind est plus léger et plus rapide
(idéal pour la CI et les clusters multi-nœuds jetables) ; Minikube offre plus d'outillage
(addons, dashboard, drivers VM). Voir [modes.md](modes.md).

## État de validation

- Implémenté et testé par la CI GitHub Actions (job `e2e-minikube`, driver docker).
- Dans l'environnement de développement de cette refonte (hôte cgroup v1, capacités
  restreintes), minikube n'a pas pu démarrer le control-plane : c'est une limite de cet
  environnement, détectée par `./k8s-lab doctor` (« Docker utilise cgroup v1 »).
