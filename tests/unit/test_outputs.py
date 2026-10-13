"""Sorties : variables Ansible, manifeste, matrice, catalogue — et absence de secrets."""
import json
import shlex

from conftest import REPO, messages

from labcore import render
from labcore.catalog import PLATFORMS, Catalog

SECRET = "ne-doit-jamais-apparaitre-0123456789"


def full_env(lab):
    lab.env(f"""
ADDON_PROFILE=enterprise-lab
GATEWAY_CONTROLLER=traefik
STORAGE_BACKENDS=nfs-csi
NFS_SERVER=10.70.0.30
NFS_SHARE=/volume1/kubernetes
GRAFANA_ADMIN_PASSWORD={SECRET}
PROXMOX_VE_API_TOKEN=terraform@pve!lab={SECRET}
VELERO_S3_SECRET_KEY={SECRET}
""")


def test_ansible_vars_never_contain_secrets(lab):
    full_env(lab)
    cfg = lab.config()
    catalog = Catalog.load(lab.root)
    plan = lab.plan("vagrant")
    assert plan.ok, messages(plan)
    text = render.to_json(render.ansible_vars(plan, cfg, catalog))
    assert SECRET not in text
    data = json.loads(text)
    assert data["cni"] == "flannel" and data["kubernetes_version"] == "1.36.5"
    assert data["lab_addon_ids"][0] == "prometheus-operator-crds"
    assert "nfs-common" in data["node_prereqs"]["packages"]["debian"]


def test_manifest_never_contains_secrets(lab):
    full_env(lab)
    plan = lab.plan("vagrant")
    text = render.to_yaml(render.deployment_manifest(plan, lab.config(), Catalog.load(lab.root)))
    assert SECRET not in text
    assert "kind: DeploymentManifest" in text and "nfs-csi" in text


def test_config_display_masks_secrets(lab):
    full_env(lab)
    text = render.config_text(lab.config())
    assert SECRET not in text and "GRAFANA_ADMIN_PASSWORD=****" in text


def test_shell_exports_are_quoted(lab):
    lab.env("ADDON_PROFILE=custom\nADDONS=cert-manager,metrics-server")
    text = render.shell_exports(lab.plan("kind"), lab.config())
    exports = dict(line[len("export "):].split("=", 1) for line in text.strip().splitlines())
    assert shlex.split(exports["LAB_R_ADDONS"]) == ["cert-manager metrics-server"]
    assert exports["LAB_R_CONTEXT"] == "kind-k8s-lab"


def test_matrix_lists_every_addon_and_platform(lab):
    catalog = Catalog.load(lab.root)
    text = render.matrix_markdown(catalog)
    for addon_id in catalog.addons:
        assert f"[{addon_id}]" in text
    assert text.splitlines()[0].count("|") == len(PLATFORMS) + 3


def test_catalog_is_consistent():
    catalog = Catalog.load(REPO)
    assert not catalog.check_files(), catalog.check_files()


def test_every_profile_is_valid_on_a_kubeadm_platform(lab):
    for profile in Catalog.load(lab.root).profiles:
        lab.env(f"ADDON_PROFILE={profile}\nWORKER_COUNT=3")
        plan = lab.plan("vagrant")
        assert plan.ok, (profile, messages(plan))
