# Mode existing : Kubernetes sur des machines existantes

Le mode `existing` installe Kubernetes (kubeadm) sur des machines Linux **qui existent
déjà** : serveurs bare metal, VMs créées à la main, machines d'un autre outil. Le framework
ne crée ni ne supprime aucune machine.

## 1. Décrire les machines

Un inventaire Ansible (modèle : `ansible/inventories/existing.example.ini`) :

```ini
[control_plane]
k8s-cp-1 ansible_host=10.20.0.100 node_ip=10.20.0.100

[workers]
k8s-worker-1 ansible_host=10.20.0.101 node_ip=10.20.0.101
k8s-worker-2 ansible_host=10.20.0.102 node_ip=10.20.0.102
k8s-worker-3 ansible_host=10.20.0.103 node_ip=10.20.0.103

[k8s_cluster:children]
control_plane
workers

[k8s_cluster:vars]
ansible_user=admin
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

Exigences : SSH par **clé** (un mot de passe dans l'inventaire est refusé), `sudo` sans mot
de passe pour `ansible_user`, Python 3, accès Internet (ou proxy) vers les dépôts
`pkgs.k8s.io`, `download.docker.com`, `registry.k8s.io` et les registres des addons.

## 2. Configurer

```bash
# .env
DEPLOYMENT_MODE=existing
EXISTING_INVENTORY=ansible/inventories/homelab.ini
CONTROL_PLANE_COUNT=1          # doit correspondre à l'inventaire (vérifié)
WORKER_COUNT=3
NODE_OS=auto                   # chaque machine est identifiée puis comparée à la matrice
CNI=cilium
GATEWAY_CONTROLLER=cilium
STORAGE_BACKENDS=nfs-csi,longhorn
ADDONS=metrics-server,cert-manager,argo-cd
```

`NODE_OS=auto` : la distribution de chaque machine est détectée ; une distribution hors de la
matrice ([compatibility.md](compatibility.md#systèmes-dexploitation-des-nœuds-modes-kubeadm))
est refusée.

## 3. Vérifier, puis déployer

```bash
make doctor MODE=existing      # outils, inventaire, SSH (ansible ping), configuration
make deploy MODE=existing
```

`make deploy` enchaîne :

1. validation de la configuration et de l'inventaire (rien n'est contacté) ;
2. <a id="controles-prealables"></a>**contrôles préalables en lecture seule** (`ansible/preflight.yml`) :
   distribution et version, architecture, cgroup v2, CPU/mémoire, espace libre de `/var`,
   unicité des product_uuid et adresses MAC, **appartenance à un cluster existant**, sudo,
   ports Kubernetes libres (6443, 2379-2380, 10250, 10257, 10259…), paquets en conflit
   (containerd/runc des dépôts de la distribution, k3s, rke2, microk8s, kubectl snap…),
   Docker présent, résolution DNS des dépôts, synchronisation de l'heure, firewalld/ufw,
   SELinux ;
3. **affichage des changements prévus** (paquets, dépôts, fichiers, pare-feu, swap) ;
4. **confirmation** ;
5. installation : prérequis, containerd, paquets Kubernetes gelés, kubeadm, CNI, HA ;
6. kubeconfig (`.kube/config`, contexte `<CLUSTER_NAME>-existing`), tests, addons, manifeste.

Relancer est sans risque : seul ce qui manque est fait.

## Protections

| Toujours | Jamais |
| --- | --- |
| ouvrir les ports nécessaires dans firewalld/ufw s'ils sont actifs | désactiver le pare-feu, SELinux ou AppArmor |
| conserver les données et la configuration existantes | modifier partitions, réseau, utilisateurs, hostname, `/etc/hosts` |
| refuser une machine déjà membre d'un cluster | `kubeadm reset` automatique |
| expliquer un conflit (paquet, port, service) | désinstaller un paquet ou arrêter un service sans rapport |
| refuser un disque Longhorn non vide | formater un disque sans `LONGHORN_DISK_DEVICE` explicite **et** `LONGHORN_DISK_ALLOW_FORMAT=true` |

Le swap est désactivé (`NODE_SWAP=disable`, défaut, entrées commentées dans `/etc/fstab`) ;
`NODE_SWAP=keep` le conserve (kubelet configuré en `LimitedSwap`).

### Disque Longhorn sur une machine existante

```bash
LONGHORN_DEDICATED_DISK=true
LONGHORN_DISK_DEVICE=/dev/disk/by-id/ata-WDC_WD10EZEX-xxxxxxxx   # chemin stable, jamais /dev/sdb
LONGHORN_DISK_ALLOW_FORMAT=true                                   # seulement si le disque est VIDE
```

Un chemin différent par machine : variable d'inventaire `longhorn_disk_device=...` sur chaque hôte.

## Réutiliser une machine

<a id="reutiliser-une-machine"></a>Une machine qui porte déjà un cluster (fichiers
`/etc/kubernetes`, kubelet configuré) est refusée. Si vous êtes **certain** de vouloir la
réutiliser : sauvegardez ses données, puis sur la machine `sudo kubeadm reset`, supprimez
`/etc/cni/net.d`, et relancez le déploiement. Le framework ne le fait jamais à votre place.

## Désinstaller

<a id="desinstallation"></a>`make destroy MODE=existing` est **refusé** : les machines ne
sont pas gérées par le framework. Pour retirer Kubernetes :

```bash
make uninstall MODE=existing        # tapez le nom du cluster pour confirmer
```

Instantané etcd préalable, puis sur chaque nœud : `kubeadm reset`, nettoyage des
interfaces et de la configuration du CNI. Conservés : les machines, leurs données, les
paquets, les volumes Longhorn sur disque, les données NFS.

## HA sur machines existantes

Trois ou cinq machines dans `[control_plane]`, `CONTROL_PLANE_COUNT=3` et une VIP libre :
[high-availability.md](high-availability.md).

## Tests

La CI déploie ce mode à chaque push sur des « machines » conteneurs systemd (Ubuntu 24.04,
Debian 12/13, Rocky 9 ; HA 3 control-planes) par la commande réelle
`./k8s-lab deploy existing`. Ce n'est pas un test sur bare metal : les vérifications noyau,
disques et pare-feu réels restent à valider sur vos machines.
