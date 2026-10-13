# Réseau des Pods (CNI)

Le CNI donne une IP à chaque Pod et relie les Pods de tous les nœuds. Sans CNI, les nœuds
restent `NotReady`. Le lab propose trois CNI pour les modes kubeadm (vagrant, terraform,
existing) et sur kind ; minikube, EKS et le mode attach utilisent celui de leur plateforme.

| `CNI` | Installé par | Points forts | À savoir |
| --- | --- | --- | --- |
| `flannel` (défaut kubeadm) | manifeste officiel épinglé + SHA-256 | simple, léger | **n'applique aucune NetworkPolicy** |
| `calico` | opérateur Tigera (chart `tigera-operator`) | NetworkPolicy, BGP | plus de composants |
| `cilium` | chart Helm officiel | eBPF, remplacement de kube-proxy, Gateway API, LoadBalancer L2/BGP, Hubble | noyau ≥ 5.10 |
| `none` | vous | — | nœuds `NotReady` et addons non installés tant qu'aucun CNI n'est posé |
| `auto` | — | `flannel` (kubeadm), `kindnet` (kind), natif (minikube), AWS VPC CNI (EKS) | |

```bash
CNI=cilium
CNI_MODE=auto            # vxlan (défaut), native (routage direct, réseau L2 commun requis)
KUBE_PROXY_MODE=auto     # cilium avec CNI=cilium (eBPF, plus de kube-proxy) ; iptables sinon
NETWORK_POLICY_MODE=auto # cilium / calico / kubernetes (kindnet) / none (flannel)
ENABLE_HUBBLE=false
```

## Modes réseau (`CNI_MODE`)

| CNI | Modes | Défaut |
| --- | --- | --- |
| Flannel | `vxlan`, `host-gw` | `vxlan` |
| Calico | `vxlan`, `vxlan-crosssubnet`, `ipip`, `ipip-crosssubnet`, `bgp`, `direct` | `vxlan` |
| Cilium | `vxlan`, `geneve`, `native` | `vxlan` |

Les modes sans encapsulation (`host-gw`, `direct`, `native`) exigent que tous les nœuds
soient sur le même réseau L2, ou que votre routeur connaisse les réseaux des Pods. Sur un
homelab avec un pare-feu entre VLAN (Stormshield...), gardez `vxlan` : aucune route n'est
ajoutée automatiquement à vos équipements.

## kube-proxy

`KUBE_PROXY_MODE` : `iptables` (défaut), `nftables`, `ipvs` (déprécié depuis Kubernetes
1.35, avertissement) ou `cilium`. Avec `cilium`, kubeadm n'installe pas kube-proxy
(`skipPhases: addon/kube-proxy`) et Cilium joint l'API par l'adresse stable du
control-plane (VIP en HA) : le remplacement de kube-proxy est requis par la Gateway API et
le LoadBalancer de Cilium.

## NetworkPolicy

Avec **Flannel**, les objets `NetworkPolicy` sont acceptés par l'API mais **ignorés** : le
résolveur refuse `NETWORK_POLICY_MODE=kubernetes` avec Flannel pour ne pas donner une fausse
impression de sécurité. Choisissez Calico ou Cilium pour isoler les applications.

## Hubble

<a id="hubble"></a>`ENABLE_HUBBLE=true` (CNI Cilium) active Hubble et Hubble Relay dans la
configuration de Cilium (et l'interface web avec `HUBBLE_UI=true`). L'addon `hubble` ajoute
les ServiceMonitor si la supervision est installée et teste la lecture des flux :

```bash
kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble observe --last 20
kubectl -n kube-system port-forward svc/hubble-ui 12000:80     # si HUBBLE_UI=true
```

## Changer de CNI

<a id="changer-de-cni"></a>**Jamais automatique.** Si un CNI différent est détecté sur le
cluster, l'installation s'arrête avec une explication. Changer de CNI redémarre tous les
Pods, change l'interprétation des NetworkPolicy et peut couper le cluster : c'est une
migration. Procédure sûre dans un lab : sauvegarder (Velero, `make backup`), recréer le
cluster avec le nouveau CNI (`RECREATE=1`), restaurer les applications.

## Versions

Les versions sont verrouillées dans `config/versions.yaml` ([versions.md](versions.md)).
`CNI_VERSION` permet d'en forcer une autre (avertissement : combinaison non validée) ; pour
Flannel, une empreinte SHA-256 connue du manifeste est exigée.
