# Déployer Kubernetes avec Minikube

Minikube fournit un environnement Kubernetes local avec des fonctionnalités pratiques pour
apprendre : addons prêts à l'emploi (tableau de bord, ingress…), plusieurs drivers.
Kind est plus léger ; Minikube est plus « outillé ».

## Ce que vous allez obtenir

- 1 nœud qui est à la fois control-plane et worker
- Kubernetes 1.37
- un réseau des Pods fourni par Minikube
- les addons Minikube (`minikube addons list`)

## Prérequis

- `minikube` et `kubectl`
- Docker, démarré : c'est le driver le plus simple (Minikube sait aussi utiliser KVM,
  VirtualBox, Podman…)

Il vous manque `minikube` ou `kubectl` ? `scripts/install-tools.sh minikube kubectl` les
installe dans `~/.local/bin`, sans sudo (Linux et macOS).

## 1. Vérifier votre machine

```bash
make doctor MODE=minikube
```

## 2. Configurer

Rien d'obligatoire. Pour imposer le driver Docker, créez un fichier `.env` :

```bash
cp .env.example .env
# puis décommentez la ligne : MINIKUBE_DRIVER=docker
```

## 3. Déployer

```bash
make deploy MODE=minikube
```

Comptez 2 à 5 minutes au premier lancement (téléchargement des images).

## 4. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
kubectl get pods -A
```

Le nœud `k8s-lab` est `Ready`.

## 5. Tester

```bash
make test
```

`make test` teste le cluster **actif** : le dernier que vous avez déployé.

## 6. Supprimer

```bash
make destroy MODE=minikube
```

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| `doctor` : Docker introuvable, ou Docker ne répond pas | installez ou démarrez Docker ; sous Linux, pour l'utiliser sans sudo : `sudo usermod -aG docker $USER`, puis reconnectez-vous |
| `The "docker" driver should not be used with root privileges` | lancez la commande avec votre utilisateur, pas en root |
| Minikube choisit un driver inattendu | `MINIKUBE_DRIVER=docker` dans `.env` |
| Le démarrage échoue | `minikube logs --profile k8s-lab`, puis `make destroy MODE=minikube` et `make deploy MODE=minikube` |
| `The connection to the server localhost:8080 was refused` | vous avez oublié `export KUBECONFIG="$PWD/.kube/config"` |

Plus de cas : [troubleshooting.md](troubleshooting.md).

## Pour aller plus loin

```bash
minikube dashboard --profile k8s-lab            # interface web
minikube addons enable ingress --profile k8s-lab
minikube ssh --profile k8s-lab                  # dans le nœud : sudo crictl ps
```

- Réglages disponibles dans `.env` : `MINIKUBE_NODES`, `MINIKUBE_CPUS`, `MINIKUBE_MEMORY_MB`,
  `MINIKUBE_EXTRA_ARGS` (ex : `--addons=ingress,metrics-server`). Voir
  [configuration.md](configuration.md).
- Le CLI lance `minikube start --profile k8s-lab --kubernetes-version v1.37.0 …` : la commande
  exacte est affichée pendant le déploiement.
- Étape suivante : un vrai cluster kubeadm sur des VMs avec [Vagrant](deploy-vagrant.md).

**Statut : TESTÉ EN CI** (driver docker : déploiement réel, test nginx, suppression).
