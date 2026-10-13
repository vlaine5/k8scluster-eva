# Addons

Un addon est un composant installé **après** le cluster, depuis votre poste, par l'API
Kubernetes : passerelle Gateway API, LoadBalancer, stockage, certificats, supervision,
GitOps, sécurité… Le même moteur (`ansible/roles/addon`) installe tous les addons sur toutes
les plateformes (kind, minikube, kubeadm sur VMs ou machines existantes, EKS, cluster
existant en mode attach).

```bash
make addons-catalog                       # liste des addons
make addons-plan MODE=kind                # ce qui sera installé, pourquoi, dans quel ordre, en quelle version
make addons-apply MODE=kind               # installer / synchroniser (idempotent)
make addons-status MODE=kind              # état et santé
make addons-test MODE=kind                # tests fonctionnels (KEEP=1 pour garder les ressources de test)
make addons-upgrade MODE=kind             # passer aux versions verrouillées de config/versions.yaml
make addons-remove MODE=kind ADDON=reloader   # désinstaller (les données sont conservées)
```

`make deploy` installe les addons du plan puis lance leurs tests
(`ENABLE_POST_DEPLOY_TESTS=true`). `ADDON=a,b` limite une commande à certains addons.

## Choisir les addons

### Profils

`ADDON_PROFILE` choisit une liste de départ (`config/profiles.yaml`) :

| Profil | Addons | Gateway / LoadBalancer par défaut |
| --- | --- | --- |
| `minimal` (défaut) | aucun | aucun |
| `homelab` | metrics-server, cert-manager, argo-cd | Gateway : Cilium si `CNI=cilium`, sinon Traefik ; LoadBalancer si un pool est défini |
| `observability` | metrics-server, monitoring, logging | — |
| `enterprise-lab` | metrics-server, cert-manager, external-secrets, reloader, argo-cd, monitoring, logging, kyverno, trivy-operator | — |
| `custom` | uniquement `ADDONS` | — |

### `ADDONS` : ajouter ou retirer

```bash
ADDON_PROFILE=homelab
ADDONS=keda,+reloader,-argo-cd     # « nom » ou « +nom » : ajouté ; « -nom » : retiré du profil
```

Règles, dans cet ordre (aucune ambiguïté) :

1. le profil donne la liste de départ ;
2. `ADDONS` ajoute (`nom`, `+nom`) ou retire (`-nom`) ; retirer avec `ADDON_PROFILE=custom`
   est refusé (rien à retirer) ;
3. les **sélecteurs** ajoutent leurs addons : `GATEWAY_CONTROLLER` (traefik, envoy-gateway,
   cilium → cilium-gateway, + la Gateway partagée et les CRD Gateway API),
   `LOADBALANCER_PROVIDER` (metallb, cilium-l2/cilium-bgp → cilium-lb), `STORAGE_BACKENDS`
   (nfs-csi, longhorn), `ENABLE_HUBBLE` (hubble) ;
4. les **dépendances** sont ajoutées (ex. monitoring → prometheus-operator-crds) ;
5. contradictions **refusées** : retirer un addon exigé par un sélecteur ou une dépendance,
   deux contrôleurs Gateway, MetalLB et Cilium LB, Falco et Tetragon, deux LoadBalancers…
6. l'ordre d'installation suit les dépendances puis les phases : 4 CRD, 5 réseau, 6 stockage,
   7 infrastructure, 8 plateforme.

`make addons-plan` montre pour chaque addon la raison de sa présence (« profil homelab »,
« GATEWAY_CONTROLLER=traefik », « dépendance de monitoring »…).

## Ce que garantit le moteur

- **Versions verrouillées** (`config/versions.yaml`) ; une release Helm n'est réinstallée que
  si sa version ou ses valeurs changent : relancer `make addons-apply` ne modifie rien
  (vérifié en CI).
