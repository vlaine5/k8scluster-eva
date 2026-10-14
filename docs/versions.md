# Versions verrouillées

Toutes les versions installées par le lab sont fixées dans **un seul fichier** :
`config/versions.yaml`. Rien n'est installé en « latest » : chaque chart Helm a une version
exacte, chaque manifeste téléchargé (Flannel, Gateway API, snapshot-controller) une empreinte
SHA-256, chaque image d'OS une release datée et son SHA-256, chaque image kind un condensé.

```bash
make versions          # ce tableau, dans le terminal
make versions-check    # versions plus récentes publiées en amont (rien n'est installé)
```

`make versions-check` classe chaque nouveauté en correctif, mineure ou majeure et rappelle
`UPGRADE_POLICY` (`patch` : seuls les correctifs sont proposés). Mettre à jour une version,
c'est modifier `config/versions.yaml` dans une branche, lancer la CI (rendu de tous les
addons, déploiements réels), puis `make addons-upgrade` / `make upgrade` après relecture des
notes de version : [upgrades.md](upgrades.md).

## Pourquoi Kubernetes 1.36.5 par défaut ?

C'est la version la plus récente avec laquelle **tous** les composants du catalogue sont
déclarés testés par leur projet (Cilium 1.20 teste jusqu'à 1.36, par exemple). La 1.37.1 est
acceptée (`KUBERNETES_VERSION=1.37.1`) avec des avertissements pour les composants qui ne la
déclarent pas encore ; le passage 1.36 → 1.37 est le chemin de mise à niveau testé en CI.

## Tableau

<!-- BEGIN GENERATED: versions -->
Vérifiées le **2026-10-13** (`make versions-check` compare avec les dépôts officiels).

| Élément | Version | Source |
| --- | --- | --- |
| Kubernetes (défaut) | 1.36.5 | mineures supportées : 1.34, 1.35, 1.36, 1.37 |
| containerd | 2.3.* | download.docker.com (containerd.io) |
| Helm (sur les nœuds) | v4.3.0 | get.helm.sh (SHA-256 verrouillé) |
| kube-vip | v1.2.4 | ghcr.io/kube-vip/kube-vip |
| image kind 1.34 | `v1.34.11` | kindest/node (condensé épinglé) |
| image kind 1.35 | `v1.35.8` | kindest/node (condensé épinglé) |
| image kind 1.36 | `v1.36.4` | kindest/node (condensé épinglé) |
| image kind 1.37 | `v1.37.0` | kindest/node (condensé épinglé) |
| alloy | 1.13.1 | <https://grafana.github.io/helm-charts> |
| argo-cd | 10.10.3 | <https://argoproj.github.io/argo-helm> |
| calico | v3.33.0 | <https://docs.tigera.io/calico/charts> |
| cert-manager | v1.21.2 | <https://charts.jetstack.io> |
| cilium | 1.20.2 | <https://helm.cilium.io> |
| csi-driver-nfs | 4.13.5 | <https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts> |
| descheduler | 0.37.0 | <https://kubernetes-sigs.github.io/descheduler> |
| envoy-gateway | v1.9.2 | oci://docker.io/envoyproxy/gateway-helm |
| external-dns | 1.23.0 | <https://kubernetes-sigs.github.io/external-dns> |
| external-secrets | 2.12.0 | <https://charts.external-secrets.io> |
| falco | 9.2.0 | <https://falcosecurity.github.io/charts> |
| flannel | v0.28.10 | manifeste + SHA-256 |
| gateway-api | - | manifeste + SHA-256 |
| istio-base | 1.30.5 | <https://istio-release.storage.googleapis.com/charts> |
| istio-cni | 1.30.5 | <https://istio-release.storage.googleapis.com/charts> |
| istiod | 1.30.5 | <https://istio-release.storage.googleapis.com/charts> |
| keda | 2.21.0 | <https://kedacore.github.io/charts> |
| kube-prometheus-stack | 92.3.1 | <https://prometheus-community.github.io/helm-charts> |
| kubelet-csr-approver | 1.2.15 | <https://postfinance.github.io/kubelet-csr-approver> |
| kyverno | 3.9.1 | <https://kyverno.github.io/kyverno> |
| kyverno-policies | 3.9.1 | <https://kyverno.github.io/kyverno> |
| loki | 18.15.1 | <https://grafana-community.github.io/helm-charts> |
| longhorn | 1.13.0 | <https://charts.longhorn.io> |
| metallb | 0.16.1 | <https://metallb.github.io/metallb> |
| metrics-server | 3.14.0 | <https://kubernetes-sigs.github.io/metrics-server> |
| node-feature-discovery | 0.19.0 | <https://kubernetes-sigs.github.io/node-feature-discovery/charts> |
| opentelemetry-collector | 0.176.0 | <https://open-telemetry.github.io/opentelemetry-helm-charts> |
| prometheus-operator-crds | 32.0.1 | <https://prometheus-community.github.io/helm-charts> |
| reloader | 2.2.18 | <https://stakater.github.io/stakater-charts> |
| snapshot-controller | v8.7.0 | manifeste + SHA-256 |
| tempo | 3.1.0 | <https://grafana-community.github.io/helm-charts> |
| tetragon | 1.7.1 | <https://helm.cilium.io> |
| traefik | 41.7.1 | <https://traefik.github.io/charts> |
| trivy-operator | 0.37.0 | <https://aquasecurity.github.io/helm-charts> |
| velero | 12.2.1 | <https://vmware-tanzu.github.io/helm-charts> |
<!-- END GENERATED: versions -->
