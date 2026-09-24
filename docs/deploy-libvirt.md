# Déployer Kubernetes avec libvirt/KVM

Guide pour une machine **Linux avec KVM**.
Terraform crée les VMs KVM/libvirt localement, Ansible configure Kubernetes.

```text
Terraform → VMs KVM (libvirt) → Ansible → kubeadm → Kubernetes
```

## Ce que vous allez obtenir

- 1 control-plane : la VM `k8s-cp-1` (192.168.123.10)
- 2 workers : les VMs `k8s-worker-1` et `k8s-worker-2` (192.168.123.11 et .12)
- Kubernetes 1.37 installé avec kubeadm, runtime containerd, réseau des Pods Flannel
- un réseau et un stockage libvirt dédiés au lab (`k8s-lab-net`, `k8s-lab-pool`)

## Prérequis

- Linux avec la virtualisation matérielle (`/dev/kvm` existe)
- KVM et libvirt, utilisables sans sudo :

  ```bash
  sudo apt install qemu-kvm libvirt-daemon-system    # Ubuntu / Debian
  sudo usermod -aG libvirt "$USER"                   # puis reconnectez-vous
  ```

- Terraform (ou OpenTofu) et Ansible, ainsi que `kubectl` et le client SSH
- 6 Go de RAM libres (3 VMs de 2 Go)

## 1. Vérifier votre machine

```bash
make doctor MODE=terraform PROVIDER=libvirt
```

## 2. Configurer

Rien à configurer : les valeurs par défaut conviennent.

## 3. Déployer

```bash
make deploy MODE=terraform PROVIDER=libvirt
```

`deploy` affiche le plan Terraform et **demande confirmation** avant de créer quoi que ce soit.
L'image Ubuntu est téléchargée une seule fois (`.lab/cache/images/`) et son empreinte SHA-256
est vérifiée. Comptez 10 à 20 minutes.

## 4. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
kubectl get pods -A
```

Le contexte kubectl de ce cluster s'appelle `k8s-lab-libvirt`.

## 5. Tester

```bash
make test
```

## 6. Supprimer

```bash
make destroy MODE=terraform PROVIDER=libvirt
```

La commande demande confirmation, puis lance `terraform destroy` (VMs, réseau, stockage du lab).

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| `Permission denied` sur `qemu:///system` | `sudo usermod -aG libvirt "$USER"`, puis reconnectez-vous (ou redémarrez la session) |
| `doctor` : `/dev/kvm est absent` | activez VT-x/AMD-V dans le BIOS (ou la virtualisation imbriquée si votre Linux est lui-même une VM) |
| Le réseau `192.168.123.0/24` est déjà utilisé | choisissez-en un autre : `network_cidr` dans `terraform/providers/libvirt/terraform.tfvars` (copie du `.example`) |
| `Empreinte SHA-256 incorrecte` | relancez (téléchargement corrompu) ; si vous avez changé `VM_IMAGE_URL`, changez aussi `VM_IMAGE_SHA256` |
| libvirt ne peut pas lire le disque (AppArmor/SELinux) | vérifiez que libvirt a accès au dossier `/var/lib/libvirt/images/k8s-lab` |

Plus de cas : [troubleshooting.md](troubleshooting.md).

## Pour aller plus loin

### Explorer les VMs

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system net-dumpxml k8s-lab-net
ssh -i .lab/ssh/id_ed25519 ubuntu@192.168.123.10
```

### Ce que crée Terraform

| Ressource | Nom | Rôle |
| --- | --- | --- |
| `libvirt_pool` | `k8s-lab-pool` | stockage dans `/var/lib/libvirt/images/k8s-lab` |
| `libvirt_network` | `k8s-lab-net` | réseau NAT `192.168.123.0/24` |
| `libvirt_volume` | `k8s-lab-ubuntu-base.qcow2` | image Ubuntu 24.04 de base |
| `libvirt_volume` | `<nœud>.qcow2` | disque de chaque VM (copie sur écriture de l'image de base) |
| `libvirt_cloudinit_disk` | `<nœud>-cloudinit.iso` | configuration cloud-init (IP fixe, clé SSH) |
| `libvirt_domain` | `k8s-cp-1`, `k8s-worker-1`… | les VMs |

Réglages facultatifs (`terraform/providers/libvirt/terraform.tfvars`) : `libvirt_uri`
(hyperviseur distant `qemu+ssh://…`), `network_cidr`, `ip_start`, `storage_pool_path`,
`domain_type` (`qemu` = émulation logicielle, très lente, seulement sans `/dev/kvm`).

Le provider utilisé est [`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt)
0.9 : son schéma suit le XML de libvirt, les exemples écrits pour la version 0.8 ne
s'appliquent plus. Utiliser Terraform directement : [terraform.md](terraform.md).

**Statut : VALIDÉ STATIQUEMENT — TEST SUR KVM RÉEL À FAIRE.**
Le code est vérifié en CI (`terraform validate` contre le schéma du provider, TFLint,
`terraform test` des modules communs) ; le déploiement sur un hôte KVM réel n'a pas encore été
testé.
