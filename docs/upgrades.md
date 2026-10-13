# Mises à jour

Trois types de mises à jour, toujours **planifiées** puis **exécutées** après confirmation :

| Quoi | Plan | Exécution |
| --- | --- | --- |
| Kubernetes (kubeadm) | `make upgrade-plan` | `make upgrade` |
| Addons | `make addons-upgrade` (affiche le plan, demande confirmation) | idem |
| Système des nœuds | — | `make os-update` |
| Versions verrouillées | `make versions-check` | modifier `config/versions.yaml` |

## Kubernetes

```bash
# 1. choisir la version cible dans .env
KUBERNETES_VERSION=1.37.1
# 2. plan (lecture seule)
make upgrade-plan MODE=existing
# 3. exécution
make upgrade MODE=existing
```

Le plan (`scripts/labcore/upgrade.py`) vérifie :

- une seule mineure à la fois (1.35 → 1.37 refusé, avec le chemin 1.35.x → 1.36.x → 1.37.x) ;
- pas de rétrogradation ;
- `UPGRADE_POLICY=patch` (défaut) : seuls les correctifs ; `minor` : mineure suivante ;
- écart de version des kubelets (au plus 3 mineures sous l'API, jamais au-dessus) ;
- tous les nœuds `Ready` ;
- compatibilité de chaque addon et du CNI avec la version cible.

L'exécution (`ansible/upgrade.yml`) suit la procédure officielle de kubeadm : instantané
etcd, dépôt de paquets de la nouvelle mineure, `kubeadm upgrade apply` sur le premier
control-plane, `kubeadm upgrade node` sur les autres **un par un**, puis pour chaque nœud :
drain, kubelet/kubectl, redémarrage du kubelet, uncordon (même en cas d'échec). Prévoyez des
`PodDisruptionBudget` pour vos applications. Confirmation : taper le nom du cluster
(`UPGRADE_CONFIRM=<contexte>`).

La CI teste 1.36.5 → 1.37.1 à chaque push. kind et minikube : recréer le cluster ; EKS :
`EKS_KUBERNETES_VERSION` puis `make deploy MODE=terraform PROVIDER=eks`.

## Addons

<a id="addons"></a>

```bash
make addons-upgrade MODE=kind
```

Compare les versions installées (ConfigMap `k8s-lab-system/k8s-lab-addons`) au plan, liste
les installations et mises à jour, demande confirmation, applique, puis teste. Une
**rétrogradation** est refusée (CRD et schémas de données). Lisez les notes de version des
composants concernés : certaines mises à jour majeures demandent une migration (CRD
cert-manager, schéma Loki, Kyverno...).

## Système des nœuds

```bash
make os-update MODE=existing
```

Nœud par nœud : drain, mises à jour des paquets du système (APT : `upgrade` ; DNF : toutes
les mises à jour disponibles), **sans** toucher aux paquets Kubernetes et containerd (gelés :
`dpkg` hold sur Ubuntu/Debian, exclusion dans les dépôts DNF sur Rocky), redémarrage si
nécessaire (`/var/run/reboot-required`, `dnf needs-restarting --reboothint`), attente du
retour `Ready`, uncordon.

## Versions verrouillées

```bash
make versions-check
```

Interroge les dépôts officiels (dl.k8s.io, index Helm, registres OCI, tags Git) et liste
les nouveautés (correctif / mineure / majeure). Rien n'est installé : modifiez
`config/versions.yaml` dans une branche, laissez la CI valider (rendu de tous les addons,
déploiements réels), puis mettez à jour. Détail : [versions.md](versions.md).
