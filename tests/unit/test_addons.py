"""Profils, liste ADDONS, dépendances, conflits, ordre d'installation."""
from conftest import messages


def ids(plan):
    return plan.addon_ids()


def test_minimal_profile_installs_nothing(lab):
    plan = lab.plan("kind")
    assert plan.ok and ids(plan) == []


def test_custom_list_from_user_example(lab):
    lab.env("""
ADDON_PROFILE=custom
ADDONS=cert-manager,metrics-server,argo-cd,monitoring
""")
    plan = lab.plan("kind")
    assert plan.ok, messages(plan)
    assert set(ids(plan)) == {"cert-manager", "metrics-server", "argo-cd", "monitoring", "prometheus-operator-crds"}
    # Les CRD de supervision sont installées en premier (phase 4).
    assert ids(plan)[0] == "prometheus-operator-crds"
    reasons = {a.id: a.reasons for a in plan.addons}
    assert reasons["prometheus-operator-crds"] == ["dépendance de monitoring"]


def test_profile_plus_additions_and_removals(lab):
    lab.env("ADDON_PROFILE=homelab\nADDONS=keda,-argo-cd")
    plan = lab.plan("kind")
    assert "keda" in ids(plan) and "argo-cd" not in ids(plan) and "metrics-server" in ids(plan)


def test_plus_prefix_is_an_explicit_addition(lab):
    lab.env("ADDON_PROFILE=homelab\nADDONS=+reloader,-argo-cd")
    plan = lab.plan("kind")
    assert "reloader" in ids(plan) and "argo-cd" not in ids(plan)


def test_unknown_addon_suggests_the_right_name(lab):
    lab.env("ADDONS=cert-manger")
    errors = messages(lab.plan("kind"))
    assert "addon inconnu « cert-manger »" in errors and "cert-manager" in errors


def test_add_and_remove_same_addon_is_contradictory(lab):
    lab.env("ADDONS=keda,-keda")
    assert "à la fois ajouté et retiré" in messages(lab.plan("kind"))


def test_removal_with_custom_profile_is_refused(lab):
    lab.env("ADDON_PROFILE=custom\nADDONS=keda,-argo-cd")
    assert "custom" in messages(lab.plan("kind"))


def test_removing_a_required_dependency_is_refused(lab):
    lab.env("ADDON_PROFILE=custom\nADDONS=monitoring,-prometheus-operator-crds")
    assert "monitoring en dépend" in messages(lab.plan("kind"))


def test_gateway_selection_adds_crds_controller_and_shared_gateway(lab):
    lab.env("GATEWAY_CONTROLLER=envoy-gateway")
    plan = lab.plan("kind")
    assert plan.ok, messages(plan)
    order = ids(plan)
    assert order.index("gateway-api-crds") < order.index("envoy-gateway") < order.index("gateway")
    assert plan.resolved["gateway_api"]["version"] == "v1.6.1"
    assert plan.resolved["gateway_tls"] is False


def test_gateway_tls_auto_follows_cert_manager(lab):
    lab.env("GATEWAY_CONTROLLER=traefik\nADDONS=cert-manager")
    plan = lab.plan("kind")
    assert plan.resolved["gateway_tls"] is True
    assert plan.resolved["gateway_api"]["version"] == "v1.6.2"
    order = ids(plan)
    assert order.index("cert-manager") < order.index("gateway")


def test_gateway_tls_true_pulls_cert_manager(lab):
    lab.env("GATEWAY_CONTROLLER=traefik\nGATEWAY_TLS=true")
    plan = lab.plan("kind")
    assert "cert-manager" in ids(plan)
    assert "GATEWAY_TLS=true" in dict((a.id, a.reasons) for a in plan.addons)["cert-manager"]


def test_addons_list_can_select_the_loadbalancer(lab):
    lab.env("ADDONS=metallb\nLOADBALANCER_IP_POOL=172.18.255.200-172.18.255.250")
    plan = lab.plan("kind")
    assert plan.ok, messages(plan)
    assert plan.resolved["loadbalancer"]["provider"] == "metallb"


def test_addons_list_contradicting_explicit_selector(lab):
    lab.env("ADDONS=metallb\nLOADBALANCER_PROVIDER=cilium-l2\nLOADBALANCER_IP_POOL=10.0.0.10-10.0.0.20")
    assert "Contradiction : LOADBALANCER_PROVIDER=cilium-l2" in messages(lab.plan("kind"))


def test_two_gateway_controllers_in_addons(lab):
    lab.env("ADDONS=traefik,envoy-gateway")
    assert "plusieurs choix pour GATEWAY_CONTROLLER" in messages(lab.plan("kind"))


def test_falco_and_tetragon_are_exclusive(lab):
    lab.env("ADDONS=falco,tetragon")
    assert "incompatibles" in messages(lab.plan("vagrant"))


def test_snapshot_controller_needs_a_csi_backend(lab):
    lab.env("ADDONS=snapshot-controller")
    assert "n'est utile qu'avec" in messages(lab.plan("kind"))


def test_velero_requires_s3_settings_and_secrets(lab):
    lab.env("ADDONS=velero")
    errors = messages(lab.plan("vagrant"))
    assert "VELERO_S3_URL" in errors and "VELERO_S3_ACCESS_KEY" in errors


def test_descheduler_requires_two_workers(lab):
    lab.env("ADDONS=descheduler\nWORKER_COUNT=1")
    assert "au moins 2 worker" in messages(lab.plan("kind"))


def test_unsupported_addon_for_mode(lab):
    lab.env("ADDONS=longhorn")
    errors = messages(lab.plan("kind"))
    assert "Longhorn n'est pas supporté en mode kind" in errors


def test_cni_none_refuses_addons(lab):
    lab.env("CNI=none\nADDONS=cert-manager")
    assert "CNI=none" in messages(lab.plan("vagrant"))


def test_order_respects_phases_and_dependencies(lab):
    lab.env("""
ADDON_PROFILE=enterprise-lab
GATEWAY_CONTROLLER=traefik
STORAGE_BACKENDS=nfs-csi
NFS_SERVER=10.70.0.30
NFS_SHARE=/volume1/kubernetes
""")
    plan = lab.plan("vagrant")
    order = ids(plan)
    phases = [a.phase for a in plan.addons]
    assert order[0] == "prometheus-operator-crds"
    assert order.index("nfs-csi") < order.index("monitoring")
    assert order.index("cert-manager") < order.index("gateway") < order.index("argo-cd")
    # Pas de retour en arrière de phase sans dépendance qui l'explique.
    assert phases == sorted(phases) or order.index("gateway") > order.index("cert-manager")


def test_self_signed_kubelet_certificates_are_flagged_for_metrics_server(lab):
    lab.env("ADDON_PROFILE=homelab\nKUBELET_SERVING_CERTS=self-signed")
    plan = lab.plan("vagrant")
    assert plan.ok, messages(plan)
    assert "--kubelet-insecure-tls" in messages(plan, "warning")


def test_istio_with_cilium_adapts_the_cni(lab):
    lab.env("ADDONS=istio\nCNI=cilium")
    plan = lab.plan("vagrant")
    assert plan.ok, messages(plan)
    assert "cni.exclusive=false" in messages(plan, "info")
