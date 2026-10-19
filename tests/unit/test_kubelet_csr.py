"""Le contrôle kubelet-serving est sûr, strict TLS et réexécutable sans CSR historique."""
import yaml

from conftest import REPO


def verifier():
    path = REPO / "ansible/roles/cluster_core/tasks/verify_csr.yml"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_empty_csr_list_must_not_fail_a_rerun():
    tasks = verifier()
    assert not any("difference(" in str(t) for t in tasks)
    assert any("Denied" in str(t.get("ansible.builtin.assert", {}))
               for t in tasks)
    assert any(t.get("name", "").startswith("Wait until no kubelet serving")
               for t in tasks)


def test_live_server_tls_uses_ca_san_and_rejects_insecure_fallbacks():
    tasks = verifier()
    live = next(t for t in tasks if t.get("name", "").startswith("Verify every live kubelet"))
    args = live["ansible.builtin.command"]["argv"]
    assert args[0] == "curl"
    assert args[args.index("--cacert") + 1] == "/etc/kubernetes/pki/ca.crt"
    assert "https://{{ hostvars[item]['k8s_node_ip'] }}:10250/healthz" in args
    assert args[args.index("--noproxy") + 1] == "*"
    assert "--insecure" not in args and "-k" not in args
    assert "cluster_core_kubelet_tls_check.rc == 0" in live["until"]
    assert "401" in live["until"] and "403" in live["until"]
    assert live["changed_when"] is False
    assert live["retries"] >= 12
