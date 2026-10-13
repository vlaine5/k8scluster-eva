# Choisir un mode : local, kubeadm sur VMs, ou cloud managé ?

Tous les modes produisent un « vrai » Kubernetes (mêmes API, même `kubectl`), mais ils ne
montrent pas la même chose.

## Quatre niveaux

```text
Niveau 1   Kind / Minikube                        → utiliser Kubernetes
Niveau 2   Vagrant + Ansible + kubeadm            → comprendre comment Kubernetes est installé
Niveau 3   Terraform (Proxmox, vSphere, libvirt)  → Infrastructure as Code
             + Ansible + kubeadm                     + installation de Kubernetes
Niveau 4   Terraform + AWS EKS                    → Kubernetes managé dans le cloud

Et pour l'existant :
  existing  vos machines Linux + Ansible + kubeadm → bare metal, VMs créées à la main
  attach    un cluster qui existe déjà             → seulement les addons
```

## En résumé

| | Kind | Minikube | kubeadm sur VMs (Vagrant / Terraform) | AWS EKS (Terraform) |
| --- | --- | --- | --- | --- |
| Un nœud = | un conteneur Docker | un conteneur ou une VM | une vraie VM Linux | une instance EC2 |
| Création | ~1 min | 2-5 min | 10-20 min | 15-20 min |
| Coût | gratuit (votre poste) | gratuit (votre poste) | vos VMs | **facturé par AWS** |
| Multi-nœuds | oui (défaut du lab : 1 + 2) | possible (défaut du lab : 1) | oui (défaut du lab : 1 + 2) | oui (défaut du lab : 2 workers) |
| Control-plane | caché (image toute prête) | caché | **installé par vous** : kubeadm init | **fourni par AWS** |
| Réseau des Pods | kindnet (défaut), Calico ou Cilium | CNI de minikube (Calico, Cilium possibles) | **Flannel, Calico ou Cilium, installé par vous** | addon `vpc-cni` d'AWS |
| Haute disponibilité | — | expérimental (`--ha`) | 1, 3 ou 5 control-planes (VIP kube-vip) | fournie par AWS |
| Idéal pour | apprendre `kubectl`, tester des manifestes, la CI | découvrir les addons (dashboard, ingress…) | comprendre l'architecture d'un cluster | découvrir Kubernetes dans le cloud |

## Kind et Minikube : l'environnement local rapide

Ils répondent à la question **« comment utiliser Kubernetes ? »**. En une commande vous avez
un cluster jetable pour apprendre les objets : Pods, Deployments, Services, namespaces,
ConfigMaps… Ce qui se passe dans les nœuds est volontairement masqué.

- **Kind** (*Kubernetes IN Docker*) est minimaliste et très rapide ; c'est l'outil utilisé par
  les développeurs de Kubernetes pour leurs tests, et par la CI de ce dépôt.
- **Minikube** vise le poste du développeur : addons prêts à l'emploi
  (`minikube addons enable ingress`), tableau de bord (`minikube dashboard`), choix du driver
  (Docker, KVM, VirtualBox…).

## kubeadm sur des VMs : « je construis mon cluster »

Il répond à la question **« comment fonctionne un cluster ? »**. Vous voyez chaque brique :

1. **Le système** : swap désactivé, modules noyau `overlay` et `br_netfilter`, routage IP.
2. **Le runtime** : containerd, configuré avec le driver cgroup `systemd` (cgroup v2).
3. **Les paquets** : `kubelet`, `kubeadm`, `kubectl` depuis le dépôt officiel `pkgs.k8s.io`.
4. **`kubeadm init`** sur le control-plane : certificats, etcd, API server, scheduler,
   controller-manager (des Pods « statiques » lancés par le kubelet).
5. **Le CNI** (Flannel, Calico ou Cilium) : sans lui, les nœuds restent `NotReady`.
6. **`kubeadm join`** sur chaque worker, avec un jeton temporaire.

Ces étapes sont écrites en Ansible et commentées : [ansible-kubeadm.md](ansible-kubeadm.md).

