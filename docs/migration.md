# Migration depuis la version historique

La version d'origine (`run.sh` + `Vagrantfile` ESXi + `roles/`) déployait un cluster
kubeadm de 1 master + 3 workers sur un ESXi, avec Vagrant et Ansible. Elle a été entièrement
réécrite ; le principe pédagogique **VMs → Ansible → kubeadm → Kubernetes** est conservé et
généralisé.

## Correspondance

| Avant | Maintenant |
| --- | --- |
| `./run.sh` | `./k8s-lab deploy vagrant` (ou `make deploy MODE=vagrant`) |
| `run.sh` détruisait l'ancien cluster à chaque lancement | `deploy` ne détruit jamais ; `./k8s-lab destroy vagrant` (confirmation) ou `--recreate` |
| `vagrant provision worker-1`, `worker-2`, `worker-3` codés en dur | `WORKER_COUNT` (défaut 2), un seul playbook pour tous les nœuds |
| `snap.sh` | `cd vagrant && vagrant snapshot save <nom>` (voir [vagrant.md](vagrant.md)) |
| `Vagrantfile` à la racine, ESXi uniquement | `vagrant/Vagrantfile` : VirtualBox (défaut), libvirt, VMware Desktop, ESXi (`VAGRANT_PROVIDER=vmware_esxi`) |
| mot de passe ESXi, IP et MAC dans le `Vagrantfile` | `.env` (non versionné) ; IP calculées ; plus de réservation DHCP par MAC |
| groupes Ansible `masters` / `workers` | `control_plane` / `workers` (+ `k8s_cluster`) |
| hostnames `master`, `worker-1`… | `k8s-cp-1`, `k8s-worker-1`… (`NODE_HOSTNAME_PREFIX`) |
| `roles/main.yml`, `master.yml`, `worker.yml` | `ansible/site.yml` (+ `reset.yml`, `kubeconfig.yml`) |
| rôles `common`, `master`, `worker` | `common`, `container_runtime`, `kubernetes`, `control_plane`, `cni`, `worker` |
| Ubuntu 20.04 (`generic/ubuntu2004`) | Ubuntu 24.04 LTS (`bento/ubuntu-24.04`, images cloud datées) |
| Docker CE + containerd, `daemon.json` | containerd 2.x seul (Kubernetes n'utilise plus Docker depuis 1.24) |
| dépôt `apt.kubernetes.io` (`kubernetes-xenial`), `apt_key` | dépôt `pkgs.k8s.io`, `deb822_repository` + `Signed-By` |
| Flannel depuis la branche `master` | Flannel v0.28.9 épinglé + SHA-256 |
| `kubeadm reset -f` à chaque exécution, `ignore_errors` | exécution idempotente, erreurs expliquées |
| kubeconfig uniquement dans la VM | `.kube/config` sur votre poste (contexte `k8s-lab-vagrant`) |

## Audit de l'ancien code

Problèmes relevés et traités par la refonte :

- **Technologies obsolètes** : Ubuntu 20.04 (fin de support standard), dépôt Kubernetes
  `apt.kubernetes.io` fermé en 2024, `apt_key` obsolète, Docker comme dépendance du cluster,
  `config.toml` containerd au format v1 avec `systemd_cgroup` (option retirée), matériel
  virtuel ESXi 6.0 (`virtualhw 11`).
- **Idempotence** : `kubeadm reset -f` puis `kubeadm init` à chaque exécution (cluster détruit
  à chaque provision), `command: systemctl restart …`, `echo … >> ~/.bashrc` (lignes ajoutées
  à chaque exécution), `rm -rf` de fichiers du cluster sur les workers.
- **Erreurs masquées** : `ignore_errors: true` sur `kubeadm init`, sur la complétion et sur
  Flannel ; un échec passait inaperçu.
- **Réseau** : `/run/flannel/subnet.env` écrit à la main avec un sous-réseau `/24` identique
  sur tous les nœuds (c'est le rôle de Flannel de l'attribuer) ; `node-ip` défini en modifiant
  le fichier du paquet kubelet.
- **Sécurité** : mot de passe ESXi en clair, `join-command` sur le poste et en `0777`, clé
  SSH personnelle copiée dans les VMs, `.bashrc` tiers de 1 500 lignes (avec des fonctions
  d'envoi de fichiers vers des services publics) déployé en root. Voir [security.md](security.md).
- **Configuration** : IP/MAC/nombre de workers dupliqués entre `Vagrantfile`, `run.sh` et
  `snap.sh` ; `srv_ip` du control-plane codé en dur (`.26`) dans les variables Ansible.
- **Scripts** : `run.sh` et `snap.sh` sans `set -e` ni shebang (pour `snap.sh`), destruction
  non confirmée, bug de nommage (`snap-worker4` pour `worker-3`).
- **Documentation** : procédures obsolètes (OVF Tool 4.3 via X11, contournement d'un bug de
  box bento de 2021), liens VMware morts depuis le passage à Broadcom.

## Et mon ESXi autonome ?

Il reste utilisable avec `VAGRANT_PROVIDER=vmware_esxi` (voir
[vagrant.md](vagrant.md#mode-historique-esxi-autonome)). Deux différences : les identifiants
vont dans `.env`, et il faut deux port groups (accès + réseau privé du cluster) au lieu d'une
réservation DHCP par adresse MAC.
