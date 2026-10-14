# Ansible + kubeadm : comment le cluster est construit

Quel que soit l'origine des machines (Vagrant, Terraform, ou vos machines en mode
`existing`), c'est le même playbook, `ansible/site.yml`, qui installe Kubernetes, sur
Ubuntu, Debian ou Rocky Linux ([os.md](os.md)). (Le mode AWS EKS n'utilise pas ce playbook : AWS
fournit le control-plane, voir [deploy-eks.md](deploy-eks.md).) Il suit la documentation officielle
[*Creating a cluster with kubeadm*](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).

## L'inventaire

```ini
[control_plane]
k8s-cp-1 ansible_host=192.168.1.100 node_ip=192.168.1.100

[workers]
k8s-worker-1 ansible_host=192.168.1.101 node_ip=192.168.1.101
k8s-worker-2 ansible_host=192.168.1.102 node_ip=192.168.1.102

[k8s_cluster:children]
control_plane
workers
```

Il est **généré** (`inventories/vagrant.ini`, `inventories/terraform-<provider>.ini`) ; en
mode existing, c'est le vôtre (modèle : `inventories/existing.example.ini`,
[existing-mode.md](existing-mode.md)). 1, 3 ou 5 control-planes ; le premier initialise le
cluster, les autres le rejoignent.

## Les étapes (`ansible/site.yml`)

| Étape | Rôle | Ce qui se passe |
| --- | --- | --- |
| 0 | *(play 1)* | inventaire vérifié (1, 3 ou 5 control-planes), attente SSH et fin de cloud-init, faits |
| 1 | `preflight` | **lecture seule** : OS dans la matrice (et conforme à `NODE_OS`), cgroup v2, ressources, `product_uuid`/MAC uniques, nœud déjà membre d'un autre cluster ; en mode existing : ports occupés, paquets en conflit, disques |
| 2 | `common` | hostname, `/etc/hosts`, swap, modules `overlay`/`br_netfilter`, sysctl, SELinux (Rocky : `enforcing` conservé), pare-feu (firewalld sur Rocky) |
| 3 | `container_runtime` | dépôt Docker (deb822 ou `yum_repository`, clé dédiée), `containerd.io` 2.x **gelé**, `SystemdCgroup = true`, image `pause`, `crictl` |
| 4 | `kubernetes` | dépôt `pkgs.k8s.io` de la mineure, `kubelet`/`kubeadm`/`kubectl` **à la version exacte**, gelés (`dpkg` hold ou exclusion DNF) |
| 5 | `node_prereqs` | paquets, modules et services demandés par les addons du plan (iSCSI et `dm_crypt` pour Longhorn, client NFS…) |
| 6 | `storage_disk` | disque Longhorn dédié : identifié sans ambiguïté, formaté **seulement s'il est vide**, monté par étiquette |
| 7 | `control_plane` (1er) | VIP de l'API (kube-vip) si demandée, `kubeadm init --config …` (une seule fois), kubeconfig |
| 8 | `cni`, `cluster_core` | Flannel (manifeste SHA-256 + Kustomize), Calico (opérateur Tigera) ou Cilium (Helm) ; approbation des certificats de service des kubelets |
| 9 | `control_plane` (autres) | un par un : quorum etcd vérifié, `kubeadm join --control-plane` |
| 10 | `worker` | jeton de 15 min, `kubeadm join --config …`, suppression du fichier, label `worker` |
| 11 | *(play final)* | nœuds `Ready`, Pods système prêts, kubeconfig exporté vers `.kube/clusters/` |
| 12 | `etcd` | instantanés planifiés (`BACKUP_ENABLED=true`) |

### Points à observer sur une VM

```bash
sudo cat /etc/kubernetes/kubeadm-config.yaml     # configuration de kubeadm init
ls /etc/kubernetes/manifests/                    # etcd, apiserver, scheduler... (Pods statiques)
sudo crictl ps                                   # conteneurs vus par le kubelet
sudo containerd config dump | grep SystemdCgroup
sudo cat /etc/kubernetes/addons/flannel/kustomization.yaml
kubectl get nodes -o wide                        # sur le control-plane
```

## Idempotence

Relancer le playbook ne casse rien :

- `kubeadm init` n'est lancé que si `/etc/kubernetes/admin.conf` n'existe pas ;
- `kubeadm join` n'est lancé que si le worker n'est pas déjà membre (`kubelet.conf`) ;
- la configuration de containerd n'est réécrite (et containerd redémarré) que si elle change ;
- un worker ajouté à l'inventaire est simplement joint au cluster existant.

Changer `KUBERNETES_VERSION` sur un cluster existant est **refusé** avec un message
explicatif : une mise à jour se fait par `make upgrade-plan` puis `make upgrade` (kubeadm,
nœud par nœud : [upgrades.md](upgrades.md)), pas par un changement de paquet.

## Sécurité

