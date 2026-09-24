# Exemples Kubernetes

Trois manifestes minimalistes pour vérifier un cluster et découvrir les objets de base.

| Fichier | Objet | À retenir |
| --- | --- | --- |
| `namespace.yaml` | Namespace `demo` | isole les ressources |
| `nginx-deployment.yaml` | Deployment `nginx` (2 replicas) | Kubernetes maintient l'état désiré |
| `service.yaml` | Service `nginx` | adresse et nom DNS stables devant les Pods |

```bash
kubectl apply -f examples/namespace.yaml
kubectl apply -f examples/nginx-deployment.yaml -f examples/service.yaml
kubectl -n demo get pods,services -o wide

# Appeler le Service depuis un autre Pod (DNS + réseau des Pods) :
kubectl -n demo run client --rm -it --restart=Never --image=busybox:1.38 -- wget -qO- http://nginx

# Depuis votre poste :
kubectl -n demo port-forward service/nginx 8080:80   # puis http://localhost:8080

# Expériences :
kubectl -n demo delete pod -l app=nginx              # les Pods sont recréés automatiquement
kubectl -n demo scale deployment nginx --replicas=5  # et répartis sur les workers

# Nettoyage :
kubectl delete namespace demo
```

`./k8s-lab test` automatise ce scénario (et nettoie ensuite).
