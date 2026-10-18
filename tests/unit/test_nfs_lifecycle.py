"""Garde-fous du précontrôle NFS et du nettoyage CSI sur les relances."""
import yaml

from conftest import REPO


def tasks(path: str) -> list[dict]:
    return yaml.safe_load((REPO / path).read_text(encoding="utf-8"))


def test_nfs_preflight_is_conditional_and_runs_after_package_install():
    role = tasks("ansible/roles/node_prereqs/tasks/main.yml")
    packages = next(t for t in role if t.get("name") == "Install the packages required by the selected addons")
    hook = next(t for t in role if t.get("ansible.builtin.include_tasks") == "nfs_preflight.yml")
    assert role.index(packages) < role.index(hook)
    assert "nfs-csi" in hook["when"]
    probe = tasks("ansible/roles/node_prereqs/tasks/nfs_preflight.yml")[0]
    mount = next(t for t in probe["block"] if "bounded read-only mount" in t["name"])
    args = mount["ansible.builtin.command"]["argv"]
    assert "timeout" in args
    assert any("ro,vers={{ cfg.NFS_VERSION }}" in item for item in args)
    commands = [t.get("ansible.builtin.command", {}).get("argv", []) for t in probe["always"]]
    assert any(c and c[0] == "umount" for c in commands)
    assert any(c and c[0] == "rmdir" for c in commands)


def test_cleanup_releases_pods_before_claims_and_protects_pvs():
    cleanup = tasks("ansible/roles/addon/tasks/helpers/test_storageclass_cleanup.yml")
    names = [t["name"] for t in cleanup]
    pod = next(i for i, name in enumerate(names) if name.startswith("Delete the test Pods"))
    pvc = next(i for i, name in enumerate(names) if name.startswith("Delete the test PVCs"))
    pv = next(i for i, name in enumerate(names) if name.startswith("Wait until the current test PVs"))
    sc = next(i for i, name in enumerate(names) if name.startswith("Delete the test StorageClass"))
    assert pod < pvc < pv < sc
    assert "addon_test_sc_pvs" in str(cleanup[sc]["when"])
    assert not any("delete" in str(t.get("ansible.builtin.command", {}))
                   and "'pv'" in str(t.get("ansible.builtin.command", {}))
                   for t in cleanup)


def test_failed_test_details_are_reset_between_addons():
    first = tasks("ansible/roles/addon/tasks/test.yml")[0]["ansible.builtin.set_fact"]
    assert first["addon_test_failed"] is False
    assert first["addon_test_failure"] == ""