- Aucun `join-command` n'est écrit sur votre poste ni laissé sur les VMs : le jeton (15 min)
  circule en mémoire (`no_log`) et le fichier de configuration du join est supprimé.
- Le jeton créé par `kubeadm init` expire aussi au bout de 15 minutes.
- Le CA du cluster est vérifié par les workers (`caCertHashes`).
- Fichiers sensibles en `0600` (config kubeadm, kubeconfig) ; aucun `0777`.
- CNI, charts et manifestes : versions épinglées **et** empreintes SHA-256 vérifiées
  (`config/versions.yaml`).

## Variables

Les réglages partagés sont dans `ansible/group_vars/all.yml` (transmis par le CLI depuis
`config/lab.env`) ; les réglages propres à un rôle dans `roles/<rôle>/defaults/main.yml`.
Exemples de réglages avancés :

| Variable | Rôle | Exemple |
| --- | --- | --- |
| `control_plane_extra_cert_sans` | `control_plane` | `["k8s.example.lan"]` pour accéder à l'API par un nom DNS |
| `control_plane_kubelet_config` | `control_plane` | `{maxPods: 50}` (appliqué à tous les nœuds, peut remplacer `cgroupDriver`) |
| `control_plane_kube_proxy_config` | `control_plane` | `{mode: nftables}` ou `{mode: ipvs}` pour comparer les modes de kube-proxy |
| `control_plane_ignore_preflight_errors`, `worker_ignore_preflight_errors` | `control_plane`, `worker` | `["SystemVerification"]` (environnements particuliers uniquement) |
| `container_runtime_extra_config` | `container_runtime` | miroir de registre (TOML) |
| `container_runtime_systemd_cgroup` | `container_runtime` | `false` uniquement avec `cgroupDriver: cgroupfs` côté kubelet |
| `common_manage_etc_hosts` | `common` | `false` si `/etc/hosts` est géré ailleurs (conteneurs) |
| `common_require_cgroup_v2` | `common` | `false` uniquement pour un hôte ancien, avec `failCgroupV1: false` |
| `cni` | tous | `none` pour installer vous-même un autre CNI (sinon `CNI` dans `.env`) |

## Remettre à zéro

```bash
cd ansible
ansible-playbook -i inventories/<inventaire>.ini reset.yml -e reset_confirm=<nom-du-cluster>   # DESTRUCTIF
ansible-playbook -i inventories/<inventaire>.ini site.yml                          # recrée
```

## Ajouter un CNI

Créez `roles/cni/tasks/<nom>.yml` (en vous inspirant de `flannel.yml` ou `calico.yml` :
version verrouillée dans `config/versions.yaml`, checksum ou chart, attente), ajoutez `<nom>`
à la liste vérifiée dans `roles/cni/tasks/main.yml`, au schéma (`CNI`) et à la matrice de
compatibilité, puis à un scénario de `tests/kubeadm-in-docker` dans la CI.

## État de validation

- **En CI (GitHub Actions)** : `ansible-lint` (profil **production**, le plus strict), `yamllint`,
  `ansible-playbook --syntax-check`, et le test d'intégration `tests/kubeadm-in-docker` par le
  vrai CLI (`./k8s-lab deploy existing`) : Ubuntu 24.04/26.04, Debian 12/13, Rocky 9/10,
  Flannel, Calico, Cilium sans kube-proxy, 3 control-planes avec kube-vip, mise à niveau
  1.36 → 1.37, sauvegarde puis restauration etcd ; **2ᵉ déploiement sans aucun changement**,
  nœuds `Ready`, Pods système prêts, test nginx inter-nœuds (Service + DNS).
- **Tests manuels complémentaires** (hors CI) : ajout d'un 4ᵉ nœud sur un cluster existant
  sans toucher aux autres, refus d'un changement de version, `reset.yml` puis redéploiement,
  inventaire généré par les modules Terraform du dépôt.
- **Reste à valider sur de vraies VMs** (Vagrant, Proxmox, vSphere, libvirt) : cloud-init sur
  les images réelles, le réseau propre à chaque plateforme et le cas multi-cartes de Vagrant
  (`node-ip`, `FLANNELD_IFACE`).

### Le test d'intégration `tests/kubeadm-in-docker`

Il simule des VMs avec des conteneurs Docker privilégiés exécutant systemd, puis lance le
**vrai** `site.yml` dessus. C'est un test (ce n'est pas un mode de déploiement du lab) :

```bash
tests/kubeadm-in-docker/run.sh           # crée 1 control-plane + 2 workers, déploie, teste
tests/kubeadm-in-docker/run.sh --destroy # nettoie
```

Ce que les nœuds conteneurs ont de plus qu'une VM, pour s'en rapprocher (test uniquement,
jamais appliqué à vos machines) : montages en propagation partagée (`mount --make-rshared /`,
fait par systemd sur une vraie machine), SSH et sudo sans pile PAM « account » sur Rocky (voir
l'en-tête de `Dockerfile.rocky`).
