# Stockage persistant

Deux backends de stockage peuvent être installés, seuls ou ensemble :

| Backend | Volumes | Pour |
| --- | --- | --- |
| `nfs-csi` | un sous-dossier d'un export NFS existant (NAS) ; RWO **et** RWX | données partagées, sauvegardes, volumes simples ; dépend du NAS |
| `longhorn` | bloc répliqué sur les disques des workers ; RWO (RWX via NFS interne) | bases de données, volumes performants, instantanés ; dépend des nœuds |

```bash
STORAGE_BACKENDS=nfs-csi,longhorn
DEFAULT_STORAGE_CLASS=longhorn     # auto : le seul backend choisi ; obligatoire s'il y en a deux
```

- Une **seule** StorageClass par défaut : le framework retire l'annotation par défaut des
  autres StorageClasses (kind/minikube : `standard`) sans en supprimer aucune.
- Politique `Retain` par défaut (`NFS_RECLAIM_POLICY`, `LONGHORN_RECLAIM_POLICY`) : supprimer
  un PVC ne supprime pas les données. `Delete` est accepté avec un avertissement.
- Les tests fonctionnels utilisent une **copie** de la StorageClass en politique `Delete`,
  supprimée à la fin : aucun volume de test ne reste sur le NAS ou les disques.

## Kind, minikube, EKS

kind et minikube ont déjà une StorageClass `standard` (disque local du nœud). NFS CSI
fonctionne si le serveur est joignable depuis les nœuds (la CI utilise un serveur NFS de
test dans le cluster) ; Longhorn est refusé (il exige open-iscsi et de vrais disques). Sur
EKS, utilisez les volumes EBS/EFS d'AWS.

## Instantanés

<a id="instantanés"></a>L'addon `snapshot-controller` installe les CRD `VolumeSnapshot` et
le contrôleur officiel. Les `VolumeSnapshotClass` sont créées pour les backends présents
(`nfs-csi-snapclass` : archive du sous-dossier ; `longhorn-snapshot` : instantané Longhorn),
toujours en `deletionPolicy: Retain`.

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: db-avant-migration, namespace: demo}
spec:
  volumeSnapshotClassName: longhorn-snapshot
  source: {persistentVolumeClaimName: db}
```

Guides : [NFS (Synology)](storage-nfs.md) · [Longhorn](storage-longhorn.md) ·
sauvegardes : [backup-dr.md](backup-dr.md).
