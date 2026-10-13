# Stockage NFS (NFS CSI)

Le pilote officiel `nfs.csi.k8s.io` crée **un sous-dossier par volume** dans un export NFS
**qui existe déjà** sur votre NAS. Le framework ne crée, ne modifie et ne supprime jamais
l'export, ses droits ni le NAS.

```bash
STORAGE_BACKENDS=nfs-csi
NFS_SERVER=10.70.0.30
NFS_SHARE=/volume1/kubernetes
NFS_VERSION=4.1
NFS_RECLAIM_POLICY=Retain
NFS_MOUNT_OPTIONS=hard
NFS_SUBDIR=${pvc.metadata.namespace}-${pvc.metadata.name}-${pv.metadata.name}
```

## Préparer l'export (Synology DSM, à faire par vous)

1. **Panneau de configuration → Services de fichiers → NFS** : activer NFS, version
   maximale NFSv4.1.
2. **Dossier partagé** `kubernetes` (volume1) → **Modifier → Autorisations NFS → Créer** :
   - Nom d'hôte ou IP : le réseau des nœuds uniquement (ex. `10.20.0.100/30`, ou chaque
     IP de nœud), **pas** `*` ;
   - Privilège : lecture/écriture ;
   - Squash : *Aucun mappage* (`no_root_squash`) si des Pods écrivent en root et pour que
     `fsGroup` fonctionne ; sinon *Mapper root sur admin* et des Pods non root ;
   - Sécurité : `sys` ; cocher *Autoriser les connexions depuis les ports non privilégiés*
     uniquement si nécessaire.
3. Notez le chemin affiché en bas (ex. `/volume1/kubernetes`) : c'est `NFS_SHARE`.

`/volume1/kubernetes` n'est qu'une **proposition** : utilisez votre export réel.

## Réseau

Les nœuds doivent joindre le NAS en TCP 2049 (NFSv4 n'utilise que ce port). Si le NAS est
sur un autre VLAN (ex. NAS en `10.70.0.0/16`, nœuds en `10.20.0.0/16`), autorisez ce flux
sur votre pare-feu inter-VLAN (Stormshield...) : **le framework ne modifie jamais votre
pare-feu**. Test depuis un nœud :

```bash
ssh ubuntu@10.20.0.101 'sudo mkdir -p /mnt/t && sudo mount -t nfs4 -o vers=4.1 10.70.0.30:/volume1/kubernetes /mnt/t && ls /mnt/t; sudo umount /mnt/t'
```

## Utilisation

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: partage, namespace: demo}
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-csi
  resources: {requests: {storage: 5Gi}}
```

La taille n'est pas un quota : le sous-dossier peut grossir jusqu'à remplir l'export
(quotas : côté NAS).

## Test

`make addons-test ADDON=nfs-csi` : volume RWX, écriture par un utilisateur non root,
lecture depuis un autre nœud, persistance après recréation du Pod. Le volume de test est
supprimé à la fin (copie de la StorageClass en `Delete`, sous-dossier `k8s-lab-test-nfs-csi-*`).

## Données conservées

En `Retain`, supprimer un PVC laisse le PV (`Released`) et le sous-dossier sur le NAS.
Nettoyage manuel, après vérification : `kubectl delete pv <pv>` puis suppression du
sous-dossier sur le NAS. Désinstaller l'addon ne touche ni aux PV ni au NAS.
