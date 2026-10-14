# Documentation

Toutes les pages sont en français. Les sections marquées « générée » (variables, catalogue,
versions, matrices) sont produites depuis le code par `make docs-generate` et vérifiées en
CI par `make docs-check` : elles ne peuvent pas diverger de ce qui est réellement exécuté.

## Démarrer

| Page | Pour quoi faire |
| --- | --- |
| [deployment.md](deployment.md) | choisir un mode de déploiement |
| [modes.md](modes.md) | comparer les modes (kind, minikube, VMs, existing, attach, EKS) |
| [deploy-kind.md](deploy-kind.md) · [deploy-minikube.md](deploy-minikube.md) | cluster local |
| [deploy-vagrant.md](deploy-vagrant.md) · [deploy-libvirt.md](deploy-libvirt.md) | VMs locales + kubeadm |
| [deploy-proxmox.md](deploy-proxmox.md) · [deploy-vsphere.md](deploy-vsphere.md) | VMs sur hyperviseur + kubeadm |
| [homelab-pv05.md](homelab-pv05.md) | procédure du premier déploiement sur le homelab Proxmox « pv05 » |
| [existing-mode.md](existing-mode.md) | Kubernetes sur des machines déjà installées (bare metal) |
| [attach-mode.md](attach-mode.md) | addons sur un cluster Kubernetes existant |
| [deploy-eks.md](deploy-eks.md) | Kubernetes managé AWS |
| [migration.md](migration.md) | passer de la version précédente du dépôt à celle-ci |

## Configurer

| Page | Contenu |
| --- | --- |
| [configuration.md](configuration.md) | **toutes** les variables (générée), priorités, validation |
| [versions.md](versions.md) | versions verrouillées (générée), politique de mise à jour |
| [compatibility.md](compatibility.md) | matrices plateformes × addons, OS, CNI (générées) |
| [os.md](os.md) | Ubuntu, Debian, Rocky Linux : différences, images, CPU |
| [high-availability.md](high-availability.md) | 1, 3 ou 5 control-planes, VIP kube-vip, limites |
| [cni.md](cni.md) | Flannel, Calico, Cilium, none ; NetworkPolicy ; changer de CNI |
| [gateway-api.md](gateway-api.md) | Traefik, Envoy Gateway, Cilium ; Gateway partagée, TLS |
| [loadbalancer.md](loadbalancer.md) | MetalLB, Cilium L2/BGP ; choisir un pool d'adresses |
| [storage.md](storage.md) · [storage-nfs.md](storage-nfs.md) · [storage-longhorn.md](storage-longhorn.md) | stockage persistant |

## Addons

| Page | Contenu |
| --- | --- |
| [addons.md](addons.md) | profils, catalogue et fiche de chaque addon (générés), commandes |
| [observability.md](observability.md) | métriques, tableaux de bord, alertes, journaux, traces |
| [security.md](security.md) | secrets, Pod Security, Kyverno, Trivy, Falco, Tetragon, durcissement |
| [gitops.md](gitops.md) | Argo CD : ce qui est géré par le framework, ce qui l'est par Git |
| [service-mesh.md](service-mesh.md) | Istio (sidecars, agent CNI, mTLS) |
| [addon-development.md](addon-development.md) | écrire un addon |

## Exploiter

| Page | Contenu |
| --- | --- |
| [day2.md](day2.md) | toutes les commandes d'exploitation |
| [upgrades.md](upgrades.md) | mises à niveau de Kubernetes, des addons et de l'OS |
| [backup-dr.md](backup-dr.md) | instantanés etcd, Velero, restauration, exercices |
| [troubleshooting.md](troubleshooting.md) | dépannage par symptôme |

## Comprendre

| Page | Contenu |
| --- | --- |
| [architecture.md](architecture.md) | organisation du dépôt, principes de conception |
| [ansible-kubeadm.md](ansible-kubeadm.md) | ce que fait chaque étape de l'installation kubeadm |
| [terraform.md](terraform.md) | modules, providers, utilisation directe de Terraform |
| [maintenance.md](maintenance.md) | mettre à jour les versions verrouillées |
