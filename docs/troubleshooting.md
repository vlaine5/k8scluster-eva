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

## AWS EKS

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `doctor` : aucun identifiant AWS valide | AWS CLI non configurée, profil inconnu, session SSO expirée | `aws configure` (ou `aws sso login`), `AWS_PROFILE=<profil>` ; test : `aws sts get-caller-identity` |
| `AccessDenied` / `is not authorized to perform` pendant `deploy` | droits IAM insuffisants pour créer VPC, IAM, EKS, EC2 | utilisez un compte de TP avec ces droits |
| `UnsupportedAvailabilityZoneException` | zone refusée par EKS | le lab exclut les zones connues ; sinon changez `aws_region` |
| Node group `CREATE_FAILED` / `InsufficientInstanceCapacity` / quota vCPU | type d'instance indisponible ou quota atteint | autre `node_instance_types`, autre région, ou demande de quota |
| `kubectl` : `i/o timeout` | votre IP publique a changé (l'API n'est ouverte qu'à elle) | relancez `make deploy MODE=terraform PROVIDER=eks` (met à jour l'accès) |
| `kubectl` : `You must be logged in to the server (Unauthorized)` | autre identité AWS que celle qui a créé le cluster | reprenez le même `AWS_PROFILE` ; `make kubeconfig MODE=terraform PROVIDER=eks` |
| `destroy` refuse : Services LoadBalancer | des load balancers AWS créés par Kubernetes, inconnus de Terraform | `kubectl delete service -n <namespace> <nom>`, puis relancez `destroy` |
| `destroy` : `DependencyViolation` sur le VPC | une ressource créée hors Terraform (load balancer, interface réseau) utilise encore le VPC | attendez quelques minutes puis relancez ; sinon supprimez-la dans la console AWS (étiquette `Project = k8s-lab`) |
| `AWS_TARGET=localstack` : `connection refused` sur `localhost:4566` | LocalStack n'est pas démarré | démarrez-le (voir [deploy-eks.md](deploy-eks.md)) |
| LocalStack : service EKS indisponible | licence LocalStack sans EKS (offre Hobby) | EKS exige une licence Ultimate, Student ou open source |

