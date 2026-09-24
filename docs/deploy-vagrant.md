# Déployer Kubernetes avec Vagrant

Ce mode construit un « vrai » cluster sur des machines virtuelles, comme en entreprise :

```text
Vagrant       crée les VMs décrites dans vagrant/Vagrantfile
   ↓
VMs           3 machines Ubuntu 24.04, chacune avec une IP fixe
   ↓
Ansible       se connecte aux VMs en SSH et les prépare (ansible/site.yml)
   ↓
kubeadm       « kubeadm init » sur le control-plane, « kubeadm join » sur les workers
   ↓
Kubernetes    le cluster est prêt, kubectl est configuré sur votre machine
```

Une seule commande enchaîne toutes ces étapes, et chacune est affichée pendant le déploiement.

## Ce que vous allez obtenir

- 1 control-plane : la VM `k8s-cp-1` (192.168.56.10)
- 2 workers : les VMs `k8s-worker-1` et `k8s-worker-2` (192.168.56.11 et .12)
- Kubernetes 1.37 installé avec kubeadm, runtime containerd
- un réseau des Pods Flannel

## Prérequis

- [Vagrant](https://developer.hashicorp.com/vagrant/install)
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) (sous Linux avec KVM, vous pouvez
  utiliser libvirt : voir [Pour aller plus loin](#pour-aller-plus-loin))
- Ansible (ansible-core 2.18 ou plus récent) : `pipx install --include-deps ansible`
- `kubectl` et un client SSH
- 6 Go de RAM libres (3 VMs de 2 Go) et la virtualisation activée dans le BIOS

## 1. Vérifier votre machine

```bash
make doctor MODE=vagrant
```

## 2. Configurer

Rien d'obligatoire. Le nombre de workers (2 par défaut) se choisit au déploiement :

```bash
make deploy MODE=vagrant WORKERS=3
```

`WORKER_COUNT=3 make deploy MODE=vagrant` fonctionne aussi. Pour garder ce réglage, écrivez
`WORKER_COUNT=3` dans votre fichier `.env` (`cp .env.example .env`).

## 3. Déployer

```bash
make deploy MODE=vagrant
```

Comptez 10 à 20 minutes. Relancer `deploy` ne recrée rien. Si vous augmentez le nombre de
workers, seuls les nouveaux workers sont créés et ajoutés au cluster.

## 4. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
kubectl get pods -A
```

Les nœuds `k8s-cp-1`, `k8s-worker-1` et `k8s-worker-2` sont `Ready`.

## 5. Tester

```bash
make test
```

## 6. Supprimer

```bash
make destroy MODE=vagrant
```

Pour **réduire** le nombre de workers, supprimez le lab puis redéployez-le avec le nouveau
nombre : Vagrant ne supprime pas les VMs en trop (`deploy` vous le rappelle).

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| `VT-x is not available` / `VERR_VMX_NO_VMX` | activez la virtualisation (VT-x/AMD-V) dans le BIOS ; sous Linux avec KVM, utilisez `VAGRANT_PROVIDER=libvirt` |
| `The IP address configured for the host-only network is not within the allowed ranges` | gardez le réseau par défaut `192.168.56.x`, ou autorisez votre plage dans `/etc/vbox/networks.conf` |
| Ansible : `UNREACHABLE` | la VM ne répond pas en SSH : `cd vagrant && vagrant status`, puis relancez `make deploy MODE=vagrant` |
| Une étape Ansible échoue | lisez la tâche en erreur, corrigez, puis relancez `make deploy MODE=vagrant` : les VMs sont conservées |
| Pas assez de RAM | un seul worker : `make deploy MODE=vagrant WORKERS=1` (sur un lab neuf) |

Plus de cas : [troubleshooting.md](troubleshooting.md).

## Pour aller plus loin

### Se connecter aux VMs

```bash
cd vagrant
vagrant status
vagrant ssh k8s-cp-1          # dans la VM : kubectl get nodes, sudo crictl ps
```

### Lancer les étapes à la main

```bash
cd vagrant && vagrant up && cd ..                                  # 1. les VMs + l'inventaire
cd ansible && ansible-playbook -i inventories/vagrant.ini site.yml    # 2. Kubernetes
```

Le détail des étapes Ansible : [ansible-kubeadm.md](ansible-kubeadm.md).

### Autres hyperviseurs

Réglage `VAGRANT_PROVIDER` dans `.env` :

| Valeur | Pour qui | À installer en plus de Vagrant |
| --- | --- | --- |
| `virtualbox` (défaut) | Linux, Windows, macOS Intel | VirtualBox |
| `libvirt` | Linux avec KVM | `qemu-kvm libvirt-daemon-system` + `vagrant plugin install vagrant-libvirt` |
| `vmware_desktop` | VMware Workstation / Fusion | Vagrant VMware Utility + `vagrant plugin install vagrant-vmware-desktop` |
| `vmware_esxi` | ESXi autonome (mode historique) | `vagrant plugin install vagrant-vmware-esxi` + VMware OVF Tool |

### Mode historique : ESXi autonome

La version d'origine de ce projet déployait sur un ESXi. Ce mode reste disponible, sans mot de
passe dans le code. Dans `.env` :

```bash
VAGRANT_PROVIDER=vmware_esxi
ESXI_HOSTNAME=esxi.example.lan
ESXI_USERNAME=root
ESXI_PASSWORD=...                     # lu par le plugin via "env:ESXI_PASSWORD"
ESXI_DATASTORE=datastore1
ESXI_NETWORKS=VM Network,K8S Network  # 1er : DHCP/accès, 2e : IP privées du cluster
```

Limites : le plugin `vagrant-vmware-esxi` n'est plus maintenu depuis 2022 (ce mode est fourni
« au mieux »), il nécessite VMware OVF Tool et **deux** port groups. Le mode Terraform vSphere
ne remplace pas ce mode : il exige un vCenter (voir [deploy-vsphere.md](deploy-vsphere.md)).

### Pourquoi le lab fixe `node-ip` ?

Une VM Vagrant a deux cartes réseau : une carte NAT (même IP `10.0.2.15` sur toutes les VMs
avec VirtualBox) et une carte privée (`192.168.56.x`). Si Kubernetes utilisait la carte NAT,
les nœuds ne pourraient pas se joindre. Le lab donne donc explicitement l'IP privée au kubelet
(`node-ip`) et à Flannel. C'est un piège classique des clusters à plusieurs cartes réseau.

### Instantanés

```bash
cd vagrant
vagrant snapshot save avant-tp
vagrant snapshot restore avant-tp
```

### Remarques

- La taille du disque est celle de la box (`NODE_DISK_GB` ne s'applique qu'à Terraform).
- `vagrant up` fonctionne aussi sans le CLI : le Vagrantfile lit `config/lab.env` et `.env`.

**Statut : VALIDÉ STATIQUEMENT — TEST D'INTÉGRATION VM À FAIRE.**
Vagrantfile : syntaxe et `vagrant validate` vérifiés en CI (configuration par défaut).
Déploiement réel : à tester sur VirtualBox, libvirt ou VMware. L'installation de Kubernetes
par Ansible est, elle, testée en CI sur des nœuds conteneurs.
