# Migration

## Depuis la version précédente (lab multi-providers + EKS)

La refonte est **compatible** avec vos fichiers : aucune variable n'a été supprimée, les
anciennes restent acceptées et sont converties (affiché par `make config`). Les commandes
`make doctor / deploy / status / test / kubeconfig / destroy` et les modes `kind`,
`minikube`, `vagrant`, `terraform` (proxmox, vsphere, libvirt, eks) gardent leur forme.

### Ce qui change pour vous

| Avant | Maintenant |
| --- | --- |
| versions dans `config/lab.env` (`FLANNEL_VERSION`, `CONTAINERD_VERSION`, `KIND_NODE_IMAGE`, `VM_IMAGE_URL`, `VAGRANT_BOX`…) | toutes dans `config/versions.yaml` (SHA-256 compris) ; ces variables vides = version verrouillée, une valeur explicite reste prioritaire |
| `KUBERNETES_VERSION=1.37.1` | `1.36.5` par défaut : dernière version compatible avec **tout** le catalogue d'addons ([versions.md](versions.md)) ; 1.37 reste possible |
| `CNI=flannel` | `CNI=auto` (Flannel en kubeadm, kindnet en kind, CNI natif en minikube et EKS) ; `calico`, `cilium`, `none` disponibles |
| `VM_IMAGE_URL` / `VM_IMAGE_SHA256` | `NODE_OS`, `NODE_OS_VERSION`, `NODE_IMAGE_SOURCE` (`catalog`, `url`, `template`) ; les anciennes variables valent `NODE_IMAGE_SOURCE=url` |
| `FLANNEL_VERSION` | `CNI_VERSION` |
| `NFS_DEFAULT_STORAGE_CLASS=true` | `DEFAULT_STORAGE_CLASS=nfs-csi` |
| 1 control-plane | `CONTROL_PLANE_COUNT=1`, `3` ou `5` ([high-availability.md](high-availability.md)) |
| aucun addon | `ADDON_PROFILE=minimal` par défaut : toujours aucun addon tant que vous n'en choisissez pas ([addons.md](addons.md)) |
| certificats de service des kubelets auto-signés | `KUBELET_SERVING_CERTS=signed` : signés par la CA du cluster (voir ci-dessous) |
| erreurs de configuration découvertes en cours de déploiement | `make validate` / `make config` : tout est vérifié avant la moindre création |

Nouveaux modes : `existing` (vos machines) et `attach` (cluster existant) ; nouvelles
commandes d'exploitation : [day2.md](day2.md).

### Un cluster créé par la version précédente

Les clusters jetables (kind, minikube) : recréez-les (`make deploy MODE=kind RECREATE=1`).

Pour un cluster kubeadm (Vagrant, Proxmox, vSphere, libvirt) que vous voulez **garder** :

1. **Version** : il tourne en 1.37.1. Ajoutez `KUBERNETES_VERSION=1.37.1` dans `.env` : le
   playbook refuse tout changement de version d'un cluster existant en dehors de
   `make upgrade` (et un retour en arrière est impossible). Les addons non
   encore déclarés compatibles avec 1.37 par leur projet sont signalés
   (`COMPATIBILITY_POLICY=warn`).
2. **Certificats des kubelets** : ces nœuds ont été créés sans `serverTLSBootstrap`. Deux
   possibilités :
   - simple : `KUBELET_SERVING_CERTS=self-signed` dans `.env` ; metrics-server ne vérifie
     alors pas le TLS des kubelets (`--kubelet-insecure-tls`, signalé par le résolveur) ;
   - recommandé, sur chaque nœud, l'un après l'autre : ajoutez `serverTLSBootstrap: true`
     dans `/var/lib/kubelet/config.yaml`, puis `sudo systemctl restart kubelet` ; faites de
     même dans la ConfigMap `kube-system/kubelet-config` (`kubectl -n kube-system edit cm
     kubelet-config`) pour les futurs nœuds. Le prochain `make deploy` installe
     l'approbateur des certificats (`kubelet-csr-approver`) ; vérifiez
     `kubectl get csr` (toutes `Approved,Issued`) puis `kubectl logs` sur un Pod.
