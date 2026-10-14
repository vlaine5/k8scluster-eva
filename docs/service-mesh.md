# Service mesh (Istio)

L'addon `istio` installe Istio en mode **sidecar** (charts `base`, `cni` et `istiod`, version
verrouillée). Il est facultatif : ajoutez-le avec `ADDONS=istio`.

```bash
kubectl label namespace demo istio-injection=enabled
kubectl -n demo rollout restart deployment     # les Pods reçoivent le sidecar istio-proxy
```

mTLS strict dans un namespace :

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: {name: default, namespace: demo}
spec:
  mtls: {mode: STRICT}
```

## Points d'attention

- **Agent CNI d'Istio** (DaemonSet `istio-cni-node`, privilégié, dans `istio-system`) : il
  configure la redirection du trafic de chaque Pod maillé. Les Pods n'ont donc plus de
  conteneur `istio-init` avec les capacités `NET_ADMIN`/`NET_RAW`, seulement un conteneur
  `istio-validation` sans capacité : les namespaces maillés restent en Pod Security
  `baseline` et compatibles avec les politiques Kyverno en mode `enforce` (testé en CI).
- **Avec Cilium**, quand Istio est dans le plan, Cilium est configuré avec
  `cni.exclusive=false` (sinon il retire la configuration CNI d'Istio) et, sans kube-proxy,
  `socketLB.hostNamespaceOnly` (sinon la répartition de charge eBPF court-circuite les
  sidecars). Ajouter Istio après coup exige donc de relancer `make deploy` (mise à jour de la
  configuration de Cilium), ce que le résolveur signale.
- Mode attach : un Cilium existant doit déjà avoir ces deux réglages ; k3s et RKE2 placent
  la configuration CNI dans des chemins non standard, non pris en charge par le lab.
- Istio et la Gateway API : Istio sait aussi être un contrôleur Gateway API, mais le lab
  garde un seul contrôleur (`GATEWAY_CONTROLLER`) pour la Gateway partagée.
- Coût : ~100 Mo de mémoire par sidecar. Pour un homelab, réservez le maillage aux
  namespaces qui en ont besoin.

## Test

`make addons-test ADDON=istio` : injection du sidecar, appel d'un client maillé vers un
serveur maillé (mTLS), puis **refus** d'un client hors du maillage (mTLS STRICT).
