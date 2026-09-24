# Sécurité et secrets

Un lab pédagogique doit montrer les bonnes pratiques, pas les contourner.

## Règles

1. **Aucun secret dans Git.** Identifiants Proxmox, vCenter et ESXi : uniquement dans `.env`
   (ignoré par Git), lus comme variables d'environnement par les outils. Identifiants AWS :
   mécanismes standards d'AWS (`aws configure`, `AWS_PROFILE`), hors du dépôt.
2. Les fichiers **versionnés** sont des exemples génériques : `.env.example`,
   `terraform.tfvars.example`, `ansible/inventories/example.ini` (adresses de documentation
   `192.0.2.0/24`).
3. Les fichiers **générés** sont ignorés par Git et privés : `.lab/` (0700), `.kube/` (0700),
   kubeconfigs (0600), plans Terraform (0600, supprimés après usage).

## Ce qui est sensible, et où

| Élément | Emplacement | Protection |
| --- | --- | --- |
| Token API Proxmox, mot de passe vCenter / ESXi | `.env` | ignoré par Git ; jamais écrit dans un fichier Terraform ou Vagrant ; variables Terraform non utilisées pour les secrets |
| Identifiants AWS | `~/.aws/` (profils) ou variables d'environnement | hors du dépôt ; kubectl obtient à chaque commande un jeton EKS temporaire (`aws eks get-token`), aucun jeton n'est écrit dans le kubeconfig |
| Clé SSH du lab | `.lab/ssh/id_ed25519` | générée pour le lab (0600) : votre clé personnelle n'est pas distribuée sur les VMs |
| kubeconfig (certificat administrateur du cluster) | `.kube/config`, `.kube/clusters/*.yaml` | 0600 ; `~/.kube/config` n'est jamais modifié |
| State Terraform | `terraform/providers/<p>/terraform.tfstate` | ignoré par Git ; **peut contenir des données sensibles**, ne pas le partager |
| Plan Terraform | `.lab/terraform/<p>.tfplan` | créé en 0600, supprimé après `apply` |
| Jetons `kubeadm join` | mémoire d'Ansible | durée de vie 15 min, `no_log`, fichier de join supprimé ; aucun `join-command` sur disque |
| Clés d'hôte SSH des VMs | `.lab/known_hosts` | `StrictHostKeyChecking=accept-new` : une clé qui change est refusée ; les entrées sont retirées au `destroy` |

## Téléchargements et intégrité

| Artefact | Épinglage | Vérification |
| --- | --- | --- |
| Paquets Kubernetes | version exacte (`kubeadm=1.37.1-*`) + `apt-mark hold` | signature APT (`Signed-By` dédié, pas d'`apt-key`) |
| containerd | dépôt Docker officiel, motif `2.3.*` | signature APT (`Signed-By` dédié) |
| Manifeste Flannel | release `v0.28.9` (jamais `master`) | SHA-256 |
| Image cloud Ubuntu | release datée (`release-20260911`), jamais `current` | SHA-256 (par Proxmox, ou par le CLI pour libvirt) |
| Image de nœud kind | tag + **digest** | digest |
| Collections Ansible | versions exactes (`requirements.yml`) | Galaxy |
| Providers Terraform | contraintes `~>` + `.terraform.lock.hcl` versionné | hashes du lock file |
| Outils de la CI et de `scripts/install-tools.sh` (kind, kubectl, minikube, Vagrant, actionlint) | versions exactes (`config/lab.env`) | SHA-256 publié par chaque projet |
| Image LocalStack (facultative, EKS) | version datée (`2026.08.4`), jamais `latest` | registre Docker Hub |
| Actions GitHub | SHA de commit (version en commentaire) | mises à jour proposées par Dependabot |

## AWS EKS

- **Moindre privilège** : le rôle du control-plane n'a que `AmazonEKSClusterPolicy` ; celui
  des workers, les trois politiques gérées recommandées par AWS (`AmazonEKSWorkerNodePolicy`,
  `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKS_CNI_Policy`). Aucun `AdministratorAccess`.
- **API Kubernetes filtrée** : le point d'accès public n'accepte que votre adresse IP
  (`api_allowed_cidrs`, détectée par le CLI) ; les workers passent par le point d'accès privé.
- **Workers sans port ouvert** : ils ont une IP publique (pas de NAT, pour la simplicité) mais
  le groupe de sécurité créé par EKS n'accepte que le trafic interne au cluster.
- **Accès au cluster** : l'identité AWS qui crée le cluster en devient administratrice
  (entrée d'accès EKS) ; kubectl s'authentifie avec cette même identité.
- **LocalStack** : les identifiants factices `test` et la désactivation des contrôles du
  provider ne s'appliquent qu'avec `aws_target = "localstack"`, jamais au vrai AWS.
- **Coûts** : aucune CI automatique ne crée de ressource AWS ; le test EKS réel est un
  workflow déclenché à la main, qui détruit le cluster même en cas d'échec (`if: always()`).

## Sur les VMs

- Connexion SSH **par clé uniquement** (`ssh_pwauth: false`, pas de mot de passe
  utilisateur, root désactivé) ; `sudo` sans mot de passe pour l'utilisateur de déploiement.
- Fichiers de configuration kubeadm en 0600 ; aucun fichier en `0777`.
- Scripts : aucun `curl | bash`, aucun script exécuté en root depuis Internet.

## Audit de l'ancienne version (corrigé)

| Problème | Correction |
| --- | --- |
| Mot de passe ESXi en clair dans le `Vagrantfile` (`ESXI_PASS = "password"`) | supprimé : `ESXI_PASSWORD` dans `.env`, lu par le plugin (`env:`) |
| IP et adresses MAC personnelles dans le `Vagrantfile` | supprimées : IP calculées depuis la configuration |
| `join-command` écrit sur le poste, copié en `/tmp` avec le mode `0777` | jeton éphémère en mémoire, fichier 0600 supprimé après usage |
| Script de complétion copié en `0777` | fichier généré en 0644 |
| `apt_key` (obsolète) et dépôt `apt.kubernetes.io` (fermé) | `deb822_repository` + `Signed-By`, dépôt `pkgs.k8s.io` |
| Flannel téléchargé depuis la branche `master` | release épinglée + SHA-256 |
| `.bashrc` de 1 500 lignes déployé (fonctions d'envoi de fichiers vers `transfer.sh`/`qbin.io`, chemin personnel) | supprimé ; seuls la complétion kubectl et l'alias `k` sont installés |
| Clé `~/.ssh/id_rsa` personnelle copiée dans les VMs | clé dédiée au lab |
| Destruction systématique du cluster au lancement (`run.sh`) | destruction uniquement explicite, avec confirmation |

## Pour aller plus loin (hors périmètre du lab)

- State Terraform dans un backend distant chiffré, avec verrouillage.
- Coffre de secrets (Vault, SOPS) plutôt qu'un fichier `.env`.
- Durcissement Kubernetes : RBAC par utilisateur, NetworkPolicies (nécessitent un CNI qui les
  applique, comme Calico ou Cilium), Pod Security Admission.