## Ansible / kubeadm

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `UNREACHABLE` | VM pas encore démarrée, IP incorrecte, clé SSH | `ssh -i .lab/ssh/id_ed25519 ubuntu@<ip>` ; vérifiez l'IP dans l'inventaire |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | VM recréée hors du CLI avec la même IP | `ssh-keygen -R <ip> -f .lab/known_hosts` |
| `does not use cgroup v2` | image trop ancienne | utilisez Ubuntu 22.04+ / Debian 12+ |
| `kubeadm init failed` | kubelet ne démarre pas, image inaccessible | sur la VM : `sudo journalctl -u kubelet --no-pager \| tail -50`, `sudo crictl ps -a` ; puis `reset.yml` et relancer |
| `Refuse to silently change the Kubernetes version` | `KUBERNETES_VERSION` changé sur un cluster existant | remettez la version, ou planifiez la mise à niveau : `make upgrade-plan` puis `make upgrade` |
| Nœuds `NotReady` | CNI absent ou en erreur | `kubectl -n kube-flannel logs ds/kube-flannel-ds`, `kubectl -n kube-system logs ds/cilium`, `kubectl -n calico-system get pods` ; avec `CNI=none`, installez un CNI |
| `already runs <CNI> but cni=<autre>` | changement de CNI demandé sur un cluster existant | jamais automatique : [cni.md](cni.md#changer-de-cni) |
| `kubectl logs` / `exec` : `tls: internal error` | certificat de service du kubelet pas encore émis | `kubectl get csr` ; kubeadm : `kubectl -n kube-system logs deploy/kubelet-csr-approver` |
| `cannot resolve pkgs.k8s.io` (preflight) | DNS ou proxy | `/etc/resolv.conf`, accès Internet des nœuds |
| Pods d'un nœud à l'autre ne se joignent pas (Vagrant) | mauvaise interface réseau | vérifiez `FLANNELD_IFACE` (IP du nœud) et `node_ip` dans l'inventaire |
| Collections introuvables (`community.general.modprobe`) | collections non installées | `ansible-galaxy collection install -r ansible/requirements.yml` |

Recommencer le cluster sans recréer les VMs (instantané etcd pris avant) :

```bash
cd ansible
ansible-playbook -i inventories/<inventaire>.ini reset.yml -e reset_confirm=<nom-du-cluster>
cd .. && make deploy MODE=<mode>            # Terraform : MODE=terraform PROVIDER=<provider>
```

Mode existing : `make uninstall MODE=existing` (même effet, confirmation par le nom du cluster).

## Configuration

| Symptôme | Solution |
| --- | --- |
| `variable inconnue` | une faute de frappe : la variable la plus proche est proposée ; liste complète : [configuration.md](configuration.md) |
| `chevauchent` (réseaux) | `POD_CIDR`, `SERVICE_CIDR`, réseau des nœuds, `RESERVED_CIDRS`, pool LoadBalancer doivent être disjoints ; homelab avec des réseaux `10.101-105.0.0/16` : `SERVICE_CIDR=10.250.0.0/16` |
| `PyYAML est absent` / `No module named yaml` | `make venv` puis `source .venv/bin/activate` |
| `terraform.tfvars définit … pilotés par .env` | retirez ces lignes du tfvars (une seule source) |

## HA (plusieurs control-planes)

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `CONTROL_PLANE_VIP` exigée | HA sans VIP | choisissez une IP libre du réseau des nœuds (hors DHCP, hors pool) |
| la VIP ne répond pas | kube-vip ne trouve pas l'interface, ARP filtré | `sudo crictl logs $(sudo crictl ps -q --name kube-vip)` sur un control-plane ; la VIP doit être dans le même réseau L2 |
| `etcd members` ≠ nombre de control-planes | jonction interrompue | `make health` ; voir les membres : `kubectl -n kube-system exec etcd-k8s-cp-1 -- etcdctl … member list` |

## Addons

<a id="addons"></a>

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| `Le cluster du contexte … ne répond pas` | cluster arrêté, mauvais kubeconfig | `make status`, `make kubeconfig MODE=…` |
| `bibliothèque Python « kubernetes »` | Ansible sans la bibliothèque | `make venv`, puis `source .venv/bin/activate` |
| Helm : `timed out waiting for the condition` | image lente à télécharger, ressources insuffisantes | `kubectl get pods -A`, `kubectl describe pod` ; relancer `make addons-apply` (idempotent) |
| `is not ready` (contrôle de santé) | Pods en erreur | diagnostic affiché ; `kubectl -n <ns> get events --sort-by=.lastTimestamp` |
| Conflit de *server-side apply* | ressource possédée par un autre outil | ne pas forcer : identifier l'outil (`kubectl get <obj> -o yaml --show-managed-fields`) |
| Test en échec | voir le rapport `.lab/reports/<contexte>-addons-test.json` | `KEEP=1 make addons-test ADDON=<id>` conserve le namespace `k8s-lab-test-<id>` |
| LoadBalancer en `<pending>` | pool vide, fournisseur absent | `kubectl -n metallb-system get ipaddresspools` ; `make addons-test ADDON=metallb` |
| PVC NFS en `Pending` | export inaccessible, pare-feu | test de montage depuis un nœud : [storage-nfs.md](storage-nfs.md#réseau) |

## Modes existing et attach

| Symptôme | Solution |
| --- | --- |
| `belongs to another cluster` | la machine porte déjà un cluster : [existing-mode.md](existing-mode.md#reutiliser-une-machine) |
| `Kubernetes ports already in use` / paquets en conflit | le preflight liste le programme ou le paquet ; rien n'est désinstallé pour vous |
| `Au moins une machine ne répond pas en SSH`, et dans le journal de la machine `Access denied … by PAM account configuration` | `/run/nologin` ou `/etc/nologin` existe (machine encore en démarrage, arrêt programmé) : attendez la fin du démarrage ou supprimez le fichier si vous savez pourquoi il est là |
| `ss is not available (package iproute2)` | le contrôle des ports n'a pas pu être fait ; installez `iproute2` ou vérifiez les ports à la main |
| attach : `déjà installé par un autre outil` | retirer l'addon d'`ADDONS`, ou `EXISTING_ADDON_POLICY=skip` |
| attach : `géré par Argo CD` | jamais repris : gérez ce composant dans Git |

## Option avancée

`K8S_LAB_SKIP_DOCTOR=1` permet de déployer même si `doctor` signale un problème (par exemple
une configuration kind personnalisée pour un environnement particulier). À réserver aux cas
où vous savez pourquoi le contrôle échoue.
