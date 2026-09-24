# Déployer Kubernetes avec Kind

Kind exécute les nœuds Kubernetes dans des **conteneurs Docker**.
C'est le moyen recommandé pour commencer.

## Ce que vous allez obtenir

- 1 control-plane
- 2 workers
- Kubernetes 1.37, prêt en 1 à 2 minutes
- un réseau des Pods déjà en place (kindnet, fourni par Kind)

## Prérequis

- Docker, démarré (Docker Desktop sous macOS/Windows ; sous Windows, travaillez dans WSL2)
- `kind` et `kubectl`

Il vous manque `kind` ou `kubectl` ? `scripts/install-tools.sh kind kubectl` les installe
dans `~/.local/bin`, sans sudo (Linux et macOS).

## 1. Vérifier votre machine

```bash
make doctor MODE=kind
```

## 2. Configurer

Rien à configurer : les valeurs par défaut conviennent.

## 3. Déployer

```bash
make deploy MODE=kind
```

## 4. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
kubectl get pods -A
```

Les 3 nœuds (`k8s-lab-control-plane`, `k8s-lab-worker`, `k8s-lab-worker2`) sont `Ready`.

## 5. Tester

```bash
make test
```

Le test déploie nginx, un Service, vérifie que le DNS du cluster répond, puis nettoie.

## 6. Supprimer

```bash
make destroy MODE=kind
```

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| `doctor` : Docker introuvable, ou Docker ne répond pas | installez ou démarrez Docker ; sous Linux, pour l'utiliser sans sudo : `sudo usermod -aG docker $USER`, puis reconnectez-vous |
| `Docker utilise cgroup v1` | Kubernetes 1.37 exige cgroup v2 : distribution récente, Docker Desktop ou WSL2 à jour |
| `The connection to the server localhost:8080 was refused` | vous avez oublié `export KUBECONFIG="$PWD/.kube/config"` |
| Le cluster `k8s-lab` existe déjà | c'est normal : `deploy` ne détruit jamais un cluster ; pour le recréer : `make deploy MODE=kind RECREATE=1` |
| Machine lente ou peu de RAM | un seul worker : `make deploy MODE=kind WORKERS=1` (ajoutez `RECREATE=1` si le cluster existe déjà) |

Plus de cas : [troubleshooting.md](troubleshooting.md).

## Pour aller plus loin

- Les nœuds sont des conteneurs : `docker ps`, puis
  `docker exec -it k8s-lab-control-plane crictl ps` pour voir les conteneurs lancés par le kubelet.
- Le CLI affiche chaque commande exécutée. L'équivalent manuel est :
  `kind create cluster --config local/kind/kind-config.yaml` puis
  `kind delete cluster --name k8s-lab`.
- `./k8s-lab config kind` affiche la configuration Kind générée avec vos réglages.
- Des exercices avec nginx : [examples/README.md](../examples/README.md).
- Limites : pas de Service `LoadBalancer` natif (utilisez `kubectl port-forward`), et les
  nœuds partagent le noyau de votre machine.
- Étape suivante : [Minikube](deploy-minikube.md), puis un vrai cluster kubeadm sur des VMs
  avec [Vagrant](deploy-vagrant.md).

**Statut : TESTÉ EN CI** (déploiement réel, second `deploy` sans effet, test nginx, suppression).
