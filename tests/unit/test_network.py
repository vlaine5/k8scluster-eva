"""CNI, Gateway, LoadBalancer, CIDR et plages d'adresses."""
import pytest
from conftest import messages

from labcore import netutil

HOMELAB_RESERVED = ("10.10.0.0/16,10.30.0.0/16,10.60.0.0/16,10.70.0.0/16,10.101.0.0/16,"
                    "10.102.0.0/16,10.103.0.0/16,10.104.0.0/16,10.105.0.0/16")


@pytest.mark.parametrize("text,first,last", [
    ("10.20.0.200-10.20.0.210", "10.20.0.200", "10.20.0.210"),
    ("10.20.0.200/29", "10.20.0.200", "10.20.0.207"),
    ("10.20.0.5", "10.20.0.5", "10.20.0.5"),
])
def test_parse_range(text, first, last):
    rng = netutil.parse_range(text)
    assert (str(rng.first), str(rng.last)) == (first, last)


@pytest.mark.parametrize("text", ["10.20.0.210-10.20.0.200", "10.20.0.300", "fe80::1", "10.0.0.1/33"])
def test_invalid_ranges(text):
    with pytest.raises(netutil.NetError):
        netutil.parse_range(text)


def test_default_service_cidr_overlaps_homelab_vlans(lab):
    # 10.96.0.0/12 couvre 10.96.0.0 - 10.111.255.255 : il masque 10.101-105.0.0/16.
    lab.env(f"RESERVED_CIDRS={HOMELAB_RESERVED}")
    errors = messages(lab.plan("vagrant"))
    assert "SERVICE_CIDR=10.96.0.0/12 chevauche le réseau réservé 10.101.0.0/16" in errors


def test_homelab_cidrs_are_accepted(lab):
    lab.env(f"RESERVED_CIDRS={HOMELAB_RESERVED}\nSERVICE_CIDR=10.250.0.0/16")
    plan = lab.plan("vagrant")
    assert plan.ok, messages(plan)


def test_pod_and_service_overlap(lab):
    lab.env("POD_CIDR=10.96.0.0/16\nSERVICE_CIDR=10.96.0.0/12")
    assert "se chevauchent" in messages(lab.plan("kind"))


def test_pod_cidr_overlapping_node_network(lab):
    lab.env("NODE_NETWORK_CIDR=10.244.0.0/24")
    assert "chevauche le réseau des nœuds" in messages(lab.plan("terraform", "proxmox"))


def test_pod_cidr_too_small_for_node_count(lab):
    lab.env("POD_CIDR=10.244.0.0/23\nWORKER_COUNT=3")
    assert "ne permet que 2 nœud(s)" in messages(lab.plan("vagrant"))


def proxmox_homelab(lab, extra=""):
    lab.env(f"""
CNI=flannel
WORKER_COUNT=3
LOADBALANCER_PROVIDER=metallb
RESERVED_IPS=10.20.0.1,10.20.0.31
{extra}
""")
    lab.tfvars("proxmox", 'proxmox_node = "pv05"\nnetwork_cidr = "10.20.0.0/16"\nip_start = 100\ngateway = "10.20.0.1"\n')
    return lab.plan("terraform", "proxmox")


def test_valid_metallb_pool(lab):
    plan = proxmox_homelab(lab, "LOADBALANCER_IP_POOL=10.20.0.200-10.20.0.210")
    assert plan.ok, messages(plan)
    assert [n["ip"] for n in plan.nodes] == ["10.20.0.100", "10.20.0.101", "10.20.0.102", "10.20.0.103"]
    assert plan.resolved["loadbalancer_pool_size"] == 11


