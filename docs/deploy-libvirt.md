# Terraform + libvirt/KVM

Pour créer de **vraies VMs sur votre propre PC Linux**, sans Proxmox ni VMware.
Provider : [`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt)
0.9.x — une réécriture récente dont le schéma suit fidèlement le XML de libvirt
(les exemples trouvés en ligne pour la version 0.8 ne s'appliquent plus).

Terraform crée tout ce qui est nécessaire, dans des objets dédiés au lab :

| Ressource | Nom | Rôle |
| --- | --- | --- |
| `libvirt_pool` | `k8s-lab-pool` | stockage dans `/var/lib/libvirt/images/k8s-lab` |
| `libvirt_network` | `k8s-lab-net` | réseau NAT `192.168.123.0/24` |
| `libvirt_volume` | `k8s-lab-ubuntu-base.qcow2` | image Ubuntu 24.04 de base |
| `libvirt_volume` | `<nœud>.qcow2` | disque de chaque VM (copie sur écriture de l'image de base) |
| `libvirt_cloudinit_disk` + volume | `<nœud>-cloudinit.iso` | configuration cloud-init |
| `libvirt_domain` | `k8s-cp-1`, `k8s-worker-1`… | les VMs |

## Prérequis (Ubuntu / Debian)

```bash
sudo apt install qemu-kvm libvirt-daemon-system
sudo usermod -aG libvirt "$USER"     # puis reconnectez-vous
virsh -c qemu:///system list         # doit répondre sans sudo
ls /dev/kvm                          # virtualisation matérielle disponible
```

Plus Terraform (ou OpenTofu), Ansible et kubectl. Comptez 2 Go de RAM par VM.

## Déployer

Aucun fichier à préparer : les valeurs par défaut conviennent.

```bash
./k8s-lab doctor terraform libvirt
./k8s-lab deploy terraform libvirt
```

L'image Ubuntu est téléchargée **une seule fois** dans `.lab/cache/images/` et son SHA-256 est
vérifié par le CLI avant d'être confiée à Terraform.

Réglages facultatifs (`terraform/providers/libvirt/terraform.tfvars`) : `libvirt_uri`
(hyperviseur distant `qemu+ssh://…`), `network_cidr`, `ip_start`, `storage_pool_path`,
`domain_type` (`qemu` = émulation logicielle, très lente, uniquement sans `/dev/kvm`).

## Explorer

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system net-dumpxml k8s-lab-net
virsh -c qemu:///system vol-list k8s-lab-pool
ssh -i .lab/ssh/id_ed25519 ubuntu@192.168.123.10
```

## Remarques

- Sur un hôte avec AppArmor/SELinux strict, vérifiez que libvirt peut lire le dossier du pool.
- Le réseau `192.168.123.0/24` ne doit chevaucher aucun réseau existant de votre machine.

## État de validation

Implémenté, validé statiquement contre le schéma du provider 0.9.9 (`terraform validate`,
TFLint). **Nécessite un test d'intégration sur un hôte KVM** (l'environnement de cette refonte
n'expose pas `/dev/kvm`).
