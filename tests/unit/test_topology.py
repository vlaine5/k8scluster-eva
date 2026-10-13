"""Topologie, haute disponibilité, systèmes d'exploitation, stockage, sauvegardes."""
import pytest
from conftest import messages


@pytest.mark.parametrize("count", [2, 4])
def test_even_control_plane_counts_are_refused(lab, count):
    lab.env(f"CONTROL_PLANE_COUNT={count}\nCONTROL_PLANE_VIP=192.168.56.9")
    assert "nombre PAIR" in messages(lab.plan("vagrant"))


def test_ha_requires_a_vip_or_external_endpoint(lab):
    lab.env("CONTROL_PLANE_COUNT=3")
    lab.tfvars("proxmox", 'network_cidr = "10.20.0.0/16"\n')
    assert "exige CONTROL_PLANE_VIP" in messages(lab.plan("terraform", "proxmox"))


def test_ha_with_kube_vip(lab):
    lab.env("CONTROL_PLANE_COUNT=3\nWORKER_COUNT=3\nCONTROL_PLANE_VIP=10.20.0.99")
    lab.tfvars("proxmox", 'network_cidr = "10.20.0.0/16"\nip_start = 100\n')
    plan = lab.plan("terraform", "proxmox")
    assert plan.ok, messages(plan)
    r = plan.resolved
    assert (r["ha_mode"], r["api_lb_provider"], r["control_plane_endpoint"]) == ("stacked-etcd", "kube-vip", "10.20.0.99:6443")
    assert [n["name"] for n in plan.nodes][:3] == ["k8s-cp-1", "k8s-cp-2", "k8s-cp-3"]
    assert plan.nodes[3]["ip"] == "10.20.0.103"
    assert "UN SEUL hyperviseur" in messages(plan, "warning")


def test_five_control_planes_with_worker_offset(lab):
    lab.env("CONTROL_PLANE_COUNT=5\nWORKER_COUNT=5\nCONTROL_PLANE_VIP=10.20.0.99")
    lab.tfvars("proxmox", 'network_cidr = "10.20.0.0/16"\nip_start = 100\nworker_ip_offset = 10\n')
    plan = lab.plan("terraform", "proxmox")
    assert plan.ok, messages(plan)
    assert plan.nodes[4]["ip"] == "10.20.0.104" and plan.nodes[5]["ip"] == "10.20.0.110"


def test_ha_mode_contradictions(lab):
    lab.env("CONTROL_PLANE_COUNT=3\nHA_MODE=off\nCONTROL_PLANE_VIP=192.168.56.9")
    assert "HA_MODE=off est contradictoire" in messages(lab.plan("vagrant"))
    lab.env("HA_MODE=stacked-etcd")
    assert "au moins 3 control-planes" in messages(lab.plan("vagrant"))
    lab.env("CONTROL_PLANE_COUNT=3\nHA_MODE=external-etcd\nCONTROL_PLANE_VIP=192.168.56.9")
    assert "external-etcd n'est pas encore implémenté" in messages(lab.plan("vagrant"))


def test_vagrant_ha_picks_a_private_vip(lab):
    lab.env("CONTROL_PLANE_COUNT=3")
    plan = lab.plan("vagrant")
    assert plan.ok, messages(plan)
    assert plan.resolved["control_plane_vip"] == "192.168.56.9"
    assert [n["ip"] for n in plan.nodes] == ["192.168.56.10", "192.168.56.11", "192.168.56.12",
                                              "192.168.56.13", "192.168.56.14"]


def test_vip_on_a_node_address(lab):
    lab.env("CONTROL_PLANE_COUNT=3\nCONTROL_PLANE_VIP=192.168.56.11")
    assert "est l'adresse du nœud k8s-cp-2" in messages(lab.plan("vagrant"))


def test_eks_control_plane_is_managed(lab):
    lab.env("CONTROL_PLANE_COUNT=3")
    assert "géré (et déjà hautement disponible) par AWS" in messages(lab.plan("terraform", "eks"))


def test_single_cp_with_vip_prepares_future_ha(lab):
    lab.env("CONTROL_PLANE_VIP=192.168.56.9")
    plan = lab.plan("vagrant")
    assert plan.resolved["api_lb_provider"] == "kube-vip" and plan.resolved["control_plane_count"] == 1


@pytest.mark.parametrize("os_name,version", [("ubuntu", "24.04"), ("debian", "12"), ("debian", "13"), ("rocky", "9")])
def test_supported_os(lab, os_name, version):
    lab.env(f"NODE_OS={os_name}\nNODE_OS_VERSION={version}")
    plan = lab.plan("terraform", "libvirt")
    assert plan.ok, messages(plan)
    assert plan.resolved["image"]["source"] == "catalog" and len(plan.resolved["image"]["sha256"]) == 64
    assert plan.resolved["node_ssh_user"] == {"ubuntu": "ubuntu", "debian": "debian", "rocky": "rocky"}[os_name]


def test_unsupported_os_version(lab):
    lab.env("NODE_OS=debian\nNODE_OS_VERSION=11")
    assert "n'est pas dans la matrice supportée" in messages(lab.plan("vagrant"))