- **Namespaces** avec les labels Pod Security (`baseline` par défaut, `restricted` quand
  l'addon le permet, `privileged` seulement s'il l'exige).
- **Secrets** créés depuis `.env`, jamais affichés (`no_log`), jamais écrits sur disque.
- **Manifestes** appliqués en *server-side apply* (gestionnaire de champs `k8s-lab`) : si un
  autre outil possède déjà ces champs, l'application échoue au lieu de les reprendre.
- **Santé** vérifiée après installation (`ENABLE_HEALTHCHECKS`), diagnostic en cas d'échec.
- **Trace** des addons installés : ConfigMap `k8s-lab-system/k8s-lab-addons` (versions,
  raisons) ; elle permet `make addons-upgrade` et distingue, en mode attach, ce qui est géré
  par le framework de ce qui ne l'est pas.
- **Tests** dans un namespace jetable `k8s-lab-test-<addon>`, supprimé à la fin ; un échec
  n'empêche pas de tester les autres addons et produit un rapport
  (`.lab/reports/<contexte>-addons-test.json`).
- **Données** : désinstaller un addon ne supprime jamais un PVC, un volume, une sauvegarde ni
  des CRD ; les PVC sont annotés `helm.sh/resource-policy=keep` avant `helm uninstall`.
  Longhorn n'est jamais désinstallé automatiquement.

## Accès aux interfaces

Aucune interface n'est exposée par défaut. Avec une Gateway (`GATEWAY_CONTROLLER`) :

| Interface | Exposition | Adresse |
| --- | --- | --- |
| Grafana | `GRAFANA_EXPOSE=true` | `https://grafana.<GATEWAY_DOMAIN>` |
| Argo CD | `ARGOCD_EXPOSE=true` | `https://argocd.<GATEWAY_DOMAIN>` |
| Longhorn (sans authentification !) | `LONGHORN_UI_EXPOSE=true` | `https://longhorn.<GATEWAY_DOMAIN>` |

Sinon : `kubectl port-forward` (ex. `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`).
Mot de passe Grafana : `GRAFANA_ADMIN_PASSWORD` dans `.env`, sinon généré
(`kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d`).
Argo CD : `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.

## Cluster existant (mode attach)

Avant d'installer quoi que ce soit, le framework inventorie le cluster (lecture seule) et
**refuse** d'installer un addon déjà présent et géré par un autre outil (release Helm d'un
autre nom, application Argo CD, Traefik de k3s, ServiceLB…), sauf
`EXISTING_ADDON_POLICY=skip` qui l'utilise tel quel sans le gérer : [attach-mode.md](attach-mode.md).

## Ajouter un addon

Un addon = un dossier `addons/<id>/` (fiche `addon.yaml`, valeurs Helm, manifestes, test) :
[addon-development.md](addon-development.md).

## Catalogue

<!-- BEGIN GENERATED: catalog -->
| Addon | Catégorie | Phase | Composants (versions verrouillées) | Rôle |
| --- | --- | --- | --- | --- |
| [prometheus-operator-crds](#prometheus-operator-crds) *(interne)* | observability | 4 | prometheus-operator-crds 32.0.1 | CRD Prometheus Operator |
| [cilium-gateway](#cilium-gateway) | network | 5 | cilium 1.20.2 | Cilium Gateway API |
| [cilium-lb](#cilium-lb) | network | 5 | cilium 1.20.2 | Cilium LB IPAM (L2 / BGP) |
| [envoy-gateway](#envoy-gateway) | network | 5 | envoy-gateway v1.9.2 | Envoy Gateway |
| [gateway-api-crds](#gateway-api-crds) *(interne)* | network | 5 | gateway-api | CRD Gateway API |
| [metallb](#metallb) | network | 5 | metallb 0.16.1 | MetalLB |
| [traefik](#traefik) | network | 5 | traefik 41.7.1 | Traefik (contrôleur Gateway API) |
| [longhorn](#longhorn) | storage | 6 | longhorn 1.13.0 | Longhorn |
| [nfs-csi](#nfs-csi) | storage | 6 | csi-driver-nfs 4.13.5 | NFS CSI Driver |
| [snapshot-controller](#snapshot-controller) | storage | 6 | snapshot-controller v8.7.0 | CSI Snapshot Controller |
| [cert-manager](#cert-manager) | security | 7 | cert-manager v1.21.2 | cert-manager |
| [external-secrets](#external-secrets) | security | 7 | external-secrets 2.12.0 | External Secrets Operator |
| [gateway](#gateway) *(interne)* | network | 7 | — | Gateway partagée du lab |
| [metrics-server](#metrics-server) | infrastructure | 7 | metrics-server 3.14.0 | metrics-server |
| [reloader](#reloader) | operations | 7 | reloader 2.2.18 | Reloader |
| [argo-cd](#argo-cd) | gitops | 8 | argo-cd 10.10.3 | Argo CD |
| [descheduler](#descheduler) | operations | 8 | descheduler 0.37.0 | Descheduler |
| [external-dns](#external-dns) | network | 8 | external-dns 1.23.0 | ExternalDNS |
| [falco](#falco) | security | 8 | falco 9.2.0 | Falco |
| [hubble](#hubble) | observability | 8 | cilium 1.20.2 | Hubble (observabilité réseau Cilium) |
| [istio](#istio) | mesh | 8 | istio-base 1.30.5, istio-cni 1.30.5, istiod 1.30.5 | Istio (service mesh) |
| [keda](#keda) | autoscaling | 8 | keda 2.21.0 | KEDA |
| [kyverno](#kyverno) | security | 8 | kyverno 3.9.1, kyverno-policies 3.9.1 | Kyverno |
| [logging](#logging) | observability | 8 | loki 18.15.1, alloy 1.13.1 | Loki + Grafana Alloy |
| [monitoring](#monitoring) | observability | 8 | kube-prometheus-stack 92.3.1 | Prometheus, Grafana et Alertmanager |
| [node-feature-discovery](#node-feature-discovery) | operations | 8 | node-feature-discovery 0.19.0 | Node Feature Discovery |
| [opentelemetry-collector](#opentelemetry-collector) | observability | 8 | opentelemetry-collector 0.176.0 | OpenTelemetry Collector |
| [tempo](#tempo) | observability | 8 | tempo 3.1.0 | Grafana Tempo |
| [tetragon](#tetragon) | security | 8 | tetragon 1.7.1 | Tetragon |
| [trivy-operator](#trivy-operator) | security | 8 | trivy-operator 0.37.0 | Trivy Operator |
| [velero](#velero) | backup | 8 | velero 12.2.1 | Velero |
<!-- END GENERATED: catalog -->

Compatibilité par plateforme : [compatibility.md](compatibility.md).

## Fiches des addons

<!-- BEGIN GENERATED: details -->
### prometheus-operator-crds

**CRD Prometheus Operator** — CRD ServiceMonitor, PodMonitor, PrometheusRule... installées AVANT les autres addons pour que chacun puisse déclarer sa supervision quel que soit l'ordre d'installation.

| | |
| --- | --- |
| Catégorie, phase | observability, phase 4 (interne) |
| Composants | prometheus-operator-crds 32.0.1 |
| Namespace | `monitoring` (Pod Security : privileged) |
| Données | non |
| Test fonctionnel | via les addons qui l'utilisent |
| Testé en CI | kind |
| Désinstallation | Les CRD sont conservées (les supprimer effacerait toutes les règles et cibles de supervision). |

### cilium-gateway

**Cilium Gateway API** — Contrôleur Gateway API intégré à Cilium (proxy Envoy de Cilium, GatewayClass « cilium »). Activé dans la configuration de Cilium (gatewayAPI.enabled) : exige CNI=cilium et le remplacement de kube-proxy. Les CRD Gateway API sont installées AVANT Cilium.

| | |
| --- | --- |
| Catégorie, phase | network, phase 5 |
| Composants | cilium 1.20.2 |
| Dépend de | gateway-api-crds |
| Exige | cni : cilium; kube_proxy_replacement : True |
| Activé par | `GATEWAY_CONTROLLER=cilium` |
| Données | non |
| Test fonctionnel | via les addons qui l'utilisent |
| Testé en CI | kind |
| Désinstallation | Désactiver la Gateway Cilium = changer GATEWAY_CONTROLLER puis redéployer (mise à jour de la configuration de Cilium). |

### cilium-lb

**Cilium LB IPAM (L2 / BGP)** — Attribution d'IP aux Services LoadBalancer par Cilium (CiliumLoadBalancerIPPool) et annonce en L2 (CiliumL2AnnouncementPolicy, cilium-l2) ou en BGP (CiliumBGPClusterConfig, cilium-bgp). Jamais en même temps que MetalLB.

| | |
| --- | --- |
| Catégorie, phase | network, phase 5 |
| Composants | cilium 1.20.2 |
| Incompatible avec | metallb |
| Exige | cni : cilium; kube_proxy_replacement : True; settings : LOADBALANCER_IP_POOL |
| Activé par | `LOADBALANCER_PROVIDER=cilium-l2\|cilium-bgp` |
| Données | non |
| Test fonctionnel | `addons/cilium-lb/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Les Services LoadBalancer existants perdent leur IP externe. |

### envoy-gateway

**Envoy Gateway** — Implémentation de référence de Gateway API basée sur Envoy Proxy (GatewayClass « envoy-gateway »). Supporte HTTPRoute, GRPCRoute, TLSRoute, et TCPRoute/UDPRoute avec le canal expérimental.

| | |
| --- | --- |
| Catégorie, phase | network, phase 5 |
| Composants | envoy-gateway v1.9.2 |
| Namespace | `envoy-gateway-system` (Pod Security : baseline) |
| Dépend de | gateway-api-crds |
| S'intègre avec | prometheus-operator-crds |
| Activé par | `GATEWAY_CONTROLLER=envoy-gateway` |
| Données | non |
| Test fonctionnel | via les addons qui l'utilisent |
| Testé en CI | kind |
| Désinstallation | Les CRD d'Envoy Gateway sont conservées (helm uninstall ne supprime pas les CRD). |

### gateway-api-crds

**CRD Gateway API** — Ressources standard de Kubernetes Gateway API (GatewayClass, Gateway, HTTPRoute, GRPCRoute, ReferenceGrant...) à la version exigée par le contrôleur choisi. Ajoutées automatiquement.

| | |
| --- | --- |
| Catégorie, phase | network, phase 5 (interne) |
| Composants | gateway-api |
| Données | non |
| Test fonctionnel | via les addons qui l'utilisent |
| Testé en CI | kind |
| Désinstallation | Les CRD ne sont JAMAIS supprimées automatiquement : les supprimer effacerait toutes les routes de toutes les applications. |

### metallb

**MetalLB** — Services de type LoadBalancer sur réseau local (bare metal) : attribue une IP de LOADBALANCER_IP_POOL et l'annonce en L2 (ARP) ou en BGP.

| | |
| --- | --- |
| Catégorie, phase | network, phase 5 |
| Composants | metallb 0.16.1 |
| Namespace | `metallb-system` (Pod Security : privileged) |
| S'intègre avec | prometheus-operator-crds |
| Incompatible avec | cilium-lb |
| Exige | settings : LOADBALANCER_IP_POOL |
| Activé par | `LOADBALANCER_PROVIDER=metallb` |
| Données | non |
| Test fonctionnel | `addons/metallb/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Les Services LoadBalancer existants perdent leur IP externe. |

### traefik

**Traefik (contrôleur Gateway API)** — Traefik Proxy comme contrôleur Kubernetes Gateway API (GatewayClass « traefik »), avec le support des Ingress historiques. Conformité Gateway API v1.6.2 (canal standard ; TCPRoute en expérimental).

| | |
| --- | --- |
| Catégorie, phase | network, phase 5 |
| Composants | traefik 41.7.1 |
| Namespace | `traefik` (Pod Security : restricted) |
| Dépend de | gateway-api-crds |
| S'intègre avec | prometheus-operator-crds |
| Activé par | `GATEWAY_CONTROLLER=traefik` |
| Données | non |
| Test fonctionnel | via les addons qui l'utilisent |
| Testé en CI | non (validé statiquement : rendu et helm template) |
| Désinstallation | Les routes (HTTPRoute) des applications restent en place mais ne sont plus servies. |

### longhorn

**Longhorn** — Stockage bloc distribué sur les disques des workers : volumes répliqués sur des nœuds distincts, instantanés, sauvegardes vers NFS/S3, extension de volume, interface web.

| | |
| --- | --- |
| Catégorie, phase | storage, phase 6 |
| Composants | longhorn 1.13.0 |
| Namespace | `longhorn-system` (Pod Security : privileged) |
| S'intègre avec | snapshot-controller, prometheus-operator-crds, gateway |
| Exige | min_workers : 1 |
| Activé par | `STORAGE_BACKENDS=longhorn` |
| Réglages (.env) | `LONGHORN_VERSION`, `LONGHORN_REPLICA_COUNT`, `LONGHORN_DATA_PATH`, `LONGHORN_STORAGE_CLASS`, `LONGHORN_RECLAIM_POLICY`, `LONGHORN_UI_ENABLED`, `LONGHORN_UI_EXPOSE`, `LONGHORN_BACKUP_ENABLED`, `LONGHORN_BACKUP_TARGET`, `LONGHORN_DEDICATED_DISK`, `LONGHORN_DISK_SIZE_GB` |
| Secrets (.env uniquement) | `LONGHORN_BACKUP_S3_ACCESS_KEY`, `LONGHORN_BACKUP_S3_SECRET_KEY` |
| Données | oui : jamais supprimées automatiquement |
| Test fonctionnel | `addons/longhorn/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |
| Désinstallation | Longhorn exige un drapeau de confirmation (deleting-confirmation-flag) pour se désinstaller : le framework ne le positionne JAMAIS. Les volumes et leurs données restent sur les disques. Procédure manuelle : docs/storage-longhorn.md#desinstallation |

### nfs-csi

**NFS CSI Driver** — Pilote CSI officiel nfs.csi.k8s.io : provisionnement dynamique de volumes (RWO et RWX) dans un sous-dossier d'un export NFS existant (NAS Synology...). Politique Retain par défaut.

| | |
| --- | --- |
| Catégorie, phase | storage, phase 6 |
| Composants | csi-driver-nfs 4.13.5 |
| Namespace | `kube-system` (Pod Security : baseline) |
| S'intègre avec | snapshot-controller, prometheus-operator-crds |
| Exige | settings : NFS_SERVER, NFS_SHARE |
| Activé par | `STORAGE_BACKENDS=nfs-csi` |
| Réglages (.env) | `NFS_SERVER`, `NFS_SHARE`, `NFS_VERSION`, `NFS_STORAGE_CLASS`, `NFS_RECLAIM_POLICY`, `NFS_MOUNT_OPTIONS`, `NFS_SUBDIR` |
| Données | oui : jamais supprimées automatiquement |
| Test fonctionnel | `addons/nfs-csi/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |
| Désinstallation | helm uninstall du pilote uniquement. La StorageClass, les PV et les DONNÉES sur le NAS sont conservés. Les PVC existants ne pourront plus être montés tant que le pilote est absent. |

### snapshot-controller

**CSI Snapshot Controller** — CRD VolumeSnapshot/VolumeSnapshotContent/VolumeSnapshotClass et contrôleur officiel (kubernetes-csi/external-snapshotter). Utile seulement avec un pilote CSI qui sait faire des instantanés (Longhorn ; NFS CSI par archive).

| | |
| --- | --- |
| Catégorie, phase | storage, phase 6 |
| Composants | snapshot-controller v8.7.0 |
| Exige | any_addon : nfs-csi, longhorn |
| Données | non |
| Test fonctionnel | via les addons qui l'utilisent |
| Testé en CI | non (validé statiquement : rendu et helm template) |
| Désinstallation | Les CRD (et donc les instantanés) sont conservées. |

### cert-manager

**cert-manager** — Émission et renouvellement automatiques de certificats TLS : CA interne (aucun domaine public requis), ACME (Let's Encrypt) en HTTP-01 ou DNS-01, intégration Gateway API.

| | |
| --- | --- |
| Catégorie, phase | security, phase 7 |
| Composants | cert-manager v1.21.2 |
| Namespace | `cert-manager` (Pod Security : restricted) |
| S'intègre avec | prometheus-operator-crds, gateway-api-crds |
| Réglages (.env) | `CERT_MANAGER_ISSUER`, `ACME_EMAIL`, `ACME_ENVIRONMENT`, `ACME_DNS01_PROVIDER`, `RFC2136_NAMESERVER`, `RFC2136_TSIG_KEY_NAME`, `RFC2136_TSIG_ALGORITHM` |
| Secrets (.env uniquement) | `CLOUDFLARE_API_TOKEN`, `RFC2136_TSIG_SECRET` |
| Données | non |
| Test fonctionnel | `addons/cert-manager/tests/test.yml` |
| Testé en CI | attach, kind |
| Désinstallation | Les CRD sont conservées (crds.keep=true) : supprimer les CRD supprimerait tous les certificats. Les Secrets TLS déjà émis restent valides jusqu'à leur expiration. |

### external-secrets

**External Secrets Operator** — Synchronise des Secrets Kubernetes depuis un gestionnaire externe (Vault, AWS Secrets Manager, Bitwarden...). L'exemple fourni utilise le fournisseur « kubernetes » : aucun secret réel.

| | |
| --- | --- |
| Catégorie, phase | security, phase 7 |
| Composants | external-secrets 2.12.0 |
| Namespace | `external-secrets` (Pod Security : restricted) |
| S'intègre avec | prometheus-operator-crds |
| Données | non |
| Test fonctionnel | `addons/external-secrets/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Les Secrets déjà synchronisés restent en place ; les CRD sont conservées. |

### gateway

**Gateway partagée du lab** — Gateway « lab-gateway » (namespace gateway-system) partagée par les applications : écouteur HTTP (redirection vers HTTPS si TLS), écouteur HTTPS avec certificat *.GATEWAY_DOMAIN émis par cert-manager. Les applications y attachent leurs HTTPRoute depuis les namespaces étiquetés gateway.k8s-lab.io/expose=true.

| | |
| --- | --- |
| Catégorie, phase | network, phase 7 (interne) |
| Namespace | `gateway-system` (Pod Security : restricted) |
| Dépend de | gateway-controller |
| S'intègre avec | cert-manager, external-dns |
| Données | non |
| Test fonctionnel | `addons/gateway/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Supprimer la Gateway coupe toutes les routes qui y sont attachées. |

### metrics-server

**metrics-server** — API Metrics (metrics.k8s.io) : kubectl top, Horizontal Pod Autoscaler. Vérifie les certificats des kubelets (signés par la CA du cluster) : pas d'option --kubelet-insecure-tls.

| | |
| --- | --- |
| Catégorie, phase | infrastructure, phase 7 |
| Composants | metrics-server 3.14.0 |
| Namespace | `kube-system` (Pod Security : baseline) |
| Données | non |
| Test fonctionnel | `addons/metrics-server/tests/test.yml` |
| Testé en CI | kind |

### reloader

**Reloader** — Redémarre (rolling update) les workloads annotés quand une ConfigMap ou un Secret qu'ils utilisent change.

| | |
| --- | --- |
| Catégorie, phase | operations, phase 7 |
| Composants | reloader 2.2.18 |
| Namespace | `reloader` (Pod Security : restricted) |
| Données | non |
| Test fonctionnel | `addons/reloader/tests/test.yml` |
| Testé en CI | kind |

### argo-cd

**Argo CD** — GitOps : synchronise des applications depuis Git (Application, ApplicationSet). Les composants critiques (CNI, stockage, cert-manager...) restent installés par le framework pour éviter les dépendances circulaires ; Argo CD gère les applications.

| | |
| --- | --- |
| Catégorie, phase | gitops, phase 8 |
| Composants | argo-cd 10.10.3 |
| Namespace | `argocd` (Pod Security : baseline) |
| S'intègre avec | prometheus-operator-crds, gateway |
| Réglages (.env) | `ARGOCD_REPO_URL`, `ARGOCD_REPO_PATH`, `ARGOCD_REPO_REVISION`, `ARGOCD_AUTO_SYNC`, `ARGOCD_EXPOSE` |
| Secrets (.env uniquement) | `ARGOCD_REPO_USERNAME`, `ARGOCD_REPO_PASSWORD` |
| Données | non |
| Test fonctionnel | `addons/argo-cd/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |
| Désinstallation | Désinstaller Argo CD ne supprime PAS les applications qu'il a déployées (les ressources restent). Les CRD Application/ApplicationSet sont conservées. |

### descheduler

**Descheduler** — Rééquilibrage prudent des Pods (CronJob toutes les 30 minutes) : doublons sur un même nœud, nœuds sous-utilisés. Respecte les PodDisruptionBudget ; namespaces système exclus.

| | |
| --- | --- |
| Catégorie, phase | operations, phase 8 |
| Composants | descheduler 0.37.0 |
| Namespace | `kube-system` (Pod Security : baseline) |
| Exige | min_workers : 2 |
| Données | non |
| Test fonctionnel | `addons/descheduler/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |

### external-dns

**ExternalDNS** — Crée les enregistrements DNS des Services LoadBalancer et des HTTPRoute dans un DNS supporté (RFC2136 : BIND, Windows DNS... ; Cloudflare ; Pi-hole). Politique upsert-only : aucun enregistrement n'est jamais supprimé automatiquement.

| | |
| --- | --- |
| Catégorie, phase | network, phase 8 |
| Composants | external-dns 1.23.0 |
| Namespace | `external-dns` (Pod Security : restricted) |
| S'intègre avec | gateway-api-crds, prometheus-operator-crds |
| Exige | settings : EXTERNAL_DNS_PROVIDER, EXTERNAL_DNS_DOMAIN_FILTER |
| Réglages (.env) | `EXTERNAL_DNS_PROVIDER`, `EXTERNAL_DNS_DOMAIN_FILTER`, `RFC2136_NAMESERVER`, `RFC2136_TSIG_KEY_NAME`, `PIHOLE_SERVER` |
| Secrets (.env uniquement) | `RFC2136_TSIG_SECRET`, `CLOUDFLARE_API_TOKEN`, `PIHOLE_PASSWORD` |
| Données | non |
| Test fonctionnel | `addons/external-dns/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |
| Désinstallation | Les enregistrements DNS déjà créés sont conservés (upsert-only). |

### falco

**Falco** — Détection d'événements de sécurité à l'exécution (shell dans un conteneur, lecture de fichiers sensibles...) par eBPF (pilote modern_ebpf). Exige un noyau >= 5.8 avec BTF.

| | |
| --- | --- |
| Catégorie, phase | security, phase 8 |
| Composants | falco 9.2.0 |
| Namespace | `falco` (Pod Security : privileged) |
| Incompatible avec | tetragon |
| Exige | kernel_min : 5.8 |
| Données | non |
| Test fonctionnel | `addons/falco/tests/test.yml` |
| Testé en CI | kind |

### hubble

**Hubble (observabilité réseau Cilium)** — Visibilité des flux réseau entre workloads (Hubble, Hubble Relay, interface web optionnelle), métriques exportées vers Prometheus si la supervision est installée. Activé dans la configuration de Cilium (ENABLE_HUBBLE) : CNI=cilium obligatoire.

| | |
| --- | --- |
| Catégorie, phase | observability, phase 8 |
| Composants | cilium 1.20.2 |
| S'intègre avec | monitoring |
| Exige | cni : cilium |
| Activé par | `ENABLE_HUBBLE=true` |
| Données | non |
| Test fonctionnel | `addons/hubble/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Désactiver Hubble = ENABLE_HUBBLE=false puis redéployer (mise à jour de la configuration de Cilium). |

### istio

**Istio (service mesh)** — Service mesh Istio en mode sidecar : identités SPIFFE, mTLS entre workloads, routage applicatif, télémétrie. Activé namespace par namespace (label istio-injection=enabled). Agent CNI d'Istio : les Pods maillés n'ont besoin d'aucune capacité réseau (compatible Pod Security baseline et Kyverno). Avec Cilium, le framework adapte Cilium (cni.exclusive=false, socketLB.hostNamespaceOnly).

| | |
| --- | --- |
| Catégorie, phase | mesh, phase 8 |
| Composants | istio-base 1.30.5, istio-cni 1.30.5, istiod 1.30.5 |
| Namespace | `istio-system` (Pod Security : privileged) |
| S'intègre avec | prometheus-operator-crds, gateway-api-crds |
| Données | non |
| Test fonctionnel | `addons/istio/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Retirez d'abord le label istio-injection de vos namespaces puis redémarrez les Pods concernés. |

### keda

**KEDA** — Autoscaling piloté par des événements (files de messages, cron, métriques Prometheus...) avec ScaledObject / ScaledJob, y compris jusqu'à zéro réplica.

| | |
| --- | --- |
| Catégorie, phase | autoscaling, phase 8 |
| Composants | keda 2.21.0 |
| Namespace | `keda` (Pod Security : restricted) |
| S'intègre avec | prometheus-operator-crds |
| Données | non |
| Test fonctionnel | `addons/keda/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |

### kyverno

**Kyverno** — Politiques de sécurité en tant que code : validation, mutation, génération et audit des ressources. Politiques Pod Security « baseline » et politiques pédagogiques en mode audit par défaut (KYVERNO_POLICY_MODE), namespaces système exclus.

| | |
| --- | --- |
| Catégorie, phase | security, phase 8 |
| Composants | kyverno 3.9.1, kyverno-policies 3.9.1 |
| Namespace | `kyverno` (Pod Security : baseline) |
| S'intègre avec | prometheus-operator-crds |
| Réglages (.env) | `KYVERNO_POLICY_MODE` |
| Données | non |
| Test fonctionnel | `addons/kyverno/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Désinstaller supprime les webhooks d'admission : les politiques cessent de s'appliquer. |

### logging

**Loki + Grafana Alloy** — Centralisation des journaux : Grafana Alloy (DaemonSet) collecte les journaux des conteneurs (et du journal systemd des nœuds si LOGGING_NODE_LOGS=true) et les envoie à Loki (mode SingleBinary). Consultation dans Grafana si la supervision est installée.

| | |
| --- | --- |
| Catégorie, phase | observability, phase 8 |
| Composants | loki 18.15.1, alloy 1.13.1 |
| Namespace | `logging` (Pod Security : privileged) |
| S'intègre avec | monitoring, prometheus-operator-crds |
| Réglages (.env) | `LOGGING_RETENTION`, `LOGGING_PERSISTENCE`, `LOGGING_NODE_LOGS` |
| Données | oui : jamais supprimées automatiquement |
| Test fonctionnel | `addons/logging/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Le PVC de Loki (si persistance) est conservé. |

### monitoring

**Prometheus, Grafana et Alertmanager** — kube-prometheus-stack : supervision des nœuds, Pods et composants Kubernetes, alertes essentielles, tableaux de bord Grafana. Dimensionné pour un homelab ; persistance optionnelle.

| | |
| --- | --- |
| Catégorie, phase | observability, phase 8 |
| Composants | kube-prometheus-stack 92.3.1 |
| Namespace | `monitoring` (Pod Security : privileged) |
| Dépend de | prometheus-operator-crds |
| S'intègre avec | gateway, nfs-csi, longhorn |
| Exige | storage_class : True |
| Réglages (.env) | `MONITORING_RETENTION`, `MONITORING_PERSISTENCE`, `MONITORING_STORAGE_SIZE_GB`, `GRAFANA_EXPOSE` |
| Secrets (.env uniquement) | `GRAFANA_ADMIN_PASSWORD` |
| Données | oui : jamais supprimées automatiquement |
| Test fonctionnel | `addons/monitoring/tests/test.yml` |
| Testé en CI | kind |
| Désinstallation | Les PVC de Prometheus/Grafana (si persistance) sont conservés. |

### node-feature-discovery

**Node Feature Discovery** — Détecte les caractéristiques matérielles et logicielles des nœuds (CPU, noyau, PCI...) et les publie en labels feature.node.kubernetes.io/* utilisables pour le placement des Pods.

| | |
| --- | --- |
| Catégorie, phase | operations, phase 8 |
| Composants | node-feature-discovery 0.19.0 |
| Namespace | `node-feature-discovery` (Pod Security : privileged) |
| S'intègre avec | prometheus-operator-crds |
| Données | non |
| Test fonctionnel | `addons/node-feature-discovery/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |

### opentelemetry-collector

**OpenTelemetry Collector** — Passerelle OTLP pour la télémétrie applicative : traces vers Tempo, journaux vers Loki, métriques exposées à Prometheus (selon les addons présents). Rôle distinct d'Alloy (journaux des nœuds).

| | |
| --- | --- |
| Catégorie, phase | observability, phase 8 |
| Composants | opentelemetry-collector 0.176.0 |
| Namespace | `opentelemetry` (Pod Security : restricted) |
| S'intègre avec | tempo, logging, monitoring, prometheus-operator-crds |
| Données | non |
| Test fonctionnel | `addons/opentelemetry-collector/tests/test.yml` |
| Testé en CI | kind |

### tempo

**Grafana Tempo** — Stockage et consultation des traces distribuées (OTLP gRPC/HTTP). Source de données Grafana ajoutée automatiquement si la supervision est installée.

| | |
| --- | --- |
| Catégorie, phase | observability, phase 8 |
| Composants | tempo 3.1.0 |
| Namespace | `tracing` (Pod Security : restricted) |
| S'intègre avec | monitoring, prometheus-operator-crds |
| Données | non |
| Test fonctionnel | `addons/tempo/tests/test.yml` |
| Testé en CI | kind |

### tetragon

**Tetragon** — Observabilité de sécurité et application de politiques à l'exécution par eBPF (projet Cilium) : exécutions de processus, accès fichiers, connexions réseau. Exige un noyau avec BTF.

| | |
| --- | --- |
| Catégorie, phase | security, phase 8 |
| Composants | tetragon 1.7.1 |
| Namespace | `kube-system` (Pod Security : baseline) |
| Incompatible avec | falco |
| Exige | kernel_min : 5.4 |
| Données | non |
| Test fonctionnel | `addons/tetragon/tests/test.yml` |
| Testé en CI | kind |

### trivy-operator

**Trivy Operator** — Analyse continue des vulnérabilités des images et des erreurs de configuration des workloads (VulnerabilityReport, ConfigAuditReport). Une analyse à la fois (limité pour un homelab).

| | |
| --- | --- |
| Catégorie, phase | security, phase 8 |
| Composants | trivy-operator 0.37.0 |
| Namespace | `trivy-system` (Pod Security : baseline) |
| S'intègre avec | prometheus-operator-crds |
| Données | non |
| Test fonctionnel | `addons/trivy-operator/tests/test.yml` |
| Testé en CI | kind |

### velero

**Velero** — Sauvegarde et restauration des ressources Kubernetes et, par copie de fichiers (Kopia), du contenu des volumes, vers un stockage S3-compatible. N'assure PAS seul la cohérence d'une base de données en cours d'écriture (voir docs/backup-dr.md).

| | |
| --- | --- |
| Catégorie, phase | backup, phase 8 |
| Composants | velero 12.2.1 |
| Namespace | `velero` (Pod Security : privileged) |
| S'intègre avec | prometheus-operator-crds, snapshot-controller |
| Exige | settings : VELERO_S3_URL, VELERO_BUCKET; secrets : VELERO_S3_ACCESS_KEY, VELERO_S3_SECRET_KEY |
| Réglages (.env) | `VELERO_S3_URL`, `VELERO_BUCKET`, `VELERO_REGION`, `VELERO_FS_BACKUP`, `BACKUP_SCHEDULE`, `BACKUP_RETENTION_DAYS` |
| Secrets (.env uniquement) | `VELERO_S3_ACCESS_KEY`, `VELERO_S3_SECRET_KEY` |
| Données | non |
| Test fonctionnel | `addons/velero/tests/test.yml` |
| Testé en CI | non (validé statiquement : rendu et helm template) |
| Désinstallation | Les sauvegardes dans le bucket S3 ne sont JAMAIS supprimées par le framework. |
<!-- END GENERATED: details -->
