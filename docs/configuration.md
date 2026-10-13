# Configuration

Toute la configuration du lab tient dans des fichiers `CLE=valeur`. Un résolveur unique
(`scripts/labctl`, Python) la **valide entièrement avant toute action** : types, valeurs
autorisées, contradictions, chevauchements de réseaux, compatibilité des versions, plan des
addons. Si la configuration est invalide, **rien n'est créé ni modifié**.

## Où régler quoi ?

| Fichier | Versionné ? | Contenu |
| --- | --- | --- |
| `config/lab.env` | oui | valeurs par défaut de **toutes** les variables |
| `config/schema.yaml` | oui | description de chaque variable (type, valeurs, secret) |
| `config/versions.yaml` | oui | versions verrouillées (Kubernetes, CNI, charts, images d'OS) : [versions.md](versions.md) |
| `config/profiles.yaml` | oui | profils d'addons : [addons.md](addons.md#profils) |
| `.env` (copie de `.env.example`) | **non** | vos réglages **et vos secrets** |
| `terraform/providers/<p>/terraform.tfvars` | **non** | description de votre infrastructure (nœud Proxmox, datastore, réseau) — aucun secret |
| inventaire du mode existing | à vous de voir | vos machines existantes : [existing-mode.md](existing-mode.md) |

Priorité (la première valeur trouvée gagne) :

1. la ligne de commande ou l'environnement : `make deploy MODE=kind WORKERS=3`,
   `WORKER_COUNT=3 make deploy MODE=kind` ;
2. `.env` (ou le fichier désigné par `LAB_ENV_FILE`, par exemple un des
   [profils d'exemple](../examples/profiles/README.md)) ;
3. `config/lab.env`.

```bash
make config MODE=kind          # configuration effective (secrets masqués), choix résolus, plan
make validate MODE=existing    # validation seule
LAB_ENV_FILE=examples/profiles/homelab.env make config   # un autre fichier que .env
```

## Règles du résolveur

- **Variable inconnue** dans `.env` : erreur, avec la variable la plus proche suggérée
  (`WORKERS_COUNT` → `WORKER_COUNT`).
- **Contradictions refusées** : `GATEWAY_CONTROLLER=cilium` avec `CNI=flannel`,
  `CONTROL_PLANE_COUNT=3` avec `HA_MODE=off`, `-metallb` dans `ADDONS` avec
  `LOADBALANCER_PROVIDER=metallb`, deux StorageClasses par défaut…
- **Réseaux** : `POD_CIDR`, `SERVICE_CIDR`, `RESERVED_CIDRS`, le réseau des nœuds, le pool
  `LOADBALANCER_IP_POOL` et la VIP de l'API ne doivent pas se chevaucher. Le pool doit
  appartenir au réseau des nœuds et ne contenir aucune IP de nœud ni de `RESERVED_IPS`.
- **Valeurs automatiques** (`auto`) : toujours résolues explicitement et affichées par
  `make config` (ex. `CNI=auto` → `flannel` sur kubeadm, `kindnet` sur kind).
- **Compatibilité** : chaque composant déclare les mineures de Kubernetes testées par son
  projet ; `COMPATIBILITY_POLICY=warn` avertit, `strict` refuse ([compatibility.md](compatibility.md)).
- **Secrets** : uniquement dans `.env` ou l'environnement ; jamais affichés (`****`), jamais
  écrits dans un fichier généré (variables Ansible, manifeste de déploiement, inventaire).
  Ansible les lit dans l'environnement au moment de créer les Secrets Kubernetes.

## Compatibilité avec les anciennes variables

| Ancienne variable | Remplacée par | Comportement |
| --- | --- | --- |
| `VM_IMAGE_URL`, `VM_IMAGE_SHA256` | `NODE_IMAGE_SOURCE=url` + `NODE_IMAGE_URL` / `NODE_IMAGE_SHA256` | toujours acceptées, avertissement |
| `template_vm_id` (terraform.tfvars Proxmox) | `NODE_TEMPLATE_ID` | les deux fonctionnent ; `.env` est prioritaire |
| `NFS_CSI_ENABLED`, `LONGHORN_ENABLED` | `STORAGE_BACKENDS` | alias acceptés, contradiction refusée |
| `NFS_DEFAULT_STORAGE_CLASS` | `DEFAULT_STORAGE_CLASS` | alias accepté |
| `FLANNEL_VERSION` | `CNI_VERSION` | alias accepté pour Flannel |

Migration complète : [migration.md](migration.md).

## Référence des variables

Cette section est **générée** depuis `config/schema.yaml` et `config/lab.env`
(`make docs-generate`) ; la CI vérifie qu'elle est à jour (`make docs-check`).

<!-- BEGIN GENERATED: variables -->
### Plateforme de déploiement

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `DEPLOYMENT_MODE` | *(vide)* | `kind` · `minikube` · `vagrant` · `terraform` · `existing` · `attach` | Mode utilisé quand la commande n'en précise pas. |
| `DEPLOYMENT_PROVIDER` | *(vide)* | `proxmox` · `vsphere` · `libvirt` · `eks` | Provider Terraform par défaut. |

### Forme du cluster et haute disponibilité

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `CLUSTER_NAME` | `k8s-lab` | string | Nom du cluster (minuscules, chiffres, tirets). |
| `CONTROL_PLANE_COUNT` | `1` | int (1…5) | Nombre de control-planes (1, 3 ou 5). |
| `WORKER_COUNT` | `2` | int (0…20) | Nombre de workers. |
| `HA_MODE` | `auto` | `auto` · `off` · `stacked-etcd` · `external-etcd` | Topologie etcd / haute disponibilité. |
| `CONTROL_PLANE_ENDPOINT` | `auto` | endpoint | Adresse stable de l'API (host:port) ou auto. |
| `CONTROL_PLANE_VIP` | *(vide)* | ip | IP virtuelle de l'API (kube-vip). |
| `API_LB_PROVIDER` | `auto` | `auto` · `kube-vip` · `external` · `none` | Répartiteur de charge de l'API Kubernetes. |

### Machines

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `NODE_HOSTNAME_PREFIX` | `k8s` | string | Préfixe des hostnames. |
| `NODE_CPUS` | `2` | int (2…128) | vCPU par VM. |
| `NODE_MEMORY_MB` | `2048` | int (2048…1048576) | Mémoire par VM (Mo). |
| `NODE_DISK_GB` | `20` | int (10…4096) | Disque système par VM (Go). |
| `NODE_CPU_TYPE` | `x86-64-v2-AES` | string | Type de CPU virtuel (Proxmox). |
| `SSH_PRIVATE_KEY_FILE` | *(vide)* | path | Clé SSH privée d'Ansible (vide = clé dédiée générée). |
| `NODE_SSH_USER` | *(vide)* | string | Utilisateur SSH créé par cloud-init. |

### Système d'exploitation

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `NODE_OS` | `ubuntu` | `ubuntu` · `debian` · `rocky` · `auto` | Distribution des nœuds. |
| `NODE_OS_VERSION` | `24.04` | string | Version de la distribution. |
| `NODE_IMAGE_SOURCE` | `catalog` | `catalog` · `url` · `template` | Origine de l'image des VMs. |
| `NODE_IMAGE_URL` | *(vide)* | url | URL d'une image personnalisée. |
| `NODE_IMAGE_SHA256` | *(vide)* | string | SHA-256 de NODE_IMAGE_URL. |
| `NODE_TEMPLATE_ID` | *(vide)* | string | Template Proxmox (ID) ou vSphere (nom). |
| `VM_IMAGE_URL` | *(vide)* | url | Ancien nom de NODE_IMAGE_URL. **Obsolète** : NODE_IMAGE_URL |
| `VM_IMAGE_SHA256` | *(vide)* | string | Ancien nom de NODE_IMAGE_SHA256. **Obsolète** : NODE_IMAGE_SHA256 |
| `NODE_SWAP` | `disable` | `disable` · `keep` | Gestion du swap des nœuds. |
| `NODE_FIREWALL` | `auto` | `auto` · `managed` · `unmanaged` | Gestion du pare-feu des nœuds. |

### Kubernetes (kubeadm)

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `KUBERNETES_VERSION` | `1.36.5` | version | Version complète de Kubernetes (ex : 1.36.5). |
| `POD_CIDR` | `10.244.0.0/16` | cidr | Réseau des Pods. |
| `SERVICE_CIDR` | `10.96.0.0/12` | cidr | Réseau des Services. |
| `RESERVED_CIDRS` | *(vide)* | cidr_list | Réseaux du LAN à ne pas chevaucher. |
| `NODE_NETWORK_CIDR` | *(vide)* | cidr | Réseau des nœuds (vide = déduit). |
| `RESERVED_IPS` | *(vide)* | ip_ranges | Adresses à ne jamais attribuer (nœuds, LoadBalancer, VIP). |
| `CONTAINER_RUNTIME` | `containerd` | `containerd` | Runtime de conteneurs. |
| `CONTAINERD_VERSION` | *(vide)* | string | Motif de version de containerd.io (2.x). |
| `CONTAINERD_SELINUX` | `false` | bool | Étiquetage SELinux des conteneurs (Rocky). |
| `KUBELET_SERVING_CERTS` | `signed` | `signed` · `self-signed` | Certificats de service des kubelets. |

### Réseau des Pods (CNI)

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `CNI` | `auto` | `auto` · `flannel` · `calico` · `cilium` · `none` | Plugin réseau des Pods. |
| `CNI_VERSION` | *(vide)* | string | Version du CNI (vide = verrouillée). |
| `CNI_MODE` | `auto` | `auto` · `vxlan` · `host-gw` · `vxlan-crosssubnet` · `ipip` · `ipip-crosssubnet` · `direct` · `geneve` · `native` | Mode réseau du CNI. |
| `KUBE_PROXY_MODE` | `auto` | `auto` · `iptables` · `nftables` · `ipvs` · `cilium` | Mode de kube-proxy (cilium = remplacement eBPF). |
| `NETWORK_POLICY_MODE` | `auto` | `auto` · `none` · `kubernetes` · `calico` · `cilium` | Moteur de NetworkPolicy attendu. |
| `ENABLE_HUBBLE` | `false` | bool | Hubble (Cilium). |
| `HUBBLE_UI` | `false` | bool | Interface web de Hubble. |
| `FLANNEL_VERSION` | *(vide)* | string | Ancien réglage de version de Flannel. **Obsolète** : CNI_VERSION |

### Gateway API

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `GATEWAY_CONTROLLER` | `auto` | `auto` · `none` · `traefik` · `envoy-gateway` · `cilium` | Contrôleur Gateway API. |
| `GATEWAY_API_VERSION` | *(vide)* | string | Version des CRD Gateway API. |
| `GATEWAY_API_CHANNEL` | `standard` | `standard` · `experimental` | Canal des CRD Gateway API. |
| `GATEWAY_DOMAIN` | `k8s-lab.internal` | string | Domaine DNS des applications publiées. |
| `GATEWAY_TLS` | `auto` | `auto` · `true` · `false` | Écouteur HTTPS de la Gateway partagée. |
| `GATEWAY_SERVICE_TYPE` | `auto` | `auto` · `LoadBalancer` · `NodePort` · `ClusterIP` | Type du Service de la Gateway. |

### LoadBalancer

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `LOADBALANCER_PROVIDER` | `auto` | `auto` · `none` · `metallb` · `cilium-l2` · `cilium-bgp` | Fournisseur de Services LoadBalancer. |
| `LOADBALANCER_MODE` | `l2` | `l2` · `bgp` | Mode d'annonce de MetalLB. |
| `LOADBALANCER_IP_POOL` | *(vide)* | ip_ranges | Plage(s) d'IP des Services LoadBalancer. |
| `LOADBALANCER_INTERFACES` | *(vide)* | string | Interfaces d'annonce L2 (regex). |
| `BGP_LOCAL_ASN` | *(vide)* | int (1…4294967295) | ASN local (BGP). |
| `BGP_PEER_ADDRESS` | *(vide)* | ip | Adresse du routeur BGP pair. |
| `BGP_PEER_ASN` | *(vide)* | int (1…4294967295) | ASN du routeur pair. |

### Stockage

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `STORAGE_BACKENDS` | *(vide)* | `nfs-csi` · `longhorn` | Backends de stockage. |
| `DEFAULT_STORAGE_CLASS` | `auto` | string | StorageClass par défaut. |
| `NFS_SERVER` | *(vide)* | string | Serveur NFS. |
| `NFS_SHARE` | *(vide)* | string | Export NFS. |
| `NFS_VERSION` | `4.1` | `3` · `4` · `4.0` · `4.1` · `4.2` | Version du protocole NFS. |
| `NFS_STORAGE_CLASS` | `nfs-csi` | string | Nom de la StorageClass NFS. |
| `NFS_RECLAIM_POLICY` | `Retain` | `Retain` · `Delete` | Politique de récupération des volumes NFS. |
| `NFS_MOUNT_OPTIONS` | `hard` | list | Options de montage NFS supplémentaires. |
| `NFS_SUBDIR` | `${pvc.metadata.namespace}-${pvc.metadata.name}-${pv.metadata.name}` | string | Modèle de sous-dossier par volume. |
| `NFS_DEFAULT_STORAGE_CLASS` | *(vide)* | bool | Ancienne forme : true = DEFAULT_STORAGE_CLASS=nfs-csi. **Obsolète** : DEFAULT_STORAGE_CLASS |
| `NFS_CSI_ENABLED` | *(alias, non défini)* | bool | Alias : true = nfs-csi dans STORAGE_BACKENDS. **Obsolète** : STORAGE_BACKENDS |
| `LONGHORN_ENABLED` | *(alias, non défini)* | bool | Alias : true = longhorn dans STORAGE_BACKENDS. **Obsolète** : STORAGE_BACKENDS |
| `LONGHORN_VERSION` | `auto-compatible` | string | Version de Longhorn. |
| `LONGHORN_REPLICA_COUNT` | `3` | int (1…10) | Nombre de réplicas par volume. |
| `LONGHORN_DATA_PATH` | `/var/lib/longhorn` | path | Répertoire des données Longhorn sur les nœuds. |
| `LONGHORN_STORAGE_CLASS` | `longhorn` | string | Nom de la StorageClass Longhorn. |
| `LONGHORN_RECLAIM_POLICY` | `Retain` | `Retain` · `Delete` | Politique de récupération des volumes Longhorn. |
| `LONGHORN_UI_ENABLED` | `true` | bool | Interface web de Longhorn. |
| `LONGHORN_UI_EXPOSE` | `false` | bool | Publier l'interface par la Gateway. |
| `LONGHORN_BACKUP_ENABLED` | `false` | bool | Sauvegardes Longhorn. |
| `LONGHORN_BACKUP_TARGET` | *(vide)* | string | Cible de sauvegarde Longhorn. |
| `LONGHORN_DEDICATED_DISK` | `false` | bool | Disque dédié sur chaque worker. |
| `LONGHORN_DISK_SIZE_GB` | `100` | int (10…65536) | Taille du disque dédié. |
| `LONGHORN_DISK_DATASTORE` | *(vide)* | string | Stockage du disque dédié. |
| `LONGHORN_DISK_DEVICE` | *(vide)* | path | Périphérique dédié (mode existing). |
| `LONGHORN_DISK_ALLOW_FORMAT` | `false` | bool | Autoriser le formatage d'un disque vide. |

### Addons

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `ADDON_PROFILE` | `minimal` | `minimal` · `homelab` · `observability` · `enterprise-lab` · `ci` · `custom` | Profil d'addons. |
| `ADDONS` | *(vide)* | list | Addons ajoutés (nom ou +nom) ou retirés (-nom) par rapport au profil. |
| `COMPATIBILITY_POLICY` | `warn` | `warn` · `strict` | Traitement des combinaisons non testées en amont. |
| `EXISTING_ADDON_POLICY` | `fail` | `fail` · `skip` | Mode attach : composant déjà installé par un autre outil. |

### Réglages des addons

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `CERT_MANAGER_ISSUER` | `selfsigned-ca` | `selfsigned-ca` · `acme-http01` · `acme-dns01` · `none` | ClusterIssuer créé par défaut. |
| `ACME_EMAIL` | *(vide)* | string | E-mail du compte ACME. |
| `ACME_ENVIRONMENT` | `staging` | `staging` · `production` | Serveur ACME (Let's Encrypt). |
| `ACME_DNS01_PROVIDER` | *(vide)* | `cloudflare` · `rfc2136` · `route53` | Fournisseur DNS-01. |
| `RFC2136_NAMESERVER` | *(vide)* | string | Serveur DNS RFC2136 (host:port). |
| `RFC2136_TSIG_KEY_NAME` | *(vide)* | string | Nom de la clé TSIG. |
| `RFC2136_TSIG_ALGORITHM` | `HMACSHA256` | `HMACMD5` · `HMACSHA1` · `HMACSHA256` · `HMACSHA512` | Algorithme TSIG. |
| `ARGOCD_REPO_URL` | *(vide)* | url | Dépôt Git de l'application d'exemple. |
| `ARGOCD_REPO_PATH` | `examples/gitops/apps` | string | Chemin dans le dépôt. |
| `ARGOCD_REPO_REVISION` | `HEAD` | string | Branche, tag ou commit. |
| `ARGOCD_AUTO_SYNC` | `false` | bool | Synchronisation automatique. |
| `ARGOCD_EXPOSE` | `false` | bool | Publier Argo CD par la Gateway. |
| `MONITORING_RETENTION` | `7d` | string | Rétention de Prometheus. |
| `MONITORING_PERSISTENCE` | `false` | bool | Volumes persistants pour la supervision. |
| `MONITORING_STORAGE_SIZE_GB` | `10` | int (1…10000) | Taille du volume Prometheus. |
| `GRAFANA_EXPOSE` | `false` | bool | Publier Grafana par la Gateway. |
| `LOGGING_RETENTION` | `168h` | string | Rétention de Loki. |
| `LOGGING_PERSISTENCE` | `false` | bool | Volume persistant pour Loki. |
| `LOGGING_NODE_LOGS` | `false` | bool | Collecter le journal systemd des nœuds. |
| `KYVERNO_POLICY_MODE` | `audit` | `audit` · `enforce` · `none` | Politiques Kyverno d'exemple. |
| `EXTERNAL_DNS_PROVIDER` | *(vide)* | `rfc2136` · `cloudflare` · `pihole` | Fournisseur DNS d'ExternalDNS. |
| `EXTERNAL_DNS_DOMAIN_FILTER` | *(vide)* | string | Domaine géré par ExternalDNS. |
| `PIHOLE_SERVER` | *(vide)* | url | URL de Pi-hole. |

### Exploitation, sauvegarde, mises à jour

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `BACKUP_ENABLED` | `false` | bool | Sauvegardes automatiques. |
| `BACKUP_PROVIDER` | `etcd-snapshot` | `etcd-snapshot` · `velero` · `both` | Mécanisme de sauvegarde. |
| `BACKUP_SCHEDULE` | `0 3 * * *` | cron | Planification (cron). |
| `BACKUP_RETENTION_DAYS` | `7` | int (1…3650) | Rétention des sauvegardes (jours). |
| `VELERO_S3_URL` | *(vide)* | url | URL S3-compatible de Velero. |
| `VELERO_BUCKET` | *(vide)* | string | Bucket Velero. |
| `VELERO_REGION` | `minio` | string | Région S3. |
| `VELERO_FS_BACKUP` | `true` | bool | Sauvegarde des volumes par copie de fichiers. |
| `UPGRADE_POLICY` | `patch` | `patch` · `minor` | Mises à jour proposées. |
| `ENABLE_HEALTHCHECKS` | `true` | bool | Contrôles de santé après déploiement. |
| `ENABLE_POST_DEPLOY_TESTS` | `true` | bool | Tests fonctionnels après déploiement. |

### Modes existing et attach

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `EXISTING_INVENTORY` | *(vide)* | path | Inventaire Ansible des machines existantes. |
| `EXISTING_KUBECONFIG` | *(vide)* | path | kubeconfig du cluster existant (attach). |
| `EXISTING_CONTEXT` | *(vide)* | string | Contexte kubectl du cluster existant (attach). |

### Kind

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `KIND_NODE_IMAGE` | *(vide)* | string | Image des nœuds kind (vide = verrouillée). |
| `KIND_CONFIG` | *(vide)* | path | Config kind personnalisée. |

### Minikube

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `MINIKUBE_KUBERNETES_VERSION` | *(vide)* | string | Version de Kubernetes de minikube. |
| `MINIKUBE_DRIVER` | *(vide)* | string | Driver minikube. |
| `MINIKUBE_NODES` | `1` | int (1…10) | Nombre de nœuds minikube. |
| `MINIKUBE_CPUS` | `2` | int (2…64) | CPU par nœud minikube. |
| `MINIKUBE_MEMORY_MB` | `2048` | int (1800…262144) | Mémoire par nœud minikube. |
| `MINIKUBE_EXTRA_ARGS` | *(vide)* | string | Options supplémentaires de minikube start. |

### Vagrant

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `VAGRANT_PROVIDER` | `virtualbox` | `virtualbox` · `libvirt` · `vmware_desktop` · `vmware_esxi` | Provider Vagrant. |
| `VAGRANT_BOX` | *(vide)* | string | Box Vagrant (vide = selon NODE_OS). |
| `VAGRANT_BOX_VERSION` | *(vide)* | string | Version de la box. |
| `VAGRANT_NETWORK_PREFIX` | `192.168.56` | string | Préfixe /24 du réseau privé. |
| `VAGRANT_IP_START` | `10` | int (2…250) | Première adresse des VMs. |

### AWS EKS

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `EKS_KUBERNETES_VERSION` | `1.36` | string | Version mineure EKS. |
| `AWS_TARGET` | `aws` | `aws` · `localstack` | Cible AWS. |
| `LOCALSTACK_ENDPOINT` | `http://localhost:4566` | url | Adresse de LocalStack. |

### Versions d'outils

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `KIND_VERSION` | `v0.33.0` | string | Version conseillée de kind. |
| `KUBECTL_VERSION` | `v1.37.1` | string | Version conseillée de kubectl. |
| `MINIKUBE_VERSION` | `v1.39.0` | string | Version conseillée de minikube. |
| `HELM_VERSION` | `v4.3.0` | string | Version conseillée de Helm. |
| `TERRAFORM_VERSION` | `1.16.5` | string | Version conseillée de Terraform. |
| `TFLINT_VERSION` | `v0.64.0` | string | Version de TFLint (CI). |
| `VAGRANT_VERSION` | `2.4.9` | string | Version de Vagrant (CI). |
| `ACTIONLINT_VERSION` | `1.7.12` | string | Version d'actionlint (CI). |

### Identifiants (.env uniquement)

| Variable | Défaut | Type / valeurs | Description |
| --- | --- | --- | --- |
| `PROXMOX_VE_ENDPOINT` | *(.env uniquement)* | url | URL de l'API Proxmox. |
| `PROXMOX_VE_API_TOKEN` | *(.env uniquement)* | string | Token API Proxmox. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `PROXMOX_VE_USERNAME` | *(.env uniquement)* | string | Utilisateur Proxmox (déconseillé). |
| `PROXMOX_VE_PASSWORD` | *(.env uniquement)* | string | Mot de passe Proxmox (déconseillé). *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `PROXMOX_VE_INSECURE` | *(.env uniquement)* | bool | Certificat auto-signé. |
| `VSPHERE_SERVER` | *(.env uniquement)* | string | vCenter. |
| `VSPHERE_USER` | *(.env uniquement)* | string | Utilisateur vCenter. |
| `VSPHERE_PASSWORD` | *(.env uniquement)* | string | Mot de passe vCenter. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `VSPHERE_ALLOW_UNVERIFIED_SSL` | *(.env uniquement)* | bool | Certificat auto-signé. |
| `ESXI_HOSTNAME` | *(.env uniquement)* | string | ESXi autonome (Vagrant). |
| `ESXI_USERNAME` | *(.env uniquement)* | string | Utilisateur ESXi. |
| `ESXI_PASSWORD` | *(.env uniquement)* | string | Mot de passe ESXi. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `ESXI_DATASTORE` | *(.env uniquement)* | string | Datastore ESXi. |
| `ESXI_NETWORKS` | *(.env uniquement)* | string | Réseaux ESXi. |
| `LIBVIRT_DEFAULT_URI` | *(.env uniquement)* | string | URI libvirt. |
| `AWS_PROFILE` | *(.env uniquement)* | string | Profil AWS CLI. |
| `AWS_REGION` | *(.env uniquement)* | string | Région AWS. |
| `GRAFANA_ADMIN_PASSWORD` | *(.env uniquement)* | string | Mot de passe admin Grafana (vide = généré dans le cluster). *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `ARGOCD_REPO_USERNAME` | *(.env uniquement)* | string | Utilisateur du dépôt Git privé. |
| `ARGOCD_REPO_PASSWORD` | *(.env uniquement)* | string | Jeton du dépôt Git privé. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `CLOUDFLARE_API_TOKEN` | *(.env uniquement)* | string | Jeton API Cloudflare (DNS-01, ExternalDNS). *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `RFC2136_TSIG_SECRET` | *(.env uniquement)* | string | Secret TSIG (base64). *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `PIHOLE_PASSWORD` | *(.env uniquement)* | string | Mot de passe Pi-hole. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `VELERO_S3_ACCESS_KEY` | *(.env uniquement)* | string | Clé d'accès S3 de Velero. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `VELERO_S3_SECRET_KEY` | *(.env uniquement)* | string | Clé secrète S3 de Velero. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `LONGHORN_BACKUP_S3_ENDPOINT` | *(.env uniquement)* | url | Point d'accès S3 de la cible Longhorn. |
| `LONGHORN_BACKUP_S3_ACCESS_KEY` | *(.env uniquement)* | string | Clé d'accès S3 Longhorn. *Secret : jamais affiché ni écrit dans un fichier généré.* |
| `LONGHORN_BACKUP_S3_SECRET_KEY` | *(.env uniquement)* | string | Clé secrète S3 Longhorn. *Secret : jamais affiché ni écrit dans un fichier généré.* |
<!-- END GENERATED: variables -->
