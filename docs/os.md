# Systèmes d'exploitation des nœuds

Les modes kubeadm (vagrant, terraform proxmox/vsphere/libvirt, existing) supportent :

| `NODE_OS` | `NODE_OS_VERSION` | Statut | Famille | Gestionnaire | Utilisateur cloud |
| --- | --- | --- | --- | --- | --- |
| `ubuntu` | `24.04` (défaut) | supporté | debian | APT | `ubuntu` |
| `ubuntu` | `26.04` | expérimental | debian | APT | `ubuntu` |
| `debian` | `12`, `13` | supporté | debian | APT | `debian` |
| `rocky` | `9` | supporté | redhat | DNF | `rocky` |
| `rocky` | `10` | expérimental (CPU x86-64-v3 requis) | redhat | DNF | `rocky` |
| `auto` | — | mode existing : détecté sur chaque machine | | | |

Matrice détaillée (noyau, image épinglée, tests) : [compatibility.md](compatibility.md).
kind, minikube, EKS et attach ignorent `NODE_OS` (information affichée).

## Images

`NODE_IMAGE_SOURCE` :

- `catalog` (défaut) : image cloud officielle **datée**, SHA-256 verrouillé dans
  `config/versions.yaml` ; Proxmox la télécharge et la vérifie lui-même, le CLI la vérifie
  pour libvirt ;
- `url` : `NODE_IMAGE_URL` + `NODE_IMAGE_SHA256` obligatoires (image personnalisée) ;
- `template` : `NODE_TEMPLATE_ID` (ID de template Proxmox, nom de template vSphere) ; vSphere
  fonctionne toujours par template.

Debian : images `generic` (noyau complet : `iscsi_tcp` et `dm_crypt`, requis par Longhorn,
sont absents des images `genericcloud`).

## Différences gérées par les rôles Ansible

| Sujet | Ubuntu / Debian | Rocky Linux |
| --- | --- | --- |
| Dépôts | deb822 + `Signed-By` | `yum_repository` + GPG |
| Gel des paquets | `dpkg` hold | exclusion dans le dépôt (`disable_excludes` à l'installation) |
| Sécurité | AppArmor actif (profil par défaut de containerd) | SELinux **enforcing** conservé, `container-selinux`, contexte de `/var/lib/etcd` |
| Pare-feu | ufw (si actif) | firewalld (si actif) |
| iSCSI (Longhorn) | `open-iscsi` | `iscsi-initiator-utils` |
| Groupe admin (cloud-init) | `sudo` | `wheel` |

## CPU : Rocky Linux 10 et les vieux processeurs

RHEL 10 / Rocky 10 exigent le niveau **x86-64-v3** (AVX2). Un Xeon X5690 (Westmere, Dell
T610) n'est que **x86-64-v2** : Rocky 10 n'y démarre pas, même en VM. Le résolveur le
refuse avec `NODE_CPU_TYPE=x86-64-v2-AES` (défaut, compatible Westmere). Sur ce matériel :
Ubuntu 24.04, Debian 12/13 ou Rocky 9.

## Noyau et Cilium

Cilium exige un noyau ≥ 5.10 (toutes les distributions supportées le dépassent ; Rocky 9 :
5.14 avec rétroportages). La vérification est faite par le résolveur (catalogue) et au
démarrage de Cilium.
