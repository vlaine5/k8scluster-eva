# Choisir un déploiement

## Pour commencer

- [Kind](deploy-kind.md) : un cluster en 2 minutes, avec Docker.

## Kubernetes local

- [Kind](deploy-kind.md) : les nœuds sont des conteneurs Docker.
- [Minikube](deploy-minikube.md) : un nœud local, avec des addons (tableau de bord, ingress…).

## Kubernetes sur VMs locales

- [Vagrant](deploy-vagrant.md) : des VMs VirtualBox, Kubernetes installé avec Ansible + kubeadm.
- [Terraform + libvirt](deploy-libvirt.md) : des VMs KVM sur votre machine Linux.

## Kubernetes sur infrastructure

- [Terraform + Proxmox](deploy-proxmox.md) : des VMs sur votre Proxmox VE.
- [Terraform + vSphere](deploy-vsphere.md) : des VMs sur votre VMware vCenter.

Comparaison des modes et parcours conseillé : [modes.md](modes.md).
