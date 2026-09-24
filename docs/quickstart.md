# Démarrage rapide

Objectif : un cluster Kubernetes qui fonctionne sur votre poste en quelques minutes, puis
quelques exercices pour le prendre en main.

## 1. Installer les outils (une seule fois)

Le mode **Kind** n'a besoin que de trois outils :

| Outil | Rôle | Installation |
| --- | --- | --- |
| Docker | exécute les nœuds du cluster (des conteneurs) | Linux : <https://docs.docker.com/engine/install/> — macOS/Windows : Docker Desktop |
| kind | crée le cluster | <https://kind.sigs.k8s.io/docs/user/quick-start/#installation> |
| kubectl | pilote le cluster | <https://kubernetes.io/docs/tasks/tools/> |

Sous Windows, utilisez WSL2 (Ubuntu) avec Docker Desktop : toutes les commandes ci-dessous se
lancent dans le terminal Ubuntu.

## 2. Vérifier son poste

```bash
git clone https://github.com/vlaine5/k8scluster-eva.git
cd k8scluster-eva
./k8s-lab doctor kind        # ou : make doctor MODE=kind
```

`doctor` indique ce qui manque, **pourquoi** c'est nécessaire et **comment** l'installer.
Sans argument (`./k8s-lab doctor`), il fait le bilan de tous les modes.

## 3. Créer le cluster

```bash
./k8s-lab deploy kind        # ou : make deploy MODE=kind
```

Le script :

1. vérifie les prérequis ;
2. génère la configuration kind (`.lab/kind/kind-config.yaml`) : 1 control-plane + 2 workers ;
3. crée le cluster (`kind create cluster`) ;
4. écrit le kubeconfig dans `.kube/config` (votre `~/.kube/config` n'est pas touché) ;
5. vérifie que tous les nœuds et les Pods système sont prêts.

## 4. Utiliser kubectl

```bash
export KUBECONFIG="$PWD/.kube/config"
kubectl get nodes -o wide
kubectl get pods -A
```

À retenir : le **contexte** (`kubectl config get-contexts`) désigne le cluster ciblé. Chaque
cluster du lab a le sien : `kind-k8s-lab`, `k8s-lab` (minikube), `k8s-lab-vagrant`…

## 5. Premiers exercices

```bash
# Déployer nginx (2 replicas) + un Service
kubectl apply -f examples/namespace.yaml
kubectl apply -f examples/nginx-deployment.yaml -f examples/service.yaml
kubectl -n demo get pods -o wide          # sur quels nœuds tournent les Pods ?

# Kubernetes maintient l'état désiré : supprimez un Pod, il revient
kubectl -n demo delete pod -l app=nginx --wait=false
kubectl -n demo get pods -w               # Ctrl+C pour quitter

# Passer à 5 replicas
kubectl -n demo scale deployment nginx --replicas=5

# Accéder au Service depuis votre navigateur : http://localhost:8080
kubectl -n demo port-forward service/nginx 8080:80

# Tout nettoyer
kubectl delete namespace demo
```

`./k8s-lab test` joue automatiquement un scénario équivalent et vérifie qu'un Pod peut joindre
le Service par son nom DNS (preuve que le réseau du cluster fonctionne).

## 6. Détruire le cluster

```bash
./k8s-lab destroy kind       # ou : make destroy MODE=kind
```

La destruction est **toujours explicite** et demande confirmation. `deploy` ne détruit jamais
un cluster existant : relancé, il se contente de vérifier qu'il fonctionne.

## Et ensuite ?

- Le même exercice avec Minikube et ses addons : [minikube.md](minikube.md)
- Construire un vrai cluster sur des VMs avec kubeadm : [vagrant.md](vagrant.md)
- Pourquoi plusieurs modes ? [modes.md](modes.md)
