# Stockage distribué Longhorn

Longhorn stocke chaque volume sur les disques des workers, en plusieurs **réplicas sur des
nœuds différents** : la perte d'un nœud ne perd pas les données (tant qu'un réplica sain
reste). Il ajoute instantanés, sauvegardes vers NFS/S3, extension de volume et une interface
web.

```bash
STORAGE_BACKENDS=longhorn            # ou nfs-csi,longhorn (+ DEFAULT_STORAGE_CLASS)
LONGHORN_VERSION=auto-compatible     # version verrouillée et compatible (config/versions.yaml)
LONGHORN_REPLICA_COUNT=3             # ≤ nombre de nœuds de stockage (vérifié)
LONGHORN_RECLAIM_POLICY=Retain
LONGHORN_DATA_PATH=/var/lib/longhorn
LONGHORN_DEDICATED_DISK=true         # disque dédié créé par Terraform/Vagrant (recommandé)
LONGHORN_DISK_SIZE_GB=100
LONGHORN_DISK_DATASTORE=local-lvm    # Proxmox/vSphere : stockage du disque dédié
```

## Prérequis des nœuds (installés par Ansible)

open-iscsi / iscsi-initiator-utils (+ `iscsid` actif, nom d'initiateur unique), client NFS
(volumes RWX), cryptsetup, device-mapper, modules `iscsi_tcp` et `dm_crypt`, exclusion des
disques Longhorn de multipathd. En mode attach, ils ne peuvent pas être installés : le test
de l'addon les vérifie (conditions des nœuds Longhorn).

## Disque dédié

Recommandé : isole les données du système, évite qu'un volume plein bloque le nœud.

| Plateforme | Disque créé | Repéré par |
| --- | --- | --- |
| Proxmox | `scsi1` de `LONGHORN_DISK_SIZE_GB` sur `LONGHORN_DISK_DATASTORE` | numéro de série `k8slab-longhorn` |
| vSphere | 2e disque SCSI (unité 1), provisionnement fin | adresse SCSI `x:0:1:0` |
| libvirt | `vdb` | numéro de série `k8slab-longhorn` |
| Vagrant | disque libvirt (`VAGRANT_PROVIDER=libvirt` uniquement) | numéro de série |
| existing | **le vôtre** : `LONGHORN_DISK_DEVICE=/dev/disk/by-id/...` | chemin explicite |

**Protections du rôle `storage_disk`** :

- un seul disque doit correspondre au sélecteur, sinon arrêt ;
- un disque qui contient **quoi que ce soit** (partitions, système de fichiers, LVM, montage)
  n'est **jamais** formaté : arrêt avec le détail ;
- un disque vierge n'est formaté (ext4, étiquette `k8slab-longhorn`) que s'il a été créé par
  le lab (numéro de série) **ou** si `LONGHORN_DISK_ALLOW_FORMAT=true` (mode existing) ;
- montage par étiquette dans `LONGHORN_DATA_PATH` (`nofail`), relancer est sans effet.

## Réplicas et topologie

- `LONGHORN_REPLICA_COUNT` ne peut pas dépasser le nombre de nœuds de stockage (workers, ou
  control-planes sans worker) : chaque réplica est sur un nœud distinct
  (`replicaSoftAntiAffinity=false`).
- Des VMs sur **un seul hyperviseur** (ex. un Proxmox) protègent d'une panne de VM, pas
  d'une panne de l'hôte ou de son stockage : avertissement du résolveur. Les sauvegardes
  hors de l'hyperviseur (NFS/S3) restent indispensables.
- Système : Longhorn 1.13 est vérifié par son projet sur Ubuntu 26.04 et Rocky 10 ; sur les
  autres OS, avertissement « non vérifié » (il fonctionne en général sur Ubuntu 24.04).

## Sauvegardes

```bash
LONGHORN_BACKUP_ENABLED=true
LONGHORN_BACKUP_TARGET=nfs://10.70.0.30:/volume1/longhorn-backup   # ou s3://bucket@region/
# S3 : LONGHORN_BACKUP_S3_ACCESS_KEY / LONGHORN_BACKUP_S3_SECRET_KEY / LONGHORN_BACKUP_S3_ENDPOINT dans .env
```

La cible doit exister. Les sauvegardes se lancent depuis l'interface ou par des
`RecurringJob` ; elles ne sont jamais supprimées par le framework.

## Interface web

Pas d'authentification : non exposée par défaut.
`kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80`, ou
`LONGHORN_UI_EXPOSE=true` (Gateway HTTPS, à protéger).

## Tests

- `make addons-test ADDON=longhorn` : nœuds Longhorn prêts et assez nombreux, volume
  `healthy` avec le bon nombre de réplicas sur des nœuds distincts, persistance des données
  (somme de contrôle) après recréation du Pod sur un autre nœud.
- `DESTRUCTIVE=1` ajoute la perte d'un **réplica** du volume de test (reconstruction, données
  intactes).
- Perte d'un **nœud** entier : test séparé, jamais lancé automatiquement, à lancer
  volontairement sur un cluster kubeadm avec au moins 2 workers et 2 réplicas :
  `make storage-failure-test MODE=<mode> NODE=<worker>` (nom du worker à retaper). Un
  Deployment écrit 32 Mio sur un volume Longhorn hébergé sur ce worker ; kubelet, tous les
  Pods puis containerd y sont arrêtés (la machine reste allumée) ; le test attend que le Pod
  redémarre sur un autre nœud (jusqu'à 15 minutes : éviction, détachement forcé par
  Longhorn) et compare la somme de contrôle. Containerd et kubelet sont **toujours**
  redémarrés, même en cas d'échec, puis le test attend la reconstruction des réplicas avant
  de supprimer son namespace et son volume (`ansible/storage-node-failure.yml`).

## Désinstallation

<a id="desinstallation"></a>Jamais automatique : Longhorn exige le drapeau
`deleting-confirmation-flag`, que le framework ne positionne pas. Procédure manuelle :
sauvegarder les volumes, supprimer les workloads et PVC concernés, puis
`kubectl -n longhorn-system patch settings.longhorn.io deleting-confirmation-flag --type=merge -p '{"value":"true"}'`
et `helm uninstall longhorn -n longhorn-system`. Les données sur les disques restent jusqu'à
leur effacement manuel.
