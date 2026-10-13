# Profils d'exemple

Fichiers de configuration complets, validés par le résolveur. Utilisez-les tels quels avec
`LAB_ENV_FILE`, ou copiez-les vers `.env` pour les adapter :

```bash
LAB_ENV_FILE=examples/profiles/kind-minimal.env make config      # configuration résolue (lecture seule)
LAB_ENV_FILE=examples/profiles/kind-minimal.env make addons-plan # addons, dépendances, ordre
LAB_ENV_FILE=examples/profiles/kind-minimal.env make deploy
```

Les secrets (token Proxmox, mots de passe…) ne vont **jamais** dans ces fichiers : ils vont
dans `.env`, qui n'est pas versionné. Avec `LAB_ENV_FILE`, mettez-les dans l'environnement
ou dans une copie non versionnée du profil.

| Profil | Mode | Contenu | Ressources |
| --- | --- | --- | --- |
| [kind-minimal.env](kind-minimal.env) | kind | 1 + 2 nœuds, aucun addon optionnel | ~2 Go |
| [kind-observability.env](kind-observability.env) | kind | Prometheus, Grafana, Alertmanager, Loki, Tempo, OpenTelemetry, Traefik | ~8 Go |
| [vagrant-ha.env](vagrant-ha.env) | vagrant (libvirt) | 3 control-planes + 2 workers, Debian 12, Calico, Envoy Gateway, MetalLB | ~14 Go |
| [homelab-pv05.env](homelab-pv05.env) | terraform proxmox | homelab « pv05 » : 1 + 3, Ubuntu 24.04, Flannel, Traefik, MetalLB, NFS (Synology), Longhorn | 16 Go sur l'hôte |
| [enterprise-lab.env](enterprise-lab.env) | terraform proxmox | 3 + 3, Rocky 9, Cilium sans kube-proxy, Hubble, Longhorn, Argo CD, supervision, Kyverno, Trivy | ~48 Go sur l'hôte |
| [existing-baremetal.env](existing-baremetal.env) | existing | vos machines (inventaire Ansible), Traefik, MetalLB, cert-manager | — |
| [attach-observability.env](attach-observability.env) | attach | supervision et journaux sur un cluster existant | — |

Les adresses IP, réseaux, serveurs NFS et pools LoadBalancer des profils homelab sont des
**exemples à valider** dans votre IPAM avant tout déploiement (`make config` affiche ce qui
sera utilisé et ce qui chevauche). Les profils `existing` et `attach` sont refusés tant que
l'inventaire ou le kubeconfig qu'ils désignent n'existe pas.

Pour Proxmox, le fichier `terraform.tfvars` correspondant au homelab est
[../homelab/terraform.tfvars.example](../homelab/terraform.tfvars.example).
