"""Plan de mise à niveau de Kubernetes (make upgrade-plan), sans cluster."""
from __future__ import annotations

from labcore import upgrade
from labcore.catalog import Catalog


def node(name: str, kubelet: str, ready: bool = True, cordoned: bool = False) -> dict:
    return {"metadata": {"name": name}, "spec": {"unschedulable": cordoned},
            "status": {"nodeInfo": {"kubeletVersion": kubelet},
                       "conditions": [{"type": "Ready", "status": "True" if ready else "False"}]}}


def build(lab, version: str, server: str, nodes=None, policy: str = "minor"):
    lab.env(f"KUBERNETES_VERSION={version}\nUPGRADE_POLICY={policy}")
    plan = lab.plan("vagrant")
    return upgrade.build(plan, Catalog.load(lab.root), policy, server, nodes or [node("cp-1", server)])


def test_minor_upgrade_lists_the_official_steps(lab):
    up = build(lab, "1.37.1", "v1.36.5")
    assert up.code == 0 and not up.errors
    assert any("kubeadm upgrade apply v1.37.1" in s for s in up.steps)
    assert up.steps[0].startswith("Instantané etcd")


def test_same_version_is_nothing_to_do(lab):
    up = build(lab, "1.36.5", "v1.36.5")
    assert up.code == upgrade.NOTHING_TO_DO


def test_two_minors_at_once_is_refused_with_the_path(lab):
    up = build(lab, "1.37.1", "v1.35.9")
    assert up.code == 1
    assert "1.35.9 -> 1.36.5 -> 1.37.1" in " ".join(up.errors)


def test_downgrade_is_refused(lab):
    up = build(lab, "1.36.5", "v1.37.1")
    assert up.code == 1 and "rétrogradation" in " ".join(up.errors)


def test_patch_policy_refuses_a_minor_change(lab):
    up = build(lab, "1.37.1", "v1.36.5", policy="patch")
    assert up.code == 1 and "UPGRADE_POLICY=patch" in " ".join(up.errors)


def test_patch_policy_accepts_a_patch(lab):
    up = build(lab, "1.36.5", "v1.36.4", policy="patch")
    assert up.code == 0


def test_not_ready_node_blocks_the_upgrade(lab):
    up = build(lab, "1.37.1", "v1.36.5", nodes=[node("cp-1", "v1.36.5"), node("w-1", "v1.36.5", ready=False)])
    assert up.code == 1 and "w-1 n'est pas Ready" in " ".join(up.errors)


def test_kubelet_newer_than_target_is_refused(lab):
    up = build(lab, "1.36.5", "v1.36.4", nodes=[node("w-1", "v1.37.1")])
    assert up.code == 1 and "plus récent" in " ".join(up.errors)


def test_managed_platforms_have_no_kubeadm_upgrade(lab):
    lab.env("KUBERNETES_VERSION=1.36.5")
    plan = lab.plan("kind")
    up = upgrade.build(plan, Catalog.load(lab.root), "minor", "v1.36.4", [])
    assert up.code == 1 and "kubeadm" in up.errors[0]