def test_proxmox_node_ip_prefix_uses_16_mask_and_four_nodes(lab):
    """Le /16 vient de network_cidr ; le prefixe choisit seulement 10.20.50.x."""
    lab.env("""
NODE_NETWORK_CIDR=10.20.0.0/16
WORKER_COUNT=3
CNI=flannel
LOADBALANCER_PROVIDER=metallb
LOADBALANCER_IP_POOL=10.20.80.100-10.20.80.200
RESERVED_IPS=10.20.0.1,10.20.0.31
""")
    lab.tfvars("proxmox", """
proxmox_node = "pv05"
network_cidr = "10.20.0.0/16"
node_ip_prefix = "10.20.50"
ip_start = 10
gateway = "10.20.0.1"
""")
    plan = lab.plan("terraform", "proxmox")
    assert plan.ok, messages(plan)
    assert [n["ip"] for n in plan.nodes] == [
        "10.20.50.10", "10.20.50.11", "10.20.50.12", "10.20.50.13"
    ]


def test_proxmox_node_ip_prefix_outside_vlan_is_refused(lab):
    lab.env("NODE_NETWORK_CIDR=10.20.0.0/16")
    lab.tfvars("proxmox", """
proxmox_node = "pv05"
network_cidr = "10.20.0.0/16"
node_ip_prefix = "10.21.50"
ip_start = 10
""")
    assert "hors du reseau" in messages(lab.plan("terraform", "proxmox"))


def test_proxmox_node_ip_prefix_last_octet_does_not_overflow(lab):
    lab.env("NODE_NETWORK_CIDR=10.20.0.0/16\nWORKER_COUNT=3")
    lab.tfvars("proxmox", """
proxmox_node = "pv05"
network_cidr = "10.20.0.0/16"
node_ip_prefix = "10.20.50"
ip_start = 254
""")
    assert "depassent le dernier octet" in messages(lab.plan("terraform", "proxmox"))


def test_pool_outside_node_network_in_l2(lab):
    assert "hors du réseau des nœuds" in messages(proxmox_homelab(lab, "LOADBALANCER_IP_POOL=10.30.0.200-10.30.0.210"))


def test_pool_overlapping_a_node(lab):
    assert "contient l'adresse du nœud k8s-worker-1" in messages(
        proxmox_homelab(lab, "LOADBALANCER_IP_POOL=10.20.0.95-10.20.0.105"))


def test_pool_overlapping_reserved_ips(lab):
    assert "adresse réservée" in messages(proxmox_homelab(lab, "LOADBALANCER_IP_POOL=10.20.0.30-10.20.0.40"))


def test_pool_containing_the_api_vip(lab):
    errors = messages(proxmox_homelab(lab, "LOADBALANCER_IP_POOL=10.20.0.200-10.20.0.210\nCONTROL_PLANE_VIP=10.20.0.205"))
    assert "contient la VIP de l'API" in errors


def test_node_on_a_reserved_ip(lab):
    plan = proxmox_homelab(lab, "LOADBALANCER_IP_POOL=10.20.0.200-10.20.0.210\nRESERVED_IPS=10.20.0.101")
    assert "utilise une adresse réservée" in messages(plan)


def test_metallb_without_pool(lab):
    assert "exige LOADBALANCER_IP_POOL" in messages(proxmox_homelab(lab))


def test_tfvars_cannot_duplicate_env_managed_settings(lab):
    lab.env("WORKER_COUNT=3")
    lab.tfvars("proxmox", 'proxmox_node = "pv05"\nnetwork_cidr = "10.20.0.0/16"\nworker_count = 2\n')
    assert "pilotés par .env" in messages(lab.plan("terraform", "proxmox"))


def test_metallb_on_eks_is_refused(lab):
    lab.env("LOADBALANCER_PROVIDER=metallb\nLOADBALANCER_IP_POOL=10.0.0.1-10.0.0.5")
    assert "n'a pas de sens sur EKS" in messages(lab.plan("terraform", "eks"))


def test_bgp_requires_explicit_peer(lab):
    plan = proxmox_homelab(lab, "LOADBALANCER_IP_POOL=10.20.0.200-10.20.0.210\nLOADBALANCER_MODE=bgp")
    assert "Le mode BGP exige BGP_LOCAL_ASN" in messages(plan)


