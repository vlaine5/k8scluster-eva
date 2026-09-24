# Minikube

Minikube n'a pas besoin de fichier de configuration : `make deploy MODE=minikube` lance
l'équivalent de :

```bash
minikube start --profile k8s-lab --kubernetes-version v1.37.0 --nodes 1 --cpus 2 --memory 2048 --wait all
```

Les valeurs viennent de `config/lab.env` (`MINIKUBE_*`). Options supplémentaires :
`MINIKUBE_EXTRA_ARGS="--addons=ingress,metrics-server"` dans `.env`.

Guide : [docs/deploy-minikube.md](../../docs/deploy-minikube.md).
