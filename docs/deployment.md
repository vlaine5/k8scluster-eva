# Choisir un déploiement

## Pour commencer

- [Kind](deploy-kind.md) : un cluster en 2 minutes, avec Docker.

## Kubernetes local

- [Kind](deploy-kind.md) : les nœuds sont des conteneurs Docker.
- [Minikube](deploy-minikube.md) : un nœud local, avec des addons (tableau de bord, ingress…).

## Kubernetes sur VMs locales

- [Vagrant](deploy-vagrant.md) : des VMs VirtualBox ou libvirt, Kubernetes installé avec Ansible + kubeadm.
- [Terraform + libvirt](deploy-libvirt.md) : des VMs KVM sur votre machine Linux.

## Kubernetes sur infrastructure

- [Terraform + Proxmox](deploy-proxmox.md) : des VMs sur votre Proxmox VE.
- [Terraform + vSphere](deploy-vsphere.md) : des VMs sur votre VMware vCenter.

## Machines ou cluster existants

- [Mode existing](existing-mode.md) : Kubernetes installé avec kubeadm sur vos machines
  (bare metal, VMs créées à la main), décrites dans un inventaire Ansible.
- [Mode attach](attach-mode.md) : uniquement les addons, sur un cluster qui existe déjà.

## Homelab

- [Proxmox « pv05 »](homelab-pv05.md) : procédure complète du premier déploiement, profil
  [homelab-pv05.env](../examples/profiles/homelab-pv05.env).

## Kubernetes managé dans le cloud

- [Terraform + AWS EKS](deploy-eks.md) : AWS fournit le control-plane (ressources payantes).

Comparaison des modes et parcours conseillé : [modes.md](modes.md).