def test_rocky_10_needs_x86_64_v3_on_proxmox(lab):
    lab.env("NODE_OS=rocky\nNODE_OS_VERSION=10")
    errors = messages(lab.plan("terraform", "proxmox"))
    assert "x86-64-v3" in errors and "X5690" in errors
    lab.env("NODE_OS=rocky\nNODE_OS_VERSION=10\nNODE_CPU_TYPE=x86-64-v3")
    assert lab.plan("terraform", "proxmox").ok


def test_node_os_auto_only_in_existing_mode(lab):
    lab.env("NODE_OS=auto")
    assert "NODE_OS=auto n'est possible qu'en mode existing" in messages(lab.plan("vagrant"))


def test_node_os_is_ignored_by_kind(lab):
    lab.env("NODE_OS=rocky\nNODE_OS_VERSION=9")
    plan = lab.plan("kind")
    assert plan.ok and "ignorés en mode kind" in messages(plan, "info")


def test_vagrant_box_follows_the_os(lab):
    lab.env("NODE_OS=debian\nNODE_OS_VERSION=13")
    assert lab.plan("vagrant").resolved["image"]["box"] == "bento/debian-13"


def test_custom_image_requires_checksum(lab):
    lab.env("NODE_IMAGE_SOURCE=url\nNODE_IMAGE_URL=https://example.org/img.qcow2")
    assert "NODE_IMAGE_SHA256" in messages(lab.plan("terraform", "libvirt"))


def test_kubernetes_minor_not_supported(lab):
    lab.env("KUBERNETES_VERSION=1.30.0")
    assert "1.30 n'est pas supportée" in messages(lab.plan("vagrant"))


def test_kind_image_follows_kubernetes_version(lab):
    lab.env("KUBERNETES_VERSION=1.37.1")
    assert lab.plan("kind").resolved["kind_node_image"].startswith("kindest/node:v1.37.0@sha256:")


def test_nfs_requires_server_and_share(lab):
    lab.env("STORAGE_BACKENDS=nfs-csi")
    errors = messages(lab.plan("vagrant"))
    assert "NFS_SERVER" in errors and "NFS_SHARE" in errors


def test_nfs_default_storage_class_legacy_flag(lab):
    lab.env("STORAGE_BACKENDS=nfs-csi\nNFS_SERVER=10.70.0.30\nNFS_SHARE=/volume1/kubernetes\nNFS_DEFAULT_STORAGE_CLASS=true")
    plan = lab.plan("vagrant")
    assert plan.ok and plan.resolved["default_storage_class"] == {"backend": "nfs-csi", "name": "nfs-csi"}


def test_two_backends_need_an_explicit_default(lab):
    env = "STORAGE_BACKENDS=nfs-csi,longhorn\nNFS_SERVER=10.70.0.30\nNFS_SHARE=/volume1/kubernetes\nWORKER_COUNT=3"
    lab.env(env)
    assert "précisez DEFAULT_STORAGE_CLASS" in messages(lab.plan("vagrant"))
    lab.env(env + "\nDEFAULT_STORAGE_CLASS=longhorn")
    plan = lab.plan("vagrant")
    assert plan.ok, messages(plan)
    assert plan.resolved["default_storage_class"]["backend"] == "longhorn"
    assert {"nfs-csi", "longhorn"} <= set(plan.addon_ids())


def test_longhorn_aliases_and_version_resolution(lab):
    lab.env("LONGHORN_ENABLED=true\nWORKER_COUNT=3")
    plan = lab.plan("vagrant")
    assert "longhorn" in plan.addon_ids() and plan.resolved["longhorn_version"] == "1.13.0"


def test_longhorn_replicas_cannot_exceed_storage_nodes(lab):
    lab.env("STORAGE_BACKENDS=longhorn\nWORKER_COUNT=2\nLONGHORN_REPLICA_COUNT=3")
    assert "LONGHORN_REPLICA_COUNT=3 > 2 nœud(s)" in messages(lab.plan("vagrant"))


def test_longhorn_existing_dedicated_disk_needs_device(lab):
    lab.file("ansible/inventories/lab.ini", INVENTORY)
    lab.env("STORAGE_BACKENDS=longhorn\nLONGHORN_DEDICATED_DISK=true\nEXISTING_INVENTORY=ansible/inventories/lab.ini")
    assert "LONGHORN_DISK_DEVICE" in messages(lab.plan("existing"))


def test_etcd_backups_only_for_kubeadm(lab):
    lab.env("BACKUP_ENABLED=true")
    assert "instantanés etcd ne concernent que les clusters kubeadm" in messages(lab.plan("kind"))
    assert lab.plan("vagrant").resolved["backup"]["etcd_snapshots"] is True


INVENTORY = """
[control_plane]
k8s-cp-1 ansible_host=10.20.0.100

[workers]
k8s-worker-1 ansible_host=10.20.0.101
k8s-worker-2 ansible_host=10.20.0.102
k8s-worker-3 ansible_host=10.20.0.103

[k8s_cluster:children]
control_plane
workers

[k8s_cluster:vars]
ansible_user=admin
node_network_cidr=10.20.0.0/16
"""
