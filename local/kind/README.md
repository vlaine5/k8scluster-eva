# Kind — configuration versionnée

`kind-config.yaml` est la configuration **par défaut** du lab : 1 control-plane + 2 workers,
image de nœud épinglée par digest. `./k8s-lab deploy kind` génère la même configuration à partir
de `config/lab.env` (en tenant compte de `WORKER_COUNT`) dans `.lab/kind/kind-config.yaml`.

Équivalent manuel, pour comprendre ce que fait le CLI :

```bash
kind create cluster --config local/kind/kind-config.yaml
kubectl get nodes
kind delete cluster --name k8s-lab
```

Afficher la configuration générée avec vos réglages : `./k8s-lab config kind`.
Utiliser votre propre fichier : `KIND_CONFIG=chemin/vers/config.yaml ./k8s-lab deploy kind`.

Documentation : [docs/kind.md](../../docs/kind.md).
