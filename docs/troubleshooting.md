# Dépannage

Premier réflexe : `make doctor MODE=<mode>` (Terraform : `make doctor MODE=terraform
PROVIDER=<provider>`). Deuxième : relancer la commande avec `DEBUG=1` (par exemple
`make deploy MODE=kind DEBUG=1`) pour voir chaque commande du CLI. `deploy` est idempotent :
le relancer après avoir corrigé un problème reprend là où il s'est arrêté.

## Général

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `Confirmation impossible : pas de terminal interactif` | `destroy` lancé depuis un script / la CI | ajoutez `--yes` (ou `YES=1` avec make) |
| `WORKER_COUNT=… n'est pas un nombre entier` | faute de frappe dans `.env` | corrigez `.env` |
| `kubectl` parle au mauvais cluster | contexte actif | `export KUBECONFIG="$PWD/.kube/config"` puis `kubectl config use-context …` |
| `The connection to the server localhost:8080 was refused` | `KUBECONFIG` non défini | `export KUBECONFIG="$PWD/.kube/config"` |

## Kind / Minikube

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `Docker utilise cgroup v1` (doctor) ; nœuds jamais prêts | hôte ancien en cgroup v1 : Kubernetes ≥ 1.35 le refuse | distribution récente, Docker Desktop ou WSL2 à jour |
| `Cannot connect to the Docker daemon` | démon arrêté ou droits | `sudo systemctl start docker` ; `sudo usermod -aG docker $USER` puis reconnexion |
| `ImagePullBackOff` sur les Pods de test | pas d'accès à Docker Hub (proxy d'entreprise) | configurez le proxy de Docker ; pour kind, `kind load docker-image <image>` |
| Création kind très lente puis échec | manque de RAM | `WORKER_COUNT=1` dans `.env` |
| minikube : `The "docker" driver should not be used with root privileges` | lancé en root | lancez-le en utilisateur normal |

## Vagrant

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `VT-x is not available` / `VERR_VMX_NO_VMX` | virtualisation désactivée, ou KVM utilise déjà VT-x | activez VT-x/AMD-V dans le BIOS ; sous Linux avec KVM, préférez `VAGRANT_PROVIDER=libvirt` |
| `The IP address configured for the host-only network is not within the allowed ranges` | réseau hors de `192.168.56.0/21` (VirtualBox ≥ 6.1.28) | gardez `VAGRANT_NETWORK_PREFIX=192.168.56` ou autorisez la plage dans `/etc/vbox/networks.conf` |
| Box introuvable pour le provider | la box ne publie pas ce provider | `VAGRANT_BOX` : choisissez une box compatible (`vagrant box list`) |
| `Le lab a déjà 3 worker(s), mais WORKER_COUNT=2` | nombre de workers réduit : Vagrant ne supprime pas les VMs en trop | `make destroy MODE=vagrant` puis redéployez, ou gardez le nombre actuel |
| ESXi : `esxi_password` demandé ou refusé | `ESXI_PASSWORD` absent de `.env` | ajoutez-le ; voir [deploy-vagrant.md](deploy-vagrant.md) (mode historique ESXi) |

## Terraform

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| Proxmox : `storage 'local' does not support content-type 'import'` | type de contenu *Import* non activé | voir [deploy-proxmox.md](deploy-proxmox.md) (étape 2) |
| Proxmox : `401` / `permission check failed` | token ou privilèges insuffisants | vérifiez `PROXMOX_VE_API_TOKEN` et le rôle du token |
| vSphere : erreur de clonage sur un ESXi | pas de vCenter | limitation du provider : utilisez Vagrant ESXi |
| vSphere : VM sans IP / cloud-init ignoré | options vApp actives sur le template | désactivez-les (voir [deploy-vsphere.md](deploy-vsphere.md)) |
| libvirt : `Permission denied` sur `qemu:///system` | utilisateur hors du groupe `libvirt` | `sudo usermod -aG libvirt $USER` puis reconnexion |
| libvirt : `Empreinte SHA-256 incorrecte` | téléchargement corrompu ou URL changée sans le checksum | relancez ; mettez à jour `VM_IMAGE_SHA256` si vous changez `VM_IMAGE_URL` |
| Le plan veut **détruire** des VMs | `WORKER_COUNT` réduit, ou paramètre forçant la recréation | lisez le plan ; refusez si ce n'est pas voulu ; après une réduction voulue, `kubectl delete node <nom>` pour chaque worker supprimé, puis relancez `deploy` |
| `Error acquiring the state lock` | un autre Terraform tourne (ou s'est interrompu) | attendez ; sinon `terraform force-unlock <id>` |

## Ansible / kubeadm

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `UNREACHABLE` | VM pas encore démarrée, IP incorrecte, clé SSH | `ssh -i .lab/ssh/id_ed25519 ubuntu@<ip>` ; vérifiez l'IP dans l'inventaire |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | VM recréée hors du CLI avec la même IP | `ssh-keygen -R <ip> -f .lab/known_hosts` |
| `does not use cgroup v2` | image trop ancienne | utilisez Ubuntu 22.04+ / Debian 12+ |
| `kubeadm init failed` | kubelet ne démarre pas, image inaccessible | sur la VM : `sudo journalctl -u kubelet --no-pager \| tail -50`, `sudo crictl ps -a` ; puis `reset.yml` et relancer |
| `Refuse to silently change the Kubernetes version` | `KUBERNETES_VERSION` changé sur un cluster existant | remettez la version, ou recréez le lab, ou faites un `kubeadm upgrade` |
| Nœuds `NotReady` | CNI absent ou en erreur | `kubectl -n kube-flannel logs ds/kube-flannel-ds` ; avec `CNI=none`, installez un CNI |
| Pods d'un nœud à l'autre ne se joignent pas (Vagrant) | mauvaise interface réseau | vérifiez `FLANNELD_IFACE` (IP du nœud) et `node_ip` dans l'inventaire |
| Collections introuvables (`community.general.modprobe`) | collections non installées | `ansible-galaxy collection install -r ansible/requirements.yml` |

Recommencer le cluster sans recréer les VMs :

```bash
cd ansible
ansible-playbook -i inventories/<inventaire>.ini reset.yml -e reset_confirm=true
cd .. && make deploy MODE=<mode>            # Terraform : MODE=terraform PROVIDER=<provider>
```

## Option avancée

`K8S_LAB_SKIP_DOCTOR=1` permet de déployer même si `doctor` signale un problème (par exemple
une configuration kind personnalisée pour un environnement particulier). À réserver aux cas
où vous savez pourquoi le contrôle échoue.