def test_cilium_full_stack(lab):
    plan = proxmox_homelab(lab, """
CNI=cilium
GATEWAY_CONTROLLER=cilium
LOADBALANCER_PROVIDER=cilium-l2
LOADBALANCER_IP_POOL=10.20.0.200-10.20.0.210
ENABLE_HUBBLE=true
NETWORK_POLICY_MODE=cilium
KUBERNETES_VERSION=1.36.5
""")
    assert plan.ok, messages(plan)
    assert plan.resolved["kube_proxy_mode"] == "cilium"
    assert {"cilium-gateway", "cilium-lb", "hubble", "gateway", "gateway-api-crds"} <= set(plan.addon_ids())
    assert "metallb" not in plan.addon_ids()
    assert plan.resolved["gateway_api"]["install_with_cni"] is True


def test_hubble_with_flannel_is_refused(lab):
    lab.env("CNI=flannel\nENABLE_HUBBLE=true")
    assert "ENABLE_HUBBLE=true exige CNI=cilium" in messages(lab.plan("vagrant"))


def test_cilium_gateway_without_cilium(lab):
    lab.env("CNI=calico\nGATEWAY_CONTROLLER=cilium")
    assert "GATEWAY_CONTROLLER=cilium exige CNI=cilium" in messages(lab.plan("vagrant"))


def test_cilium_gateway_without_kube_proxy_replacement(lab):
    lab.env("CNI=cilium\nKUBE_PROXY_MODE=iptables\nGATEWAY_CONTROLLER=cilium")
    assert "remplacement de kube-proxy" in messages(lab.plan("vagrant"))


def test_cilium_lb_with_flannel(lab):
    lab.env("CNI=flannel\nLOADBALANCER_PROVIDER=cilium-l2\nLOADBALANCER_IP_POOL=192.168.56.200-192.168.56.210")
    assert "exige CNI=cilium" in messages(lab.plan("vagrant"))


def test_network_policy_with_flannel_is_refused(lab):
    lab.env("CNI=flannel\nNETWORK_POLICY_MODE=kubernetes")
    assert "n'applique pas les NetworkPolicy" in messages(lab.plan("vagrant"))


def test_cni_mode_validation(lab):
    lab.env("CNI=flannel\nCNI_MODE=ipip")
    assert "CNI_MODE=ipip n'existe pas pour flannel" in messages(lab.plan("vagrant"))


def test_calico_modes(lab):
    lab.env("CNI=calico\nCNI_MODE=vxlan-crosssubnet")
    plan = lab.plan("vagrant")
    assert plan.ok and plan.resolved["network_policy_mode"] == "calico"


def test_kind_keeps_its_native_cni(lab):
    lab.env("CNI=flannel")
    plan = lab.plan("kind")
    assert plan.ok and plan.resolved["cni"] == "kindnet"
    assert "kind utilise son CNI natif" in messages(plan, "warning")


def test_kind_with_cilium_uses_dedicated_config(lab):
    lab.env("CNI=cilium")
    plan = lab.plan("kind")
    assert plan.resolved["cni_install"] == "helm-local" and plan.resolved["kube_proxy_mode"] == "cilium"


def test_eks_refuses_another_cni(lab):
    lab.env("CNI=calico")
    assert "AWS VPC CNI" in messages(lab.plan("terraform", "eks"))


def test_flannel_version_without_checksum(lab):
    lab.env("CNI=flannel\nCNI_VERSION=v0.20.0")
    assert "aucune empreinte SHA-256" in messages(lab.plan("vagrant"))


def test_cilium_on_kubernetes_137_warns_then_strict_refuses(lab):
    lab.env("CNI=cilium\nKUBERNETES_VERSION=1.37.1")
    assert "n'est pas déclaré testé" in messages(lab.plan("vagrant"), "warning")
    lab.env("CNI=cilium\nKUBERNETES_VERSION=1.37.1\nCOMPATIBILITY_POLICY=strict")
    assert "n'est pas déclaré testé" in messages(lab.plan("vagrant"))
