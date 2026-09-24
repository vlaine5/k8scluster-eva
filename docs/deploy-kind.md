# Mode Kind

[kind](https://kind.sigs.k8s.io/) (*Kubernetes IN Docker*) crée un cluster dont chaque nœud est
un conteneur Docker. C'est le chemin le plus rapide pour découvrir Kubernetes, et celui que
la CI du dépôt teste à chaque push.

## Prérequis

- Docker (démon démarré) — ou Podman avec `KIND_EXPERIMENTAL_PROVIDER=podman`
- `kind` (conseillé : v0.33.0) et `kubectl`
- Un hôte en **cgroup v2** (toute distribution récente, Docker Desktop, WSL2 à jour) :
  Kubernetes ≥ 1.35 refuse par défaut de démarrer sur cgroup v1.

```bash
./k8s-lab doctor kind
```

## Utilisation

```bash
./k8s-lab deploy kind          # 1 control-plane + WORKER_COUNT workers (2 par défaut)
./k8s-lab status
./k8s-lab test                 # nginx + Service + DNS
./k8s-lab destroy kind
```

Changer le nombre de workers : `WORKER_COUNT=1 ./k8s-lab deploy kind` (ou dans `.env`).
Si le cluster existe déjà, `deploy` ne le recrée pas : utilisez `--recreate` (confirmation
demandée) après avoir changé `WORKER_COUNT`.

## Ce que fait le CLI

1. Génère `.lab/kind/kind-config.yaml` depuis `config/lab.env` (`./k8s-lab config kind`
   l'affiche). Avec les valeurs par défaut, c'est exactement
   [`local/kind/kind-config.yaml`](../local/kind/kind-config.yaml).
2. `kind create cluster --config … --kubeconfig .kube/config --wait 5m`
3. Vérifie nœuds et Pods système (`kubectl wait`).

Équivalent manuel :

```bash
kind create cluster --config local/kind/kind-config.yaml
kubectl get nodes
kind delete cluster --name k8s-lab
```

## Points pédagogiques

- `docker ps` montre les nœuds : `k8s-lab-control-plane`, `k8s-lab-worker`, `k8s-lab-worker2`.
- `docker exec -it k8s-lab-control-plane crictl ps` : les conteneurs vus par le kubelet.
- Le CNI de kind s'appelle **kindnet** ; le réseau des Pods utilise `POD_CIDR` (10.244.0.0/16),
  comme le cluster kubeadm du lab.
- L'image de nœud est épinglée **par digest** : `kindest/node:v1.37.0@sha256:…`. Une nouvelle
  version de kind publie une liste d'images associées dans ses notes de version.

## Limites

- Pas de `LoadBalancer` natif (utilisez `kubectl port-forward` ou le projet
  [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind)).
- Les nœuds partagent le noyau de l'hôte : ce n'est pas un cluster « comme en production ».
