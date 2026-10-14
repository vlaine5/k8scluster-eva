# Observabilité

| Addon | Contenu | Profil |
| --- | --- | --- |
| `metrics-server` | API `metrics.k8s.io` : `kubectl top`, HPA | tous sauf minimal |
| `monitoring` | kube-prometheus-stack : Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, règles et tableaux de bord | observability, enterprise-lab |
| `logging` | Loki (monolithique) + Grafana Alloy | observability, enterprise-lab |
| `tempo` | traces distribuées (OTLP) | à ajouter |
| `opentelemetry-collector` | point d'entrée OTLP unique : traces → Tempo, journaux → Loki, métriques → Prometheus | à ajouter |
| `hubble` | flux réseau (Cilium) | `ENABLE_HUBBLE=true` |

```bash
ADDON_PROFILE=observability
ADDONS=+tempo,+opentelemetry-collector
MONITORING_RETENTION=7d
MONITORING_PERSISTENCE=false        # true : PVC sur la StorageClass par défaut
LOGGING_RETENTION=168h
LOGGING_NODE_LOGS=false             # true : journal systemd des nœuds (kubelet, containerd)
GRAFANA_EXPOSE=false                # true : https://grafana.<GATEWAY_DOMAIN>
```

## metrics-server sans TLS non vérifié

metrics-server vérifie les certificats des kubelets **sans** `--kubelet-insecure-tls` :

- kubeadm : `serverTLSBootstrap: true` ; les demandes de certificat des kubelets sont
  approuvées par kubelet-csr-approver, limité aux noms et IP exacts des nœuds ;
- kind : même configuration, demandes approuvées par `./k8s-lab` (nœuds du cluster uniquement) ;
- EKS : certificats signés par AWS ;
- minikube : addon natif de minikube (qui, lui, n'exige pas de certificats signés).

Dans l'autre sens, l'APIService `v1beta1.metrics.k8s.io` vérifie le certificat de
metrics-server (CA déclarée, pas d'`insecureSkipTLSVerify`). De même, Prometheus vérifie le
certificat des kubelets avec la CA du cluster.

## Supervision (kube-prometheus-stack)

- Toutes les `ServiceMonitor`, `PodMonitor` et `PrometheusRule` du cluster sont collectées
  (pas seulement celles de la release) : chaque addon déclare sa supervision si les CRD sont
  présentes (elles sont installées en premier, addon interne `prometheus-operator-crds`).
- Clusters kubeadm : contrôleur, ordonnanceur, etcd (`:2381`) et kube-proxy sont exposés
  pour Prometheus par la configuration kubeadm du lab. kind, minikube, EKS : non supervisés
  (non joignables), règles correspondantes désactivées.
- Accès : `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`.

Test (`make addons-test ADDON=monitoring`) : chaque job attendu (apiserver, kubelet,
node-exporter, kube-state-metrics, + plan de contrôle sur kubeadm) a des cibles « up »,
aucune cible « down », requête PromQL, santé de Grafana et d'Alertmanager.

## Journaux

<a id="journaux"></a>Loki en mode monolithique (un Pod, stockage fichiers, rétention
`LOGGING_RETENTION`). Alloy (DaemonSet) lit les journaux des conteneurs **par l'API
Kubernetes** (aucun montage de `/var/log/pods`) et ajoute `namespace`, `pod`, `container`,
`app`, `node`. La source de données Loki est ajoutée à Grafana automatiquement.

```text
{namespace="demo"} |= "error"
```

Test : une ligne unique écrite par un Pod est retrouvée dans Loki.

## Traces

<a id="traces"></a>Tempo reçoit les traces en OTLP (`tempo.tracing:4317` gRPC, `:4318` HTTP).
Avec la supervision, il calcule le graphe des services (écrit dans Prometheus) et Grafana
relie traces, journaux et métriques. Test : une trace envoyée en OTLP est relue par l'API de
Tempo.

## OpenTelemetry

<a id="opentelemetry"></a>Le collecteur
(`otel-collector-opentelemetry-collector.opentelemetry:4317/4318`) est le point d'entrée
unique des applications instrumentées : il route les traces vers Tempo, les journaux vers
Loki (OTLP) et les métriques vers Prometheus (récepteur OTLP), selon les addons présents.

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-opentelemetry-collector.opentelemetry:4318
```

## Ressources

Le profil observability demande environ 1 vCPU et 2 Go de RAM supplémentaires (`make config`
affiche l'estimation des addons). Sur un homelab de 3 workers à 4 Go, préférez
`MONITORING_PERSISTENCE=true` (données conservées au redémarrage) et une rétention courte.
