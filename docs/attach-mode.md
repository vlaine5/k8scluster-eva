# Mode attach : addons sur un cluster existant

Le mode `attach` n'installe **que des addons** sur un cluster Kubernetes qui existe déjà
(k3s, RKE2, kubeadm, EKS, AKS, GKE, Talos…). Il ne touche jamais aux nœuds, au système, à
kubeadm, à containerd ni au CNI.

```bash
# .env
DEPLOYMENT_MODE=attach
EXISTING_KUBECONFIG=~/.kube/homelab.yaml
EXISTING_CONTEXT=homelab-admin      # toujours explicite : jamais le contexte « courant »
ADDONS=cert-manager,metrics-server,argo-cd,monitoring
EXISTING_ADDON_POLICY=fail          # fail (défaut) | skip
```

```bash
make doctor MODE=attach             # outils, kubeconfig, contexte joignable
make addons-plan MODE=attach        # plan (avant détection)
make addons-apply MODE=attach       # détection, refus des conflits, installation
make addons-status MODE=attach
make addons-test MODE=attach
```

## Détection (lecture seule)

Avant toute installation, `scripts/labctl detect` inventorie le cluster :

- version et distribution (k3s, RKE2, EKS, GKE, Talos, kind, minikube, kubeadm) ;
- CNI (DaemonSets connus), kube-proxy, ServiceLB (k3s) ;
- StorageClasses (et celle par défaut) ;
- CRD Gateway API (version du bundle), cert-manager, Prometheus Operator, Argo CD… ;
- releases Helm (Secrets `sh.helm.release.v1`) et applications Argo CD ;
- addons déjà installés **par le framework** (ConfigMap `k8s-lab-system/k8s-lab-addons`).

```bash
python3 scripts/labctl detect --kubeconfig ~/.kube/homelab.yaml --context homelab-admin
```

## Règles

| Situation | Comportement |
| --- | --- |
| addon déjà installé par le framework | mis à jour normalement |
| addon présent, installé par un autre outil | **refus** (`EXISTING_ADDON_POLICY=fail`) ou utilisé tel quel sans être géré (`skip`) |
| addon géré par Argo CD | **toujours refusé** : le framework ne reprend jamais des ressources GitOps |
| MetalLB demandé, ServiceLB (k3s) actif | refus : deux fournisseurs LoadBalancer |
| Traefik demandé sur k3s/RKE2 | refus : Traefik est déjà fourni ; utilisez Envoy Gateway ou désactivez celui de k3s |
| CRD Gateway API plus anciennes que requises | refus : mettre à jour des CRD d'un autre outil est une migration |
| addons exigeant le CNI (Cilium Gateway, Hubble, Cilium LB) | non supportés en attach |
| Longhorn | expérimental : les prérequis des nœuds sont vérifiés, pas installés |

Les manifestes sont appliqués en *server-side apply* (gestionnaire `k8s-lab`) : un champ
possédé par un autre outil provoque un conflit au lieu d'être écrasé.

## Désinstaller

`make destroy MODE=attach` est refusé (le cluster n'appartient pas au framework).
`make addons-remove MODE=attach ADDON=...` retire un addon installé par le framework ; les
données et les CRD sont conservées.
