"""Modes existing (machines existantes) et attach (cluster existant)."""
from conftest import messages
from test_topology import INVENTORY

from labcore import detect
from labcore.catalog import Catalog


def test_existing_mode_reads_the_inventory(lab):
    lab.file("ansible/inventories/homelab.ini", INVENTORY)
    lab.env("""
DEPLOYMENT_MODE=existing
EXISTING_INVENTORY=ansible/inventories/homelab.ini
NODE_OS=auto
CNI=cilium
GATEWAY_CONTROLLER=cilium
ADDONS=metrics-server,cert-manager
""")
    plan = lab.plan("existing")
    assert plan.ok, messages(plan)
    assert plan.resolved["control_plane_count"] == 1 and plan.resolved["worker_count"] == 3
    assert plan.resolved["node_network_cidr"] == "10.20.0.0/16"
    assert plan.resolved["kube_context"] == "k8s-lab-existing"


def test_existing_mode_without_inventory(lab):
    assert "EXISTING_INVENTORY n'est pas défini" in messages(lab.plan("existing"))


def test_existing_counts_must_match_inventory(lab):
    lab.file("ansible/inventories/homelab.ini", INVENTORY)
    lab.env("EXISTING_INVENTORY=ansible/inventories/homelab.ini\nWORKER_COUNT=2")
    assert "WORKER_COUNT=2 mais l'inventaire" in messages(lab.plan("existing"))


def test_existing_inventory_with_password_is_refused(lab):
    lab.file("ansible/inventories/bad.ini", INVENTORY.replace("ansible_user=admin", "ansible_user=admin\nansible_become_password=hunter2"))
    lab.env("EXISTING_INVENTORY=ansible/inventories/bad.ini")
    assert "mot de passe en clair" in messages(lab.plan("existing"))


def test_existing_yaml_inventory(lab):
    lab.file("ansible/inventories/lab.yml", """
k8s_cluster:
  children:
    control_plane:
      hosts:
        cp1: {ansible_host: 10.0.0.10}
        cp2: {ansible_host: 10.0.0.11}
        cp3: {ansible_host: 10.0.0.12}
    workers:
      hosts:
        w1: {ansible_host: 10.0.0.20}
  vars:
    node_network_cidr: 10.0.0.0/24
""")
    lab.env("EXISTING_INVENTORY=ansible/inventories/lab.yml\nCONTROL_PLANE_VIP=10.0.0.5")
    plan = lab.plan("existing")
    assert plan.ok, messages(plan)
    assert plan.resolved["control_plane_count"] == 3 and plan.resolved["api_lb_provider"] == "kube-vip"


def test_attach_requires_kubeconfig_and_explicit_context(lab):
    errors = messages(lab.plan("attach"))
    assert "EXISTING_KUBECONFIG" in errors and "EXISTING_CONTEXT" in errors


def test_attach_ignores_cluster_shape_and_never_touches_the_cni(lab):
    kubeconfig = lab.file("kubeconfig-test", "apiVersion: v1\nkind: Config\n")
    lab.env(f"EXISTING_KUBECONFIG={kubeconfig}\nEXISTING_CONTEXT=mon-cluster\nCNI=cilium\n"
            "ADDONS=cert-manager,metrics-server,argo-cd,monitoring")
    plan = lab.plan("attach", cluster_version="v1.35.2")
    assert plan.ok, messages(plan)
    assert plan.resolved["cni"] == "existing" and plan.resolved["kube_context"] == "mon-cluster"
    assert "jamais modifié" in messages(plan, "warning")


def test_attach_refuses_cni_coupled_addons(lab):
    kubeconfig = lab.file("kubeconfig-test", "apiVersion: v1\nkind: Config\n")
    lab.env(f"EXISTING_KUBECONFIG={kubeconfig}\nEXISTING_CONTEXT=c\nGATEWAY_CONTROLLER=cilium")
    assert "impossible" in messages(lab.plan("attach")) or "n'est pas disponible en mode attach" in messages(lab.plan("attach"))


def raw_cluster(git_version="v1.33.4+k3s1", extra_ds=(), releases=(), crds=(), state=None):
    def item(name, namespace="kube-system", annotations=None, labels=None):
        return {"metadata": {"name": name, "namespace": namespace, "annotations": annotations or {}, "labels": labels or {}}}
    return {
        "version": {"serverVersion": {"gitVersion": git_version, "major": "1", "minor": "33"}},
        "nodes": {"items": [{"metadata": {"name": "n1", "labels": {"node-role.kubernetes.io/control-plane": ""}},
                             "status": {"nodeInfo": {"osImage": "Ubuntu 24.04", "kernelVersion": "6.8",
                                                     "containerRuntimeVersion": "containerd://2.0", "kubeletVersion": git_version}},
                             "spec": {}}]},
        "daemonsets": {"items": [item(n) for n in extra_ds]},
        "storageclasses": {"items": [{"metadata": {"name": "local-path", "annotations": {"storageclass.kubernetes.io/is-default-class": "true"}},
                                      "provisioner": "rancher.io/local-path"}]},
        "crds": {"items": [item(c, "") for c in crds]},
        "csidrivers": {"items": []},
        "apiservices": {"items": [item("v1beta1.metrics.k8s.io", "")]},
        "gatewayclasses": {"items": []},
        "deployments": {"items": [item("traefik", "kube-system")]},
        "state": state,
        "kubeadm_config": None,
        "helm": list(releases),
    }


def test_detect_k3s_and_its_bundled_components(lab):
    report = detect.analyse(raw_cluster(extra_ds=["svclb-traefik-abc"]), "k3s")
    assert report["distribution"] == "k3s"
    assert report["servicelb"] is True
    assert report["default_storage_classes"] == ["local-path"]
    catalog = Catalog.load(lab.root)
    found = detect.conflicts(report, catalog, ["metrics-server", "metallb", "traefik"], "fail")
    text = "\n".join(c["message"] for c in found)
    assert "metrics-server est déjà installé par un autre outil" in text
    assert "ServiceLB" in text
    assert "embarque déjà Traefik" in text


def test_detect_skip_policy_and_lab_managed_addons(lab):
    raw = raw_cluster("v1.36.2", crds=["certificates.cert-manager.io"],
                      releases=[{"name": "cert-manager", "namespace": "cert-manager", "chart": "cert-manager-v1.21.2", "status": "deployed"}],
                      state={"data": {"cert-manager": "v1.21.2"}})
    report = detect.analyse(raw, "c")
    catalog = Catalog.load(lab.root)
    assert detect.conflicts(report, catalog, ["cert-manager"], "fail") == []
    assert report["present"]["cert-manager"]["managed_by_lab"] is True
    skip = detect.conflicts(report, catalog, ["metrics-server"], "skip")
    assert skip[0]["level"] == "info"


def test_detect_refuses_argocd_managed_components(lab):
    raw = raw_cluster("v1.36.2", crds=["clusterpolicies.kyverno.io"])
    raw["deployments"]["items"].append({"metadata": {"name": "kyverno-admission-controller", "namespace": "kyverno",
                                                     "annotations": {"argocd.argoproj.io/tracking-id": "x"}, "labels": {}}})
    report = detect.analyse(raw, "c")
    found = detect.conflicts(report, Catalog.load(lab.root), ["kyverno"], "skip")
    assert found[0]["level"] == "error" and "Argo CD" in found[0]["message"]
