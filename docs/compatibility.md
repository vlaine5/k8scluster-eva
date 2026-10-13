# Matrices de compatibilité

Ces matrices sont **générées** depuis le catalogue (`addons/*/addon.yaml`) et
`config/versions.yaml` (`make docs-generate`) ; la CI vérifie qu'elles sont à jour.

Les statuts :

- **supporté** : le framework sait l'installer et le configurer sur cette plateforme ;
- **supporté avec configuration particulière** : fonctionne, avec une contrainte décrite en note ;
- **expérimental** : installé et testé au mieux, sans garantie ;
- **non supporté** : refusé par le résolveur (erreur explicite).

« Testé en CI » distingue ce qui est **réellement** déployé et testé à chaque push de ce qui
est seulement supporté en théorie. Le détail des tests : [README.md](../README.md#état-de-validation).

## Addons par plateforme

<!-- BEGIN GENERATED: addons -->
| Addon | Kind | Minikube | Vagrant | Proxmox | vSphere | libvirt | Existing | EKS | Attach | Testé en CI |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [prometheus-operator-crds](addons.md#prometheus-operator-crds) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | kind |
| [cilium-gateway](addons.md#cilium-gateway) | 🧪<sup>1</sup> | ❌<sup>2</sup> | ✅ | ✅ | ✅ | ✅ | ✅ | ❌<sup>3</sup> | ❌<sup>4</sup> | kind |
| [cilium-lb](addons.md#cilium-lb) | 🧪<sup>5</sup> | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌<sup>6</sup> | kind |
| [envoy-gateway](addons.md#envoy-gateway) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>7</sup> | ✅ | non |
| [gateway-api-crds](addons.md#gateway-api-crds) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>8</sup> | kind |
| [metallb](addons.md#metallb) | ⚙️<sup>9</sup> | 🧪<sup>10</sup> | ✅ | ✅ | ✅ | ✅ | ✅ | ❌<sup>11</sup> | ⚙️<sup>12</sup> | non |
| [traefik](addons.md#traefik) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>13</sup> | ✅ | non |
| [longhorn](addons.md#longhorn) | ❌<sup>14</sup> | ❌<sup>15</sup> | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>16</sup> | ❌<sup>17</sup> | 🧪<sup>18</sup> | non |
| [nfs-csi](addons.md#nfs-csi) | ⚙️<sup>19</sup> | 🧪<sup>20</sup> | ✅ | ✅ | ✅ | ✅ | ✅ | 🧪<sup>21</sup> | ✅ | non |
| [snapshot-controller](addons.md#snapshot-controller) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>22</sup> | ✅ | non |
| [cert-manager](addons.md#cert-manager) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | attach, kind |
| [external-secrets](addons.md#external-secrets) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |
| [gateway](addons.md#gateway) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | kind |
| [metrics-server](addons.md#metrics-server) | ✅ | ⚙️<sup>23</sup> | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>24</sup> | kind |
| [reloader](addons.md#reloader) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |
| [argo-cd](addons.md#argo-cd) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |
| [descheduler](addons.md#descheduler) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |
| [external-dns](addons.md#external-dns) | 🧪<sup>25</sup> | 🧪 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |
| [falco](addons.md#falco) | 🧪<sup>26</sup> | 🧪 | ✅ | ✅ | ✅ | ✅ | ✅ | 🧪 | ⚙️<sup>27</sup> | kind |
| [hubble](addons.md#hubble) | 🧪 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌<sup>28</sup> | kind |
| [istio](addons.md#istio) | 🧪 | 🧪 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>29</sup> | kind |
| [keda](addons.md#keda) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |
| [kyverno](addons.md#kyverno) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | kind |
| [logging](addons.md#logging) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | kind |
| [monitoring](addons.md#monitoring) | ⚙️<sup>30</sup> | ⚙️<sup>31</sup> | ✅ | ✅ | ✅ | ✅ | ✅ | ⚙️<sup>32</sup> | ✅ | kind |
| [node-feature-discovery](addons.md#node-feature-discovery) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |
| [opentelemetry-collector](addons.md#opentelemetry-collector) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | kind |
| [tempo](addons.md#tempo) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | kind |
| [tetragon](addons.md#tetragon) | 🧪<sup>33</sup> | 🧪 | ✅ | ✅ | ✅ | ✅ | ✅ | 🧪 | ✅ | kind |
| [trivy-operator](addons.md#trivy-operator) | 🧪<sup>34</sup> | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | kind |
| [velero](addons.md#velero) | 🧪<sup>35</sup> | 🧪 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | non |

Légende : ✅ supporté · ⚙️ supporté avec configuration particulière · 🧪 expérimental · ❌ non supporté. « Testé en CI » indique les environnements où l'addon est réellement installé et testé par la CI ; une case ✅ sans test signifie « supporté en théorie, non validé en conditions réelles ».

Notes :

1. **cilium-gateway / Kind** : Cilium sur kind (disableDefaultCNI).
2. **cilium-gateway / Minikube** : Le CNI de minikube n'est pas configurable finement.
3. **cilium-gateway / EKS** : EKS utilise AWS VPC CNI.
4. **cilium-gateway / Attach** : Modifierait la configuration du CNI.
5. **cilium-lb / Kind** : Pool dans le réseau Docker « kind ».
6. **cilium-lb / Attach** : Modifierait la configuration du CNI.
7. **envoy-gateway / EKS** : Le Service LoadBalancer crée un load balancer AWS payant.
8. **gateway-api-crds / Attach** : Si les CRD existent déjà, leur version (bundle-version) doit être compatible ; sinon refus.
9. **metallb / Kind** : Le pool doit être dans le réseau Docker « kind » (docker network inspect kind).
10. **metallb / Minikube** : Préférez « minikube tunnel ».
11. **metallb / EKS** : AWS fournit les load balancers.
12. **metallb / Attach** : Refusé si un autre fournisseur LoadBalancer (ServiceLB de k3s...) est détecté.
13. **traefik / EKS** : Le Service LoadBalancer crée un load balancer AWS payant.
14. **longhorn / Kind** : open-iscsi et disques réels requis.
15. **longhorn / Minikube** : open-iscsi et disques réels requis.
16. **longhorn / Existing** : Prérequis installés par Ansible ; disque dédié seulement si LONGHORN_DISK_DEVICE est fourni.
17. **longhorn / EKS** : Utilisez les volumes EBS (pilote CSI AWS).
18. **longhorn / Attach** : Les prérequis des nœuds ne peuvent pas être installés par le framework.
19. **nfs-csi / Kind** : Le serveur NFS doit être joignable depuis les conteneurs kind (CI : serveur NFS de test dans le cluster).
20. **nfs-csi / Minikube** : Selon le driver et le réseau de minikube.
21. **nfs-csi / EKS** : Préférez EFS ou EBS ; le serveur NFS doit être joignable depuis le VPC.
22. **snapshot-controller / EKS** : Avec le pilote CSI EBS (non installé par le framework).
23. **metrics-server / Minikube** : Installé par l'addon natif de minikube (minikube addons enable metrics-server).
24. **metrics-server / Attach** : Refusé si l'API metrics.k8s.io est déjà fournie (k3s, AKS...). Les certificats de service des kubelets doivent être signés par la CA du cluster, sinon KUBELET_SERVING_CERTS=self-signed.
25. **external-dns / Kind** : Nécessite un serveur DNS joignable depuis le cluster.
26. **falco / Kind** : Utilise le noyau de l'hôte Docker.
27. **falco / Attach** : Le noyau des nœuds (BTF) est vérifié au démarrage de Falco.
28. **hubble / Attach** : Modifierait la configuration du CNI.
29. **istio / Attach** : Avec Cilium existant : cni.exclusive=false et socketLB.hostNamespaceOnly=true doivent déjà être réglés. k3s/RKE2 : chemins CNI non standard, non pris en charge.
30. **monitoring / Kind** : Composants du control-plane non supervisés (liés à 127.0.0.1 par kind).
31. **monitoring / Minikube** : Composants du control-plane non supervisés.
32. **monitoring / EKS** : Control-plane géré par AWS : non supervisé.
33. **tetragon / Kind** : Utilise le noyau de l'hôte Docker.
34. **trivy-operator / Kind** : Analyses lentes (téléchargement de la base de vulnérabilités).
35. **velero / Kind** : Nécessite un stockage S3 joignable.
<!-- END GENERATED: addons -->

## Systèmes d'exploitation des nœuds (modes kubeadm)

<!-- BEGIN GENERATED: os -->
| Distribution | Version | Statut | Noyau | CPU x86-64 minimal | Testé en CI | Image épinglée |
| --- | --- | --- | --- | --- | --- | --- |
| ubuntu | 24.04 | supported | 6.8 | v1 | non | `ubuntu-24.04-server-cloudimg-amd64.img` |
| ubuntu | 26.04 | experimental | 7.0 | v1 | non | `ubuntu-26.04-server-cloudimg-amd64.img` |
| debian | 12 | supported | 6.1 | v1 | non | `debian-12-generic-amd64-20261006-2623.qcow2` |
| debian | 13 | supported | 6.12 | v1 | non | `debian-13-generic-amd64-20261001-2618.qcow2` |
| rocky | 9 | supported | 5.14 | v2 | non | `Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2` |
| rocky | 10 | experimental | 6.12 | v3 | non | `Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2` |
<!-- END GENERATED: os -->

## Kubernetes et composants

Chaque composant déclare dans `config/versions.yaml` la mineure minimale (`kube_min`) et les
mineures testées par son projet (`kube_tested`). Le résolveur refuse une version inférieure
au minimum et avertit (ou refuse avec `COMPATIBILITY_POLICY=strict`) hors des versions
testées. Vérification pour votre configuration : `make config`.

## CNI et fonctionnalités

| Fonctionnalité | Flannel | Calico | Cilium |
| --- | --- | --- | --- |
| Réseau des Pods (VXLAN) | ✅ | ✅ | ✅ |
| Routage direct (`CNI_MODE`) | `host-gw` | `bgp`, `direct` | `native` |
| NetworkPolicy Kubernetes | ❌ (ignorées !) | ✅ | ✅ |
| Politiques avancées | ❌ | Calico | Cilium (L7) |
| Remplacement de kube-proxy | ❌ | ❌ (eBPF possible, non configuré) | ✅ (`KUBE_PROXY_MODE=cilium`) |
| Gateway API intégrée | ❌ | ❌ | ✅ (`GATEWAY_CONTROLLER=cilium`) |
| LoadBalancer intégré | ❌ | ❌ | ✅ L2 / BGP (`cilium-l2`, `cilium-bgp`) |
| Observabilité réseau | ❌ | ❌ | ✅ Hubble |
| Noyau minimal | — | — | 5.10 |

Détails : [cni.md](cni.md).
