# Choisir un mode : Kind, Minikube ou kubeadm sur VMs ?

Les trois familles produisent un « vrai » Kubernetes (mêmes API, même `kubectl`), mais elles
ne montrent pas la même chose.

## En résumé

| | Kind | Minikube | kubeadm sur VMs (Vagrant / Terraform) |
| --- | --- | --- | --- |
| Un nœud = | un conteneur Docker | un conteneur ou une VM | une vraie VM Linux |
| Création | ~1 min | 2-5 min | 10-20 min |
| Ressources | faibles (≈ 3 Go RAM pour 3 nœuds) | faibles à moyennes | ≈ 2 Go RAM par nœud |
| Multi-nœuds | oui (défaut du lab : 1 + 2) | possible (défaut du lab : 1) | oui (défaut du lab : 1 + 2) |
| Installation de Kubernetes | cachée (image toute prête) | cachée | **visible** : containerd, kubeadm init/join, CNI |
| Réseau des Pods | kindnet (fourni) | fourni par minikube | **Flannel, installé par vous** |
| Idéal pour | apprendre `kubectl`, tester des manifestes, la CI | découvrir les addons (dashboard, ingress…) | comprendre l'architecture d'un cluster |

## Kind et Minikube : l'environnement local rapide

Ils répondent à la question **« comment utiliser Kubernetes ? »**. En une commande vous avez
un cluster jetable pour apprendre les objets : Pods, Deployments, Services, namespaces,
ConfigMaps… Ce qui se passe dans les nœuds est volontairement masqué.

- **Kind** (*Kubernetes IN Docker*) est minimaliste et très rapide ; c'est l'outil utilisé par
  les développeurs de Kubernetes pour leurs tests, et par la CI de ce dépôt.
- **Minikube** vise le poste du développeur : addons prêts à l'emploi
  (`minikube addons enable ingress`), tableau de bord (`minikube dashboard`), choix du driver
  (Docker, KVM, VirtualBox…).

## kubeadm sur des VMs : un cluster « comme en vrai »

Il répond à la question **« comment fonctionne un cluster ? »**. Vous voyez chaque brique :

1. **Le système** : swap désactivé, modules noyau `overlay` et `br_netfilter`, routage IP.
2. **Le runtime** : containerd, configuré avec le driver cgroup `systemd` (cgroup v2).
3. **Les paquets** : `kubelet`, `kubeadm`, `kubectl` depuis le dépôt officiel `pkgs.k8s.io`.
4. **`kubeadm init`** sur le control-plane : certificats, etcd, API server, scheduler,
   controller-manager (des Pods « statiques » lancés par le kubelet).
5. **Le CNI** (Flannel) : sans lui, les nœuds restent `NotReady`.
6. **`kubeadm join`** sur chaque worker, avec un jeton temporaire.

Ces étapes sont écrites en Ansible et commentées : [ansible-kubeadm.md](ansible-kubeadm.md).

Ensuite, deux façons de créer les VMs :

- **Vagrant** (niveau 2) : des VMs locales, décrites dans un seul `Vagrantfile`.
- **Terraform** (niveau 3) : l'Infrastructure as Code, sur Proxmox, vSphere ou KVM. Le même
  code Ansible installe Kubernetes, quel que soit le provider.

## Parcours conseillé

```text
Kind ──> Minikube ──> Vagrant ──> Ansible + kubeadm ──> Terraform ──> Proxmox / vSphere / KVM
```

1. Kind : `kubectl`, manifestes, `examples/`.
2. Minikube : addons, dashboard, comparer avec Kind.
3. Vagrant : lire `ansible/site.yml` pendant que le cluster se construit, se connecter aux VMs
   (`vagrant ssh k8s-cp-1`), observer `sudo crictl ps`, `/etc/kubernetes/manifests/`.
4. Terraform : lire `terraform/modules/k8s-nodes`, faire un `terraform plan`, changer
   `WORKER_COUNT` et observer le plan.

## Exercices pour aller plus loin

- `CNI=none` puis installez vous-même Calico ou Cilium : que deviennent les nœuds avant/après ?
- `./k8s-lab deploy vagrant` avec `WORKER_COUNT=3`, puis passez à `WORKER_COUNT=4` et relancez :
  un seul worker est ajouté, le cluster existant est conservé.
- Mettez à jour un cluster kubeadm d'une version mineure avec `kubeadm upgrade`
  (<https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/>).
