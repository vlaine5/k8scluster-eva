# Mode Terraform (Infrastructure as Code)

Terraform décrit les VMs **en code** : on lit un plan (`terraform plan`) avant de l'appliquer,
et on peut recréer exactement la même infrastructure à tout moment. Une fois les VMs créées,
**le même Ansible que pour Vagrant** installe Kubernetes.

```text
terraform plan / apply
   ├── module k8s-nodes          noms, rôles, IP statiques, cloud-init (commun)
   ├── ressources du provider    VMs Proxmox / vSphere / libvirt   (spécifique)
   └── module ansible-inventory  ansible/inventories/terraform-<provider>.ini
                                          │
                                          ▼
                     ansible-playbook site.yml  (kubeadm init / join, Flannel)
```

## Providers disponibles

| Provider | Plateforme | Provider Terraform | Guide |
| --- | --- | --- | --- |
| `proxmox` | Proxmox VE 8.4+ / 9 | [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox) | [deploy-proxmox.md](deploy-proxmox.md) |
| `vsphere` | VMware vCenter | [`vmware/vsphere`](https://registry.terraform.io/providers/vmware/vsphere) | [deploy-vsphere.md](deploy-vsphere.md) |
| `libvirt` | KVM sur votre PC Linux | [`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt) | [deploy-libvirt.md](deploy-libvirt.md) |

## Utilisation

```bash
cp terraform/providers/proxmox/terraform.tfvars.example terraform/providers/proxmox/terraform.tfvars
# éditez terraform.tfvars (infrastructure) et .env (identifiants)
make doctor MODE=terraform PROVIDER=proxmox
make deploy MODE=terraform PROVIDER=proxmox     # ou : ./k8s-lab deploy terraform proxmox
make destroy MODE=terraform PROVIDER=proxmox
```

`deploy` enchaîne `terraform init`, `terraform plan` (affiché), **une confirmation**, puis
`terraform apply` et Ansible. Relancer `deploy` est sans danger : Terraform ne modifie que ce
qui a changé (par exemple ajouter un worker quand `WORKER_COUNT` augmente). Si un plan prévoit
de **détruire** une ressource, un avertissement s'affiche avant la confirmation.

## Utiliser Terraform directement

C'est recommandé une fois le principe compris :

```bash
cd terraform/providers/libvirt
terraform init
terraform plan -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
terraform output                           # IP, commandes SSH, inventaire
cd ../../../ansible && ansible-playbook -i inventories/terraform-libvirt.ini site.yml
```

Les variables communes (`worker_count`, `node_cpus`…) ont les mêmes valeurs par défaut que
`config/lab.env`. Le CLI les fournit via `TF_VAR_*` ; une valeur écrite dans
`terraform.tfvars` reste prioritaire (règle de Terraform).

## Outputs

| Output | Contenu |
| --- | --- |
| `control_plane_ip` | IP du control-plane |
| `worker_ips` | IP des workers |
| `nodes` | nom → rôle, IP (et ID de VM) |
| `ssh_commands` | commande SSH prête à l'emploi pour chaque nœud |
| `ansible_inventory` | chemin de l'inventaire généré |
| `kubeconfig` | où trouver le kubeconfig une fois Kubernetes installé |

Aucun output ne contient de secret.

## State et sécurité

Le **state** (`terraform.tfstate`) décrit l'infrastructure réelle. Il est local, ignoré par Git,
et **peut contenir des données sensibles** (le contenu cloud-init, des identifiants de VM…).
Ne le partagez pas et ne le versionnez pas. En équipe, utilisez un backend distant chiffré
(S3 + DynamoDB, GitLab, Terraform Cloud…). Voir [security.md](security.md).

## OpenTofu

Le code est compatible [OpenTofu](https://opentofu.org/) : s'il est seul installé, le CLI
l'utilise automatiquement (ou forcez-le avec `TERRAFORM_BIN=tofu`).

## Ajouter un provider (OpenStack, AWS, Azure, GCP…)

1. Créez `terraform/providers/<nom>/` (`versions.tf`, `providers.tf`, `variables.tf`, `main.tf`,
   `outputs.tf`, `terraform.tfvars.example`) en copiant la structure d'un provider existant.
2. Appelez `module "nodes"` (`../../modules/k8s-nodes`) : il fournit noms, IP et cloud-init.
3. Créez une VM par élément de `module.nodes.nodes` (`for_each`), en passant
   `module.nodes.cloud_init[each.key].user_data` à la plateforme.
4. Appelez `module "inventory"` (`../../modules/ansible-inventory`).
5. Ajoutez `<nom>` dans `scripts/lib/mode_terraform.sh` (`tf_check_provider`,
   `terraform_status`) et les vérifications d'accès dans `scripts/lib/doctor.sh`.

Aucune ligne d'Ansible n'est à écrire : l'installation de Kubernetes est déjà commune.

## État de validation

Code formaté (`terraform fmt`), validé (`terraform validate`), analysé (TFLint) et modules
testés (`terraform test`) en CI. Le provider Proxmox a été vérifié par `terraform plan`
(endpoint factice). **Un test d'intégration sur chaque plateforme réelle reste nécessaire.**
