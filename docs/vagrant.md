# Mode Vagrant (VMs + Ansible + kubeadm)

[Vagrant](https://developer.hashicorp.com/vagrant) crée des VMs à partir d'un seul fichier,
`vagrant/Vagrantfile`. Kubernetes est ensuite installé par Ansible avec kubeadm — exactement
comme sur les VMs créées par Terraform.

## Prérequis

| Provider (`VAGRANT_PROVIDER`) | Pour qui | À installer |
| --- | --- | --- |
| `virtualbox` (défaut) | Linux, Windows, macOS Intel | [VirtualBox](https://www.virtualbox.org/wiki/Downloads) |
| `libvirt` | Linux avec KVM | `qemu-kvm libvirt-daemon-system` + `vagrant plugin install vagrant-libvirt` |
| `vmware_desktop` | VMware Workstation / Fusion | Vagrant VMware Utility + `vagrant plugin install vagrant-vmware-desktop` |
| `vmware_esxi` | ESXi autonome (mode historique) | `vagrant plugin install vagrant-vmware-esxi` + VMware OVF Tool |

Dans tous les cas : Vagrant, Ansible (ansible-core ≥ 2.18, `pipx install --include-deps ansible`),
un client SSH et kubectl. Comptez ~2 Go de RAM par VM (3 VMs par défaut).

```bash
./k8s-lab doctor vagrant
```

## Utilisation

```bash
./k8s-lab deploy vagrant                     # ou make deploy MODE=vagrant
WORKER_COUNT=3 ./k8s-lab deploy vagrant      # ajoute un worker, garde les VMs existantes
./k8s-lab destroy vagrant
```

Étapes :

1. `vagrant up` crée `k8s-cp-1`, `k8s-worker-1`, `k8s-worker-2` (box `bento/ubuntu-24.04`)
   avec un réseau privé `192.168.56.10`, `.11`, `.12`…
2. Après le démarrage, le Vagrantfile écrit **l'inventaire Ansible**
   `ansible/inventories/vagrant.ini` à partir des informations SSH de chaque VM.
3. `ansible-playbook site.yml` installe Kubernetes (voir [ansible-kubeadm.md](ansible-kubeadm.md)).
4. Le kubeconfig est ajouté à `.kube/config` (contexte `k8s-lab-vagrant`).

Chaque étape peut être lancée à la main pour comprendre :

```bash
cd vagrant && vagrant up && vagrant status && cd ..
cd ansible && ansible-playbook -i inventories/vagrant.ini site.yml
cd vagrant && vagrant ssh k8s-cp-1           # dans la VM : kubectl get nodes, sudo crictl ps
```

## Réseau : pourquoi `node-ip` ?

Une VM Vagrant a **deux cartes réseau** : une carte NAT (accès Internet, la même IP
`10.0.2.15` sur toutes les VMs avec VirtualBox) et une carte privée (`192.168.56.x`). Si
Kubernetes utilisait la carte NAT, les nœuds ne pourraient pas se joindre. Le lab indique donc
explicitement l'IP privée au kubelet (`node-ip`) et à Flannel (`FLANNELD_IFACE`). C'est un
problème classique des clusters multi-cartes, bon à connaître.

## Mode historique ESXi autonome

La version d'origine de ce projet déployait sur un ESXi avec le plugin `vagrant-vmware-esxi`.
Ce mode reste disponible, **sans mot de passe dans le code** :

```bash
# .env
VAGRANT_PROVIDER=vmware_esxi
ESXI_HOSTNAME=esxi.example.lan
ESXI_USERNAME=root
ESXI_PASSWORD=...                     # lu par le plugin via "env:ESXI_PASSWORD"
ESXI_DATASTORE=datastore1
ESXI_NETWORKS=VM Network,K8S Network  # 1er : DHCP/accès, 2e : IP privées du cluster
```

Limites à connaître :

- le plugin n'est plus maintenu depuis 2022 (dernière version 2.5.5) : ce mode est fourni
  « au mieux » ;
- il nécessite VMware OVF Tool sur votre poste ;
- il faut **deux** port groups : le plugin ne sait fixer une IP statique que sur une carte
  supplémentaire (d'où la réservation DHCP par adresse MAC de l'ancienne version, supprimée) ;
- Terraform ne peut pas remplacer ce mode : le provider vSphere exige un vCenter pour cloner
  des VMs (voir [terraform-vsphere.md](terraform-vsphere.md)).

## Autres remarques

- La taille du disque est celle de la box (`NODE_DISK_GB` ne s'applique qu'à Terraform).
- `vagrant up` sans le CLI fonctionne aussi : le Vagrantfile lit `config/lab.env` et `.env`.
- Instantanés (remplace l'ancien `snap.sh`) : `cd vagrant && vagrant snapshot save avant-tp`
  puis `vagrant snapshot restore avant-tp`.

## État de validation

Vagrantfile validé avec Vagrant 2.4.9 (`vagrant validate`, différents `WORKER_COUNT`,
locale non UTF-8) et génération d'inventaire testée. Un déploiement complet nécessite une
machine avec VirtualBox ou libvirt : **à valider par un test d'intégration**.
