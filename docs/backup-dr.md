# Sauvegarde et reprise après sinistre

Deux niveaux complémentaires :

| Quoi | Outil | Restaure |
| --- | --- | --- |
| **état du cluster** (etcd : tous les objets Kubernetes) | instantané etcd (`make backup`), clusters kubeadm | le cluster entier, à un instant donné |
| **applications** (ressources d'un namespace + volumes) | Velero (`ADDONS=velero`) | des namespaces, sur ce cluster ou un autre |
| volumes Longhorn | sauvegardes Longhorn (`LONGHORN_BACKUP_TARGET`) | des volumes |

```bash
BACKUP_ENABLED=true
BACKUP_PROVIDER=both              # etcd-snapshot | velero | both
BACKUP_SCHEDULE=0 3 * * *         # cron (UTC) : timer systemd (etcd) et Schedule Velero
BACKUP_RETENTION_DAYS=7
```

## Instantanés etcd (kubeadm)

```bash
make backup MODE=existing         # tout de suite
```

Sur chaque control-plane : `etcdctl snapshot save`, vérification (`etcdutl snapshot status`),
copie dans `/var/backups/k8s-lab/etcd/` avec les certificats PKI (archive), rétention
`BACKUP_RETENTION_DAYS`, puis copie sur votre poste dans `.lab/backups/<contexte>/` (0600).
Avec `BACKUP_ENABLED=true`, un timer systemd (`k8s-lab-etcd-snapshot.timer`) les prend selon
`BACKUP_SCHEDULE`. Les anciennes sauvegardes du homelab ne sont jamais supprimées : seule la
rétention des instantanés créés par le lab s'applique.

⚠ Les instantanés contiennent **tous les Secrets** du cluster : stockez la copie locale
comme un secret (chiffrement du disque, accès restreint).

## Restauration etcd

<a id="restauration"></a>

```bash
ls .lab/backups/k8s-lab-existing/
make restore MODE=existing SNAPSHOT=.lab/backups/k8s-lab-existing/etcd-....db
```

Tapez le nom du cluster pour confirmer (`RESTORE_CONFIRM=<contexte>` en automatisation).
Sur chaque control-plane : arrêt de l'API et d'etcd (manifestes statiques mis de côté),
répertoire etcd actuel **conservé** (`/var/lib/etcd.before-restore-<date>`), restauration
(`etcdutl snapshot restore` avec la topologie du cluster), redémarrage, vérification de la
santé. Tout ce qui a été créé après l'instantané est perdu ; les volumes ne sont pas
restaurés (Velero / Longhorn).

La CI exerce la restauration à chaque push (1 control-plane) : ConfigMap créée avant
l'instantané présente, ConfigMap créée après absente.

## Velero

Sauvegarde vers un stockage S3 **existant** (MinIO, Garage, NAS compatible S3...) : le
compartiment n'est jamais créé ni vidé.

```bash
ADDONS=velero
VELERO_S3_URL=http://10.70.0.30:9000
VELERO_BUCKET=velero
VELERO_FS_BACKUP=true             # volumes par copie de fichiers (node agent, kopia)
# .env : VELERO_S3_ACCESS_KEY / VELERO_S3_SECRET_KEY
```

```bash
velero backup create demo --include-namespaces demo        # CLI velero, ou une ressource Backup
velero restore create --from-backup demo
```

Le test de l'addon sauvegarde un namespace de test, supprime une ressource, restaure,
vérifie, puis supprime **uniquement** sa propre sauvegarde (durée de vie 1 h).

## Exercice de reprise conseillé (homelab)

1. `make backup`, puis une sauvegarde Velero des namespaces applicatifs ;
2. sur un cluster de test (ex. Vagrant ou kind pour Velero), restaurer ;
3. noter la durée et les écarts : c'est votre RTO/RPO réel.
