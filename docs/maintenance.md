# Maintenance : mettre à jour les versions verrouillées

Toutes les versions sont **explicites** (jamais `latest`, jamais une branche) et
**centralisées** dans `config/versions.yaml`, avec l'empreinte SHA-256 de chaque fichier
téléchargé. Le tableau des versions en vigueur est généré : [versions.md](versions.md).

Ce document s'adresse à qui maintient le dépôt. Pour mettre à jour un **cluster**, voir
[upgrades.md](upgrades.md).

## Où sont les versions ?

| Quoi | Fichier |
| --- | --- |
| Kubernetes (défaut, mineures supportées, images kind), containerd, Helm, kube-vip, images des OS, charts et manifestes des addons, CNI, images de test | `config/versions.yaml` |
| Valeur par défaut de `KUBERNETES_VERSION` | `config/lab.env` (doit égaler `kubernetes.version` de `versions.yaml` : `make check-config`) |
| Outils du poste et de la CI (kind, kubectl, minikube, helm, terraform, tflint, vagrant, actionlint) | `config/lab.env` (`*_VERSION`) ; `scripts/install-tools.sh` vérifie le SHA-256 publié par chaque projet |
| Image `pause` | `ansible/roles/container_runtime/defaults/main.yml` |
| Providers Terraform | `terraform/providers/*/versions.tf` + `.terraform.lock.hcl` |
| Collections Ansible | `ansible/requirements.yml` |
| Python (ansible-core, PyYAML, kubernetes, outils de test) | `requirements-dev.txt` |
| Actions GitHub | `.github/workflows/*.yml`, `.github/actions/` (épinglées par empreinte ; Dependabot) |

## Procédure

1. `make versions-check` : liste les versions plus récentes publiées en amont (selon
   `UPGRADE_POLICY` : correctifs seulement, ou aussi les mineures). Rien n'est installé.
2. Modifiez `config/versions.yaml` : version **et** empreinte SHA-256 de chaque fichier
   (`curl -sSL <url> | sha256sum`). Pour une image d'OS, prenez une image **datée** et le
   `SHA256SUMS` officiel de la distribution.
3. Lisez les notes de version : compatibilité avec Kubernetes (`kube_min`, `kube_tested`
   dans `versions.yaml`), changements de valeurs Helm, CRD.
4. `make lint` (contrôles statiques, documentation générée comprise) puis
   `make addons-render-check` (rendu de chaque addon avec `helm template` et contrôle Pod
   Security).
5. `make docs-generate` pour mettre à jour [versions.md](versions.md) et les matrices.
6. Poussez sur une branche : la CI déploie réellement kind avec les addons, minikube, et
   kubeadm sur plusieurs OS ; ne fusionnez qu'une CI verte.
7. Une nouvelle mineure de Kubernetes : ajoutez-la à `supported_minors`, l'image kind
   correspondante (avec son empreinte), et vérifiez que chaque addon la déclare compatible
   (sinon il sera signalé, ou refusé avec `COMPATIBILITY_POLICY=strict`).

## Règles de compatibilité

- `kubectl` : au plus une version mineure d'écart avec le cluster.
- Kubernetes ≥ 1.35 exige des nœuds en **cgroup v2** et containerd **2.x**.
- L'image de nœud kind doit être publiée pour la version de kind utilisée.
- `EKS_KUBERNETES_VERSION` suit le calendrier d'AWS, indépendamment de `KUBERNETES_VERSION`.
- Les CRD Gateway API doivent satisfaire le contrôleur choisi (`gateway_api` dans
  `versions.yaml`) ; un seul propriétaire pour ces CRD (l'addon `gateway-api-crds`, ou
  Cilium).
- Une nouvelle image d'OS ne modifie jamais les VMs existantes : elle sert aux nouvelles
  VMs (Proxmox, vSphere) ou au prochain cluster (libvirt) ; les nœuds existants se mettent
  à jour par `make os-update`.