Ensuite, deux façons de créer les VMs :

- **Vagrant** (niveau 2) : des VMs locales, décrites dans un seul `Vagrantfile`.
- **Terraform** (niveau 3) : l'Infrastructure as Code, sur Proxmox, vSphere ou KVM. Le même
  code Ansible installe Kubernetes, quel que soit le provider.

## existing : « j'ai déjà mes machines »

Même installation kubeadm que sur des VMs, mais sur des machines que vous fournissez (bare
metal, VMs créées à la main) et décrivez dans un inventaire Ansible. Contrôles préalables
en lecture seule, plan affiché, confirmation ; `make destroy` est refusé (les machines ne
sont jamais supprimées) et `make uninstall` retire seulement Kubernetes :
[existing-mode.md](existing-mode.md).

## attach : « j'ai déjà un cluster »

Seuls les addons sont installés, sur un cluster existant (k3s, RKE2, kubeadm, cluster
managé…) désigné par `EXISTING_KUBECONFIG` et `EXISTING_CONTEXT`. Le framework détecte
d'abord ce qui est présent et refuse de prendre le contrôle d'un composant installé par un
autre outil (Helm, Argo CD, k3s) : [attach-mode.md](attach-mode.md).

## AWS EKS : « le cloud me fournit le control-plane »

Il répond à la question **« comment utilise-t-on Kubernetes dans le cloud ? »**. Terraform
décrit l'infrastructure AWS (réseau, droits IAM, cluster, workers) ; AWS installe et opère le
control-plane. Il n'y a ni Ansible ni kubeadm : c'est justement ce qu'il faut observer.

## kubeadm ou EKS ?

Deux objectifs différents, pas un meilleur que l'autre :

| | kubeadm (Vagrant, Proxmox, vSphere, libvirt) | EKS |
| --- | --- | --- |
| Control-plane | installé par vous (Ansible + kubeadm) | géré par AWS |
| Workers | VMs configurées par Ansible | Managed Node Group |
| Infrastructure | au choix : vos VMs, votre hyperviseur | AWS |
| Niveau d'abstraction | plus bas niveau | plus managé |
| On apprend | l'installation de Kubernetes | Kubernetes dans le cloud |

## Parcours conseillé

```text
Kind ──> Minikube ──> Vagrant + kubeadm ──> Terraform + kubeadm ──> Terraform + EKS
```

1. Kind : `kubectl`, manifestes, `examples/`.
2. Minikube : addons, dashboard, comparer avec Kind.
3. Vagrant : lire `ansible/site.yml` pendant que le cluster se construit, se connecter aux VMs
   (`vagrant ssh k8s-cp-1`), observer `sudo crictl ps`, `/etc/kubernetes/manifests/`.
4. Terraform : lire `terraform/modules/k8s-nodes`, faire un `terraform plan`, changer
   `WORKER_COUNT` et observer le plan.
5. EKS : lire `terraform/providers/eks/main.tf`, comparer `kubectl get pods -n kube-system`
   avec un cluster kubeadm (où sont etcd et l'API server ?), puis **détruire le cluster**.

## Exercices pour aller plus loin

- `CNI=none` puis installez vous-même Calico ou Cilium : que deviennent les nœuds avant/après ?
- `make deploy MODE=vagrant WORKERS=3`, puis relancez avec `WORKERS=4` : un seul worker est
  ajouté, le cluster existant est conservé.
- Mettez à jour un cluster kubeadm d'une version mineure : `make upgrade-plan`, puis
  `make upgrade` (kubeadm, nœud par nœud : [upgrades.md](upgrades.md)).
- Passez à 3 control-planes (`CONTROL_PLANE_COUNT=3`, `CONTROL_PLANE_VIP`), arrêtez-en un
  et observez etcd et l'API ([high-availability.md](high-availability.md)).
- Sur EKS, passez de 2 à 3 workers (`make deploy MODE=terraform PROVIDER=eks WORKERS=3`) et
  observez le plan : seul le Managed Node Group change.