3. **Relire le plan Terraform** au premier `make deploy` (il est toujours affiché et
   confirmé) :
   - Proxmox : l'image cloud téléchargée change d'adresse (`image[0]` → une par serveur
     Proxmox) ; le plan **détruit l'ancien fichier image** et en télécharge un nouveau. Les
     VMs ne sont pas touchées (`import_from` ignoré pour les VMs existantes) ;
   - libvirt : l'image de base n'est jamais remplacée sur un cluster existant (renommée
     dans cette version, elle est conservée telle quelle) ;
   - dans tous les cas, refusez un plan qui **remplace** une VM (`-/+`) ou un disque, et
     signalez-le.
4. Le fichier témoin `/etc/k8s-lab/cluster` (appartenance des nœuds au lab) n'existe pas
   sur ces nœuds : son absence est acceptée en modes vagrant/terraform (machines créées par
   le lab) et il est écrit au prochain déploiement. En mode `existing`, une machine déjà
   membre d'un cluster sans ce fichier est refusée.

Rien n'est réinstallé ni redémarré sur les nœuds si rien n'a changé : le test
kubeadm-in-docker de la CI le contrôle (second déploiement sans aucun changement).

## Depuis la version historique (`run.sh` + ESXi)

La version d'origine (`run.sh` + `Vagrantfile` ESXi + `roles/`) déployait un cluster
kubeadm de 1 master + 3 workers sur un ESXi, avec Vagrant et Ansible. Le principe
**VMs → Ansible → kubeadm → Kubernetes** est conservé et généralisé ; un cluster de cette
époque ne se migre pas : recréez-le.

| Avant | Maintenant |
| --- | --- |
| `./run.sh` | `make deploy MODE=vagrant` (ou `./k8s-lab deploy vagrant`) |
| `run.sh` détruisait l'ancien cluster à chaque lancement | `deploy` ne détruit jamais ; `make destroy MODE=vagrant` (confirmation) ou `RECREATE=1` |
| `vagrant provision worker-1`, `worker-2`, `worker-3` codés en dur | `WORKER_COUNT`, un seul playbook pour tous les nœuds |
| `snap.sh` | `cd vagrant && vagrant snapshot save <nom>` ; sauvegarde etcd : `make backup` |
| `Vagrantfile` à la racine, ESXi uniquement | `vagrant/Vagrantfile` : VirtualBox, libvirt, VMware Desktop, ESXi (`VAGRANT_PROVIDER=vmware_esxi`) |
| mot de passe ESXi, IP et MAC dans le `Vagrantfile` | `.env` (non versionné) ; IP calculées |
| groupes Ansible `masters` / `workers` | `control_plane` / `workers` (+ `k8s_cluster`) |
| `roles/main.yml`, `master.yml`, `worker.yml` | `ansible/site.yml` ([ansible-kubeadm.md](ansible-kubeadm.md)) |
| Ubuntu 20.04, Docker CE, dépôt `apt.kubernetes.io`, Flannel `master` | Ubuntu 24.04 / Debian / Rocky, containerd 2.x, `pkgs.k8s.io`, CNI épinglé + SHA-256 |
| `kubeadm reset -f` à chaque exécution, `ignore_errors` | exécution idempotente, erreurs expliquées, jamais de `kubeadm reset` automatique |
| kubeconfig uniquement dans la VM | `.kube/config` sur votre poste |

Problèmes de l'ancien code traités par la refonte : technologies obsolètes (Ubuntu 20.04,
dépôt Kubernetes fermé en 2024, `apt_key`, Docker comme dépendance), cluster détruit à
chaque provision, erreurs masquées (`ignore_errors`), réseau Flannel écrit à la main,
secrets en clair (mot de passe ESXi, `join-command` en `0777`), configuration dupliquée
entre scripts, destruction non confirmée ([security.md](security.md)).

ESXi autonome : toujours possible avec `VAGRANT_PROVIDER=vmware_esxi`
([deploy-vagrant.md](deploy-vagrant.md)), identifiants dans `.env`.
