# Ansible + kubeadm : comment le cluster est construit

Quel que soit l'outil qui a créé les VMs (Vagrant ou Terraform), c'est le même playbook,
`ansible/site.yml`, qui installe Kubernetes. Il suit la documentation officielle
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

Il est **généré** (`inventories/vagrant.ini`, `inventories/terraform-<provider>.ini`) ;
`inventories/example.ini` montre comment l'écrire à la main pour des VMs existantes.
Le nombre de workers n'est écrit nulle part ailleurs : il suffit d'ajouter une ligne.

## Les étapes (`ansible/site.yml`)

| Étape | Rôle | Ce qui se passe |
| --- | --- | --- |
| 0 | *(play 1)* | attente SSH, attente de la fin de cloud-init, collecte des faits |
| 1 | `common` | contrôle OS + **cgroup v2**, hostname, `/etc/hosts`, swap désactivé, modules `overlay` et `br_netfilter`, sysctl (`ip_forward`, `bridge-nf-call-iptables`) |
| 2 | `container_runtime` | dépôt Docker (format deb822, clé dédiée), paquet `containerd.io` 2.x, `SystemdCgroup = true`, image `pause`, `crictl` ; vérification de la config effective |
| 3 | `kubernetes` | dépôt `pkgs.k8s.io` de la version mineure, `kubelet`/`kubeadm`/`kubectl` **à la version exacte**, puis `apt-mark hold` |
| 4 | `control_plane` | `kubeadm init --config /etc/kubernetes/kubeadm-config.yaml` (une seule fois), kubeconfig pour l'utilisateur SSH |
| 5 | `cni` | Flannel : manifeste de release téléchargé (SHA-256 vérifié), adapté par Kustomize, appliqué |
| 6 | `worker` | jeton de 15 min créé sur le control-plane, `kubeadm join --config …`, suppression du fichier, label `worker` |
| 7 | *(play final)* | tous les nœuds `Ready`, Pods système prêts, kubeconfig exporté vers `.kube/clusters/` |

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
explicatif : une mise à jour se fait avec `kubeadm upgrade`, pas par un changement de paquet.

## Sécurité

- Aucun `join-command` n'est écrit sur votre poste ni laissé sur les VMs : le jeton (15 min)
  circule en mémoire (`no_log`) et le fichier de configuration du join est supprimé.
- Le jeton créé par `kubeadm init` expire aussi au bout de 15 minutes.
- Le CA du cluster est vérifié par les workers (`caCertHashes`).
- Fichiers sensibles en `0600` (config kubeadm, kubeconfig) ; aucun `0777`.
- Manifeste Flannel : version épinglée **et** empreinte SHA-256 vérifiée.

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
| `cni` | tous | `none` pour installer vous-même Calico ou Cilium |

## Remettre à zéro

```bash
cd ansible
ansible-playbook -i inventories/<inventaire>.ini reset.yml -e reset_confirm=true   # DESTRUCTIF
ansible-playbook -i inventories/<inventaire>.ini site.yml                          # recrée
```

## Ajouter un CNI

Créez `roles/cni/tasks/<nom>.yml` (en vous inspirant de `flannel.yml` : version épinglée,
checksum, `kubectl apply`, attente), et ajoutez `<nom>` à la liste vérifiée dans
`roles/cni/tasks/main.yml`.

## État de validation

- **En CI (GitHub Actions)** : `ansible-lint` (profil **production**, le plus strict), `yamllint`,
  `ansible-playbook --syntax-check`, et le test d'intégration `tests/kubeadm-in-docker` : le
  playbook complet sur 1 control-plane + 2 workers (conteneurs systemd Ubuntu 24.04, cgroup v2,
  driver cgroup `systemd` par défaut), **2ᵉ exécution avec `changed=0`**, nœuds `Ready`, Pods
  système prêts, test nginx inter-nœuds (Service + DNS).
- **Pendant la refonte** (en plus) : ajout d'un 4ᵉ nœud sur un cluster existant sans toucher
  aux autres, refus d'un changement de version, `reset.yml` puis redéploiement, inventaire
  généré par les modules Terraform du dépôt.
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
