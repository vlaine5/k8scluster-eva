"""Résolution et validation de la configuration effective.

Entrée : Config (lab.env/.env/environnement) + Catalog + mode/provider.
Sortie : Plan = choix résolus (CNI, Gateway, LoadBalancer, stockage, OS,
topologie...), liste ORDONNÉE des addons avec la raison de leur présence,
et la liste des problèmes (erreurs bloquantes, avertissements, notes).

Aucune action n'est effectuée ici : tout est vérifiable AVANT de créer
la moindre ressource.
"""
from __future__ import annotations

import difflib
import heapq
import ipaddress
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

from . import inventory as inv
from . import netutil
from .catalog import Addon, Catalog
from .config import Config
from .schema import to_bool

MODES = ["kind", "minikube", "vagrant", "terraform", "existing", "attach"]
PROVIDERS = ["proxmox", "vsphere", "libvirt", "eks"]
KUBEADM_PLATFORMS = {"vagrant", "proxmox", "vsphere", "libvirt", "existing"}
VM_PLATFORMS = {"vagrant", "proxmox", "vsphere", "libvirt"}
TERRAFORM_VM = {"proxmox", "vsphere", "libvirt"}
LOCAL_PLATFORMS = {"kind", "minikube"}
# Plateformes où un LoadBalancer « bare metal » (MetalLB, Cilium L2/BGP) a un sens.
BAREMETAL_LB = KUBEADM_PLATFORMS | {"kind", "attach"}

CNI_MODES = {
    "flannel": {"vxlan", "host-gw"},
    "calico": {"vxlan", "vxlan-crosssubnet", "ipip", "ipip-crosssubnet", "direct"},
    "cilium": {"vxlan", "geneve", "native"},
}
CNI_DEFAULT_MODE = {"flannel": "vxlan", "calico": "vxlan", "cilium": "vxlan"}
NETPOL_DEFAULT = {"flannel": "none", "calico": "calico", "cilium": "cilium", "kindnet": "kubernetes",
                  "aws-vpc-cni": "none", "none": "none", "minikube": "none", "existing": "unknown"}
GATEWAY_ADDON = {"traefik": "traefik", "envoy-gateway": "envoy-gateway", "cilium": "cilium-gateway"}
LB_ADDON = {"metallb": "metallb", "cilium-l2": "cilium-lb", "cilium-bgp": "cilium-lb"}
CPU_LEVEL_V3 = {"x86-64-v3", "x86-64-v4", "host", "max"}


@dataclass
class Issue:
    level: str  # error | warning | info
    message: str
    hint: str = ""


@dataclass
class AddonPlan:
    id: str
    phase: int
    reasons: list[str]
    support: str
    support_note: str
    components: list[dict[str, str]]
    addon: Addon = field(repr=False, default=None)  # type: ignore[assignment]


@dataclass
class Plan:
    mode: str
    provider: str
    platform: str
    issues: list[Issue] = field(default_factory=list)
    resolved: dict[str, Any] = field(default_factory=dict)
    addons: list[AddonPlan] = field(default_factory=list)
    nodes: list[dict[str, Any]] = field(default_factory=list)

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "error"]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "warning"]

    @property
    def infos(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "info"]

    @property
    def ok(self) -> bool:
        return not self.errors

    def addon_ids(self) -> list[str]:
        return [a.id for a in self.addons]


def platform_of(mode: str, provider: str) -> str:
    return provider if mode == "terraform" else mode


def minor_of(version: str) -> str:
    parts = version.lstrip("v").split(".")
    return ".".join(parts[:2]) if len(parts) >= 2 else version


def version_tuple(version: str) -> tuple[int, ...]:
    out = []
    for part in version.lstrip("v").split("."):
        digits = "".join(ch for ch in part if ch.isdigit())
        out.append(int(digits) if digits else 0)
    return tuple(out)


class Resolver:
    def __init__(self, cfg: Config, catalog: Catalog, mode: str, provider: str = "",
                 cluster_version: str = ""):
        self.cfg = cfg
        self.catalog = catalog
        self.mode = mode
        self.provider = provider
        self.platform = platform_of(mode, provider)
        self.plan = Plan(mode=mode, provider=provider, platform=self.platform)
        self.r = self.plan.resolved
        self.cluster_version = cluster_version  # mode attach : version détectée
        self.selected: dict[str, list[str]] = {}
        self.removed: set[str] = set()

    # --- messages ---------------------------------------------------------------
    def error(self, message: str, hint: str = "") -> None:
        self.plan.issues.append(Issue("error", message, hint))

    def warn(self, message: str, hint: str = "") -> None:
        self.plan.issues.append(Issue("warning", message, hint))

    def info(self, message: str, hint: str = "") -> None:
        self.plan.issues.append(Issue("info", message, hint))

    @property
    def kubeadm(self) -> bool:
        return self.platform in KUBEADM_PLATFORMS

    # --- point d'entrée -----------------------------------------------------------
    def run(self) -> Plan:
        if not self._check_mode():
            return self.plan
        for message in self.cfg.file_warnings:
            self.warn(message)
        for key in self.cfg.unknown_keys():
            close = difflib.get_close_matches(key, list(self.cfg.schema.variables), n=1)
            self.warn(f".env : variable inconnue {key}" + (f" (vouliez-vous {close[0]} ?)" if close else ""),
                      "Elle n'a aucun effet. Liste des variables : docs/configuration.md")
        for message in self.cfg.type_errors():
            self.error(message, "Corrigez la valeur dans .env (référence : docs/configuration.md)")
        if self.plan.errors:
            return self.plan  # inutile d'aller plus loin avec des valeurs mal typées
        self._deprecations()
        self._names()
        self._kubernetes_version()
        self._topology()
        self._operating_system()
        self._cni()
        self._networks()
        self._selectors()
        self._storage()
        self._addons()
        self._backup()
        self._compatibility()
        self._capacity()
        return self.plan

    # --- mode et provider ------------------------------------------------------------
    def _check_mode(self) -> bool:
        if self.mode not in MODES:
            self.error(f"Mode inconnu : « {self.mode} ».", f"Modes : {', '.join(MODES)}")
            return False
        if self.mode == "terraform":
            if self.provider not in PROVIDERS:
                self.error(f"Provider Terraform inconnu ou absent : « {self.provider} ».",
                           f"Providers : {', '.join(PROVIDERS)} (PROVIDER=... ou DEPLOYMENT_PROVIDER dans .env)")
                return False
        elif self.provider:
            self.error(f"Le mode {self.mode} ne prend pas de provider (reçu : {self.provider}).")
            return False
        return True

    def _deprecations(self) -> None:
        cfg = self.cfg
        for key, spec in cfg.schema.variables.items():
            if spec.deprecated and cfg.get(key):
                self.info(f"{key} est un ancien nom, toujours accepté : préférez {spec.deprecated}.")
        if cfg.get("NODE_IMAGE_URL") and cfg.get("VM_IMAGE_URL") and cfg.get("NODE_IMAGE_URL") != cfg.get("VM_IMAGE_URL"):
            self.error("NODE_IMAGE_URL et VM_IMAGE_URL sont définies avec des valeurs différentes.",
                       "Gardez seulement NODE_IMAGE_URL (VM_IMAGE_URL est l'ancien nom).")
        if cfg.get("NODE_IMAGE_SHA256") and cfg.get("VM_IMAGE_SHA256") and cfg.get("NODE_IMAGE_SHA256") != cfg.get("VM_IMAGE_SHA256"):
            self.error("NODE_IMAGE_SHA256 et VM_IMAGE_SHA256 sont différentes.", "Gardez seulement NODE_IMAGE_SHA256.")

    def _names(self) -> None:
        name = self.cfg.get("CLUSTER_NAME")
        contexts = {
            "kind": f"kind-{name}", "minikube": name, "vagrant": f"{name}-vagrant",
            "proxmox": f"{name}-proxmox", "vsphere": f"{name}-vsphere", "libvirt": f"{name}-libvirt",
            "eks": f"{name}-eks", "existing": f"{name}-existing",
        }
        self.r["cluster_name"] = name
        self.r["mode"] = self.mode
        self.r["provider"] = self.provider
        self.r["platform"] = self.platform
        self.r["kubeadm"] = self.kubeadm
        lab_kubeconfig = str(self.cfg.root / ".kube" / "config")
        if self.platform == "attach":
            kubeconfig = self.cfg.get("EXISTING_KUBECONFIG")
            context = self.cfg.get("EXISTING_CONTEXT")
            if not kubeconfig:
                self.error("Mode attach : EXISTING_KUBECONFIG n'est pas défini.",
                           "Indiquez le chemin du kubeconfig du cluster existant dans .env.")
            else:
                path = Path(kubeconfig).expanduser()
                if not path.is_absolute():
                    path = self.cfg.root / path
                if not path.is_file():
                    self.error(f"Mode attach : kubeconfig introuvable : {path}")
                kubeconfig = str(path)
            if not context:
                self.error("Mode attach : EXISTING_CONTEXT n'est pas défini.",
                           "Le contexte doit être nommé explicitement : le framework n'utilise jamais "
                           "le contexte « courant » d'un kubeconfig pour modifier un cluster.")
            self.r["kubeconfig"] = kubeconfig
            self.r["kube_context"] = context
        else:
            self.r["kubeconfig"] = lab_kubeconfig
            self.r["kube_context"] = contexts.get(self.platform, name)
        if self.platform == "eks" and len(name) > 25:
            self.error(f"CLUSTER_NAME={name} est trop long pour EKS (25 caractères au plus).")

    # --- version de Kubernetes ----------------------------------------------------------
    def _kubernetes_version(self) -> None:
        cfg, lock = self.cfg, self.catalog.versions["kubernetes"]
        version = cfg.get("KUBERNETES_VERSION")
        minor = minor_of(version)
        self.r["kubernetes_version"] = version
        if self.kubeadm:
            if minor not in lock["supported_minors"]:
                self.error(f"KUBERNETES_VERSION={version} : la mineure {minor} n'est pas supportée par le framework.",
                           f"Mineures supportées : {', '.join(lock['supported_minors'])} (config/versions.yaml).")
            latest = lock.get("latest_patches", {}).get(minor)
            if latest and version_tuple(version) < version_tuple(latest):
                self.info(f"Kubernetes {version} : le correctif {latest} est disponible (make versions-check).")
            effective = minor
        elif self.platform == "kind":
            image = cfg.get("KIND_NODE_IMAGE")
            if not image:
                image = lock.get("kind_node_images", {}).get(minor, "")
                if not image:
                    self.error(f"Aucune image kind épinglée pour Kubernetes {minor}.",
                               "Choisissez une version de config/versions.yaml (kind_node_images) ou définissez KIND_NODE_IMAGE.")
            self.r["kind_node_image"] = image
            tag = image.split(":")[1].split("@")[0] if ":" in image else ""
            effective = minor_of(tag) if tag else minor
            if tag and minor_of(tag) != minor:
                self.warn(f"KIND_NODE_IMAGE ({tag}) ne correspond pas à KUBERNETES_VERSION ({version}) : "
                          f"la compatibilité des addons est évaluée pour {minor_of(tag)}.")
        elif self.platform == "minikube":
            mk = cfg.get("MINIKUBE_KUBERNETES_VERSION") or f"v{version}"
            self.r["minikube_kubernetes_version"] = mk
            effective = minor_of(mk)
        elif self.platform == "eks":
            effective = cfg.get("EKS_KUBERNETES_VERSION")
            if cfg.explicit("KUBERNETES_VERSION"):
                self.info("EKS utilise EKS_KUBERNETES_VERSION ; KUBERNETES_VERSION ne concerne que kubeadm.")
        else:  # attach
            effective = minor_of(self.cluster_version) if self.cluster_version else ""
        self.r["kubernetes_minor"] = effective
        if self.kubeadm:
            containerd = cfg.get("CONTAINERD_VERSION") or self.catalog.versions["containerd"]["version"]
            self.r["containerd_version"] = containerd

    # --- topologie -----------------------------------------------------------------------
    def _topology(self) -> None:
        cfg = self.cfg
        cp = cfg.int("CONTROL_PLANE_COUNT", 1)
        workers = cfg.int("WORKER_COUNT", 2)
        ha_mode = cfg.get("HA_MODE", "auto")
        if self.platform == "attach":
            for key in ("CONTROL_PLANE_COUNT", "WORKER_COUNT", "HA_MODE"):
                if cfg.explicit(key):
                    self.info(f"{key} est ignoré en mode attach (le cluster existe déjà).")
            self.r.update(control_plane_count=None, worker_count=None, ha_mode="existing")
            return
        if self.platform == "existing":
            cp, workers = self._existing_inventory(cp, workers)
        if self.platform == "eks":
            if cp != 1:
                self.error(f"CONTROL_PLANE_COUNT={cp} : sur EKS, le control-plane est géré (et déjà hautement "
                           "disponible) par AWS.", "Laissez CONTROL_PLANE_COUNT=1 pour le mode eks.")
            if workers < 1:
                self.error("EKS a besoin d'au moins 1 worker (CoreDNS s'exécute sur les workers).")
            if ha_mode not in ("auto", "off"):
                self.error(f"HA_MODE={ha_mode} n'a pas de sens sur EKS (control-plane géré par AWS).")
            self.r.update(control_plane_count=1, worker_count=workers, ha_mode="managed")
            return
        if cp % 2 == 0:
            self.error(f"CONTROL_PLANE_COUNT={cp} : un nombre PAIR de control-planes n'apporte aucune tolérance "
                       f"de panne supplémentaire à etcd (quorum = {cp // 2 + 1}) et augmente le risque.",
                       "Utilisez 1 (standard), 3 (tolère 1 panne) ou 5 (tolère 2 pannes).")
        if self.platform == "minikube" and cp not in (1, 3):
            self.error("Minikube ne propose que 1 control-plane, ou 3 avec son option --ha.")
        if self.platform == "minikube" and cp == 3:
            self.warn("Minikube --ha (3 control-planes) est expérimental et lourd pour un poste de travail.")
        if ha_mode == "external-etcd":
            self.error("HA_MODE=external-etcd n'est pas encore implémenté (évolution prévue).",
                       "Utilisez HA_MODE=stacked-etcd (etcd sur les control-planes) : docs/high-availability.md")
        resolved_ha = "off" if cp == 1 else "stacked-etcd"
        if ha_mode == "off" and cp > 1:
            self.error(f"HA_MODE=off est contradictoire avec CONTROL_PLANE_COUNT={cp}.",
                       "Mettez HA_MODE=auto (ou stacked-etcd), ou CONTROL_PLANE_COUNT=1.")
        if ha_mode == "stacked-etcd" and cp == 1:
            self.error("HA_MODE=stacked-etcd demande au moins 3 control-planes (CONTROL_PLANE_COUNT=3).")
        self.r.update(control_plane_count=cp, worker_count=workers, ha_mode=resolved_ha)
        if cp > 1:
            self.info(f"Mode HA : {cp} control-planes, etcd empilé, quorum {cp // 2 + 1}, tolère "
                      f"{(cp - 1) // 2} panne(s) de control-plane.")
            if self.platform in VM_PLATFORMS | {"existing"}:
                self.warn("Des control-planes hébergés sur UN SEUL hyperviseur ne protègent pas contre la panne "
                          "de cet hyperviseur : la HA obtenue est logicielle, pas physique.",
                          "Répartissez les VMs sur plusieurs hôtes (proxmox_nodes, anti-affinité vSphere) : "
                          "docs/high-availability.md")
        if workers == 0:
            self.info("WORKER_COUNT=0 : cluster mono-nœud, le control-plane accepte les Pods applicatifs.")
        self._api_endpoint(cp)
        self._node_addresses(cp, workers)

    def _api_endpoint(self, cp: int) -> None:
        cfg = self.cfg
        provider = cfg.get("API_LB_PROVIDER", "auto")
        vip = cfg.get("CONTROL_PLANE_VIP")
        endpoint = cfg.get("CONTROL_PLANE_ENDPOINT", "auto")
        if self.platform in ("kind", "minikube"):
            self.r.update(api_lb_provider="platform", control_plane_vip="", control_plane_endpoint="auto")
            if vip or provider not in ("auto", "none"):
                self.warn(f"CONTROL_PLANE_VIP/API_LB_PROVIDER sont ignorés en mode {self.platform} "
                          "(il fournit son propre accès à l'API).")
            return
        if self.platform == "vagrant" and cp > 1 and not vip and provider in ("auto", "kube-vip"):
            prefix, start = cfg.get("VAGRANT_NETWORK_PREFIX"), cfg.int("VAGRANT_IP_START", 10)
            vip = f"{prefix}.{start - 1}"
            self.info(f"Vagrant HA : VIP de l'API choisie automatiquement dans le réseau privé : {vip}")
        if provider == "auto":
            provider = "kube-vip" if (cp > 1 or vip) else "none"
            if endpoint != "auto" and not vip:
                provider = "external"
        if cp > 1 and provider == "none":
            self.error(f"{cp} control-planes exigent une adresse d'API stable et répartie.",
                       "API_LB_PROVIDER=kube-vip avec CONTROL_PLANE_VIP, ou API_LB_PROVIDER=external avec "
                       "CONTROL_PLANE_ENDPOINT=<votre-lb>:6443.")
        if provider == "kube-vip" and not vip:
            self.error("API_LB_PROVIDER=kube-vip exige CONTROL_PLANE_VIP (une IP libre du réseau des nœuds).",
                       "Le framework ne choisit jamais une IP sur votre réseau à votre place : vérifiez-la dans "
                       "votre IPAM.")
        if provider == "external" and endpoint == "auto":
            self.error("API_LB_PROVIDER=external exige CONTROL_PLANE_ENDPOINT=<hôte>:<port> (votre répartiteur).")
        if self.platform == "eks":
            provider = "managed"
        if endpoint == "auto":
            endpoint = f"{vip}:6443" if vip else ""
        self.r.update(api_lb_provider=provider, control_plane_vip=vip, control_plane_endpoint=endpoint)
        if provider == "kube-vip":
            self.info(f"API Kubernetes : VIP {vip} portée par kube-vip (ARP) sur les control-planes. "
                      "À ne pas confondre avec MetalLB, qui sert les Services applicatifs.")

    def _existing_inventory(self, cp: int, workers: int) -> tuple[int, int]:
        cfg = self.cfg
        path_value = cfg.get("EXISTING_INVENTORY")
        if not path_value:
            self.error("Mode existing : EXISTING_INVENTORY n'est pas défini.",
                       "Décrivez vos machines dans un inventaire (modèle : ansible/inventories/existing.example.ini).")
            return cp, workers
        path = Path(path_value).expanduser()
        if not path.is_absolute():
            path = cfg.root / path
        try:
            inventory = inv.load_inventory(path)
        except inv.InventoryError as exc:
            self.error(f"Mode existing : {exc}")
            return cp, workers
        self.r["existing_inventory"] = str(path)
        cps, wks = inventory.control_planes, inventory.workers
        if not cps:
            self.error(f"{path} : aucun hôte dans le groupe [control_plane].")
        both = {h.name for h in cps} & {h.name for h in wks}
        if both:
            self.error(f"{path} : hôte(s) à la fois control-plane et worker : {', '.join(sorted(both))}.")
        missing_parent = [h.name for h in cps + wks if "k8s_cluster" not in h.groups]
        if missing_parent:
            self.error(f"{path} : les groupes control_plane et workers doivent être enfants de [k8s_cluster:children].")
        for key in ("CONTROL_PLANE_COUNT", "WORKER_COUNT"):
            declared = cfg.int(key)
            actual = len(cps) if key == "CONTROL_PLANE_COUNT" else len(wks)
            if cfg.explicit(key) and declared != actual:
                self.error(f"{key}={declared} mais l'inventaire {path.name} en déclare {actual}.",
                           f"Alignez {key} sur l'inventaire, ou retirez {key} de .env (il sera déduit).")
        for host in cps + wks:
            for secret_var in ("ansible_password", "ansible_ssh_pass", "ansible_become_password", "ansible_become_pass"):
                value = host.vars.get(secret_var) or inventory.var(secret_var)
                if value and "{{" not in value:
                    self.error(f"{path} : {host.name} contient un mot de passe en clair ({secret_var}).",
                               "Utilisez une clé SSH (ansible_ssh_private_key_file) et sudo sans mot de passe, "
                               "ou ansible-vault / --ask-become-pass. Jamais de mot de passe dans un inventaire.")
                    break
        addresses = [h.address for h in cps + wks]
        duplicates = sorted({a for a in addresses if addresses.count(a) > 1})
        if duplicates:
            self.error(f"{path} : adresse(s) en double : {', '.join(duplicates)}.")
        self.plan.nodes = [{"name": h.name, "role": "control_plane", "ip": h.address} for h in cps] + \
                          [{"name": h.name, "role": "worker", "ip": h.address} for h in wks]
        network = inventory.var("node_network_cidr")
        if network and not cfg.get("NODE_NETWORK_CIDR"):
            self.r["node_network_cidr"] = network
        os_vars = {h.vars.get("node_os") for h in cps + wks if h.vars.get("node_os")}
        self.r["existing_declared_os"] = sorted(os_vars)
        return len(cps), len(wks)

    def _node_addresses(self, cp: int, workers: int) -> None:
        """Adresses prévues des nœuds (VMs) ; mode existing : déjà lues dans l'inventaire."""
        cfg = self.cfg
        prefix = cfg.get("NODE_HOSTNAME_PREFIX")
        network = cfg.get("NODE_NETWORK_CIDR") or self.r.get("node_network_cidr", "")
        if self.platform in TERRAFORM_VM:
            tf_dir = cfg.root / "terraform" / "providers" / self.platform
            tfvars = inv.read_tfvars(tf_dir / "terraform.tfvars")
            self.r["tfvars"] = tfvars
            managed = ["cluster_name", "worker_count", "control_plane_count", "hostname_prefix", "node_cpus",
                       "node_memory_mb", "node_disk_gb", "image_url", "image_sha256", "node_os", "node_os_version",
                       "cpu_type"]
            duplicated = [k for k in managed if k in tfvars]
            if duplicated:
                self.error(f"terraform/providers/{self.platform}/terraform.tfvars définit {', '.join(duplicated)}, "
                           "qui sont pilotés par .env.",
                           "Terraform donnerait la priorité au fichier tfvars en silence : retirez ces lignes et "
                           "réglez-les dans .env (docs/configuration.md).")
            tf_network = tfvars.get("network_cidr") or inv.tf_variable_default(tf_dir / "variables.tf", "network_cidr") or ""
            if network and tf_network and network != tf_network:
                self.error(f"NODE_NETWORK_CIDR={network} diffère de network_cidr={tf_network} (terraform.tfvars).")
            network = network or tf_network
            ip_start = int(tfvars.get("ip_start") or inv.tf_variable_default(tf_dir / "variables.tf", "ip_start") or 100)
            offset_raw = tfvars.get("worker_ip_offset", "null")
            worker_offset = int(offset_raw) if offset_raw not in ("", "null") else cp
            if worker_offset < cp:
                self.error(f"worker_ip_offset={worker_offset} (terraform.tfvars) < CONTROL_PLANE_COUNT={cp} : "
                           "les adresses des control-planes et des workers se chevaucheraient.")
            self.r["node_gateway"] = tfvars.get("gateway", "")
            if network:
                try:
                    net = netutil.parse_cidr(network)
                    hosts = [net.network_address + ip_start + i for i in range(cp)] + \
                            [net.network_address + ip_start + worker_offset + j for j in range(workers)]
                    for h in hosts:
                        if h not in net or h in (net.network_address, net.broadcast_address):
                            self.error(f"network_cidr={network} est trop petit pour {cp} control-plane(s) et "
                                       f"{workers} worker(s) à partir de ip_start={ip_start}.")
                            break
                    self.plan.nodes = [{"name": f"{prefix}-cp-{i + 1}", "role": "control_plane", "ip": str(hosts[i])}
                                       for i in range(cp)] + \
                                      [{"name": f"{prefix}-worker-{j + 1}", "role": "worker", "ip": str(hosts[cp + j])}
                                       for j in range(workers)]
                except (netutil.NetError, ValueError) as exc:
                    self.error(f"network_cidr (terraform.tfvars) : {exc}")
            elif self.platform != "libvirt":
                self.info(f"Réseau des nœuds inconnu (terraform/providers/{self.platform}/terraform.tfvars absent) : "
                          "les contrôles de chevauchement d'adresses seront faits quand il existera.")
        elif self.platform == "vagrant":
            base = cfg.get("VAGRANT_NETWORK_PREFIX")
            start = cfg.int("VAGRANT_IP_START", 10)
            network = network or f"{base}.0/24"
            if start + cp + workers > 254:
                self.error("VAGRANT_IP_START + nombre de nœuds dépasse le réseau /24 de Vagrant.")
            self.plan.nodes = [{"name": f"{prefix}-cp-{i + 1}", "role": "control_plane", "ip": f"{base}.{start + i}"}
                               for i in range(cp)] + \
                              [{"name": f"{prefix}-worker-{j + 1}", "role": "worker", "ip": f"{base}.{start + cp + j}"}
                               for j in range(workers)]
        self.r["node_network_cidr"] = network

    # --- système d'exploitation ------------------------------------------------------------
    def _operating_system(self) -> None:
        cfg = self.cfg
        os_name, os_version = cfg.get("NODE_OS"), cfg.get("NODE_OS_VERSION")
        if self.platform not in KUBEADM_PLATFORMS:
            if cfg.explicit("NODE_OS") or cfg.explicit("NODE_OS_VERSION"):
                own = {"kind": "image kindest/node", "minikube": "ISO / image de minikube",
                       "eks": "Amazon Linux 2023 (AMI optimisée EKS)", "attach": "système du cluster existant"}
                self.info(f"NODE_OS/NODE_OS_VERSION sont ignorés en mode {self.platform} : "
                          f"le système des nœuds est géré par {own.get(self.platform, 'la plateforme')}.")
            self.r["node_os"] = {"name": "platform", "family": "platform"}
            return
        if os_name == "auto":
            if self.platform != "existing":
                self.error("NODE_OS=auto n'est possible qu'en mode existing (détection sur les machines).",
                           "Choisissez ubuntu, debian ou rocky.")
                return
            self.r["node_os"] = {"name": "auto", "version": "auto", "family": "auto"}
            self.info("NODE_OS=auto : la distribution de chaque machine sera détectée par Ansible et refusée "
                      "si elle n'est pas dans la matrice supportée.")
            return
        entry = self.catalog.os_entry(os_name, os_version)
        if entry is None:
            supported = ", ".join(sorted(self.catalog.versions["os"].get(os_name, {})))
            self.error(f"{os_name} {os_version} n'est pas dans la matrice supportée.",
                       f"Versions de {os_name} supportées : {supported} (config/versions.yaml).")
            return
        if entry["status"] == "experimental":
            self.warn(f"{os_name} {os_version} est EXPÉRIMENTAL dans ce framework (voir docs/compatibility.md).")
        self.r["node_os"] = {"name": os_name, "version": os_version, **entry}
        self.r["node_ssh_user"] = cfg.get("NODE_SSH_USER") or entry["ssh_user"]
        if self.platform == "existing":
            return
        level = entry.get("x86_64_level", "v1")
        cpu_type = cfg.get("NODE_CPU_TYPE")
        if level == "v3":
            if self.platform == "proxmox" and cpu_type not in CPU_LEVEL_V3:
                self.error(f"{os_name} {os_version} exige un CPU x86-64-v3 (AVX2), mais NODE_CPU_TYPE={cpu_type}.",
                           "Mettez NODE_CPU_TYPE=x86-64-v3 (ou host) SI le processeur de l'hyperviseur supporte "
                           "AVX2. Un Xeon X5690 (Westmere) ne le supporte pas : utilisez Rocky Linux 9.")
            else:
                self.warn(f"{os_name} {os_version} exige un processeur hôte x86-64-v3 (AVX2) : vérifiez votre matériel.")
        self._image(entry)

    def _image(self, entry: dict[str, Any]) -> None:
        cfg = self.cfg
        source = cfg.get("NODE_IMAGE_SOURCE", "catalog")
        url = cfg.get("NODE_IMAGE_URL") or cfg.get("VM_IMAGE_URL")
        sha = cfg.get("NODE_IMAGE_SHA256") or cfg.get("VM_IMAGE_SHA256")
        if source == "catalog" and url:
            source = "url"
            self.info("Une image personnalisée est définie (NODE_IMAGE_URL/VM_IMAGE_URL) : elle remplace l'image "
                      "du catalogue.")
        if self.platform == "vsphere":
            self.r["image"] = {"source": "template", "template": cfg.get("NODE_TEMPLATE_ID")}
            self.info("vSphere clone toujours un template (vsphere_template ou NODE_TEMPLATE_ID) : il doit "
                      "correspondre à NODE_OS/NODE_OS_VERSION (docs/deploy-vsphere.md).")
            return
        if self.platform == "vagrant":
            box = cfg.get("VAGRANT_BOX") or entry.get("vagrant_box", "")
            self.r["image"] = {"source": "vagrant-box", "box": box}
            return
        if source == "url":
            if not url or not sha:
                self.error("NODE_IMAGE_SOURCE=url exige NODE_IMAGE_URL ET NODE_IMAGE_SHA256.",
                           "Le SHA-256 est vérifié avant utilisation : jamais d'image non vérifiée.")
            self.warn("Image personnalisée : vérifiez qu'elle correspond bien à NODE_OS/NODE_OS_VERSION "
                      "(paquets et utilisateur SSH en dépendent).")
            self.r["image"] = {"source": "url", "url": url, "sha256": sha}
        elif source == "template":
            template = cfg.get("NODE_TEMPLATE_ID")
            if self.platform != "proxmox":
                self.error(f"NODE_IMAGE_SOURCE=template n'est pas disponible pour {self.platform}.")
            elif not template.isdigit():
                self.error("NODE_IMAGE_SOURCE=template (Proxmox) exige NODE_TEMPLATE_ID = ID numérique du template.")
            self.r["image"] = {"source": "template", "template": template}
        else:
            self.r["image"] = {"source": "catalog", "url": entry["image_url"], "sha256": entry["image_sha256"]}

    # --- CNI et kube-proxy -------------------------------------------------------------------
    def _cni(self) -> None:
        cfg = self.cfg
        cni = cfg.get("CNI", "auto")
        explicit = cfg.explicit("CNI")
        install = "kubeadm"
        if self.platform == "attach":
            if explicit and cni != "auto":
                self.warn(f"CNI={cni} est ignoré en mode attach : le CNI d'un cluster existant n'est jamais modifié "
                          "(un changement de CNI est une migration à part entière : docs/cni.md).")
            cni, install = "existing", "existing"
        elif self.platform == "eks":
            if cni not in ("auto",):
                self.error(f"CNI={cni} n'est pas supporté sur EKS : le réseau des Pods est fourni par AWS VPC CNI.",
                           "Laissez CNI=auto en mode eks.")
            cni, install = "aws-vpc-cni", "platform"
        elif self.platform == "kind":
            if cni in ("auto",):
                cni, install = "kindnet", "platform"
            elif cni == "flannel":
                if explicit:
                    self.warn("CNI=flannel ne s'applique qu'aux modes kubeadm : kind utilise son CNI natif (kindnet).")
                cni, install = "kindnet", "platform"
            elif cni == "none":
                self.warn("CNI=none sur kind : les nœuds resteront NotReady tant que vous n'installez pas un CNI.")
                install = "none"
            else:
                install = "helm-local"
                self.info(f"kind avec {cni} : le CNI natif est désactivé (disableDefaultCNI) et {cni} est installé "
                          "par Helm depuis votre poste.")
        elif self.platform == "minikube":
            if cni == "auto":
                cni, install = "minikube", "platform"
            elif cni == "none":
                self.error("CNI=none n'est pas proposé pour minikube.", "Laissez CNI=auto.")
            else:
                install = "minikube"
                self.info(f"minikube installe {cni} lui-même (minikube start --cni={cni}) : sa version est choisie "
                          "par minikube, CNI_VERSION est ignoré.")
        else:
            if cni == "auto":
                cni = "flannel"
            if cni == "none":
                install = "none"
                self.warn("CNI=none : aucun réseau de Pods installé, les nœuds resteront NotReady et les addons ne "
                          "seront pas installés (installation manuelle avancée, docs/cni.md).")
        self.r["cni"] = cni
        self.r["cni_install"] = install

        # Version
        version = ""
        if cni in ("flannel", "calico", "cilium") and install in ("kubeadm", "helm-local"):
            comp = self.catalog.component(cni)
            version = cfg.get("CNI_VERSION") or (cfg.get("FLANNEL_VERSION") if cni == "flannel" else "") or comp["version"]
            if cni == "flannel" and version not in comp.get("sha256", {}):
                self.error(f"Flannel {version} : aucune empreinte SHA-256 connue pour son manifeste.",
                           "Ajoutez-la dans config/versions.yaml (components.flannel.sha256) après vérification, "
                           "ou laissez CNI_VERSION vide.")
            if version.lstrip("v") != comp["version"].lstrip("v"):
                self.warn(f"{cni} {version} n'est pas la version verrouillée ({comp['version']}) : combinaison non "
                          "validée par ce framework.")
        self.r["cni_version"] = version

        # Mode réseau
        mode = cfg.get("CNI_MODE", "auto")
        if cni in CNI_MODES and install in ("kubeadm", "helm-local"):
            if mode == "auto":
                mode = CNI_DEFAULT_MODE[cni]
            elif mode not in CNI_MODES[cni]:
                self.error(f"CNI_MODE={mode} n'existe pas pour {cni}.",
                           f"Modes de {cni} : {', '.join(sorted(CNI_MODES[cni]))}")
            if mode in ("host-gw", "direct", "native"):
                self.warn(f"CNI_MODE={mode} : routage direct sans encapsulation, tous les nœuds doivent être sur le "
                          "même réseau L2 (ou des routes vers les réseaux de Pods doivent exister).")
        elif mode != "auto" and cfg.explicit("CNI_MODE"):
            self.info(f"CNI_MODE est ignoré avec le CNI {cni}.")
            mode = "auto"
        self.r["cni_mode"] = mode

        # kube-proxy
        kpm = cfg.get("KUBE_PROXY_MODE", "auto")
        if self.platform in ("eks", "attach", "minikube"):
            if kpm != "auto":
                self.warn(f"KUBE_PROXY_MODE est ignoré en mode {self.platform}.")
            kpm = "platform"
        else:
            if kpm == "auto":
                kpm = "cilium" if cni == "cilium" else "iptables"
            if kpm == "cilium" and cni != "cilium":
                self.error("KUBE_PROXY_MODE=cilium (remplacement de kube-proxy) exige CNI=cilium.")
            if kpm == "ipvs":
                self.warn("Le mode IPVS de kube-proxy est déprécié depuis Kubernetes 1.35 : préférez nftables.")
            if kpm == "nftables" and cni == "flannel":
                self.info("kube-proxy nftables avec Flannel : Flannel utilise iptables pour sa propre mascarade.")
        self.r["kube_proxy_mode"] = kpm
        self.r["kube_proxy_replacement"] = kpm == "cilium"

        # NetworkPolicy
        npm = cfg.get("NETWORK_POLICY_MODE", "auto")
        default_np = NETPOL_DEFAULT.get(cni, "none")
        if npm == "auto":
            npm = default_np
        elif npm == "kubernetes" and cni in ("flannel", "minikube", "aws-vpc-cni"):
            self.error(f"NETWORK_POLICY_MODE=kubernetes : le CNI {cni} n'applique pas les NetworkPolicy.",
                       "Les politiques seraient acceptées par l'API mais IGNORÉES : choisissez CNI=calico ou "
                       "CNI=cilium pour les appliquer.")
        elif npm == "calico" and cni != "calico":
            self.error("NETWORK_POLICY_MODE=calico exige CNI=calico.")
        elif npm == "cilium" and cni != "cilium":
            self.error("NETWORK_POLICY_MODE=cilium exige CNI=cilium.")
        self.r["network_policy_mode"] = npm
        if cni == "flannel":
            self.info("Flannel n'applique aucune NetworkPolicy : il ne fournit qu'un réseau de Pods (docs/cni.md).")

        # Hubble (ENABLE_HUBBLE=true, ou « hubble » dans ADDONS)
        adds, _ = self._addons_from_list()
        hubble = cfg.bool("ENABLE_HUBBLE")
        if "hubble" in adds:
            if cfg.explicit("ENABLE_HUBBLE") and not hubble:
                self.error("Contradiction : ENABLE_HUBBLE=false mais hubble est dans ADDONS.")
            hubble = True
        if hubble and cni != "cilium":
            self.error(f"ENABLE_HUBBLE=true exige CNI=cilium (CNI actuel : {cni}).",
                       "Hubble est la couche d'observabilité de Cilium : il n'existe pas pour Flannel ou Calico.")
        if cfg.bool("HUBBLE_UI") and not hubble:
            self.error("HUBBLE_UI=true exige ENABLE_HUBBLE=true.")
        self.r["hubble"] = {"enabled": hubble and cni == "cilium", "ui": cfg.bool("HUBBLE_UI") and hubble}

        # Noyau requis par Cilium
        if cni == "cilium" and self.platform in VM_PLATFORMS:
            kernel = self.r.get("node_os", {}).get("kernel")
            kmin = self.catalog.component("cilium").get("kernel_min", "5.10")
            if kernel and version_tuple(kernel) < version_tuple(kmin) and self.r["node_os"].get("family") != "redhat":
                self.error(f"Cilium exige un noyau >= {kmin} ; {self.r['node_os']['name']} "
                           f"{self.r['node_os']['version']} a un noyau {kernel}.")

    # --- réseaux : CIDR, plages, chevauchements ---------------------------------------------
    def _networks(self) -> None:
        cfg = self.cfg
        if self.platform in ("eks", "attach"):
            for key in ("POD_CIDR", "SERVICE_CIDR"):
                if cfg.explicit(key):
                    self.info(f"{key} est ignoré en mode {self.platform}.")
            pod = svc = None
        else:
            pod = netutil.parse_cidr(cfg.get("POD_CIDR"))
            svc = netutil.parse_cidr(cfg.get("SERVICE_CIDR"))
            self.r["pod_cidr"], self.r["service_cidr"] = str(pod), str(svc)
            if pod.overlaps(svc):
                self.error(f"POD_CIDR={pod} et SERVICE_CIDR={svc} se chevauchent.")
            if pod.prefixlen > 24:
                self.error(f"POD_CIDR={pod} est trop petit : chaque nœud reçoit un /24.")
            else:
                max_nodes = 2 ** (24 - pod.prefixlen)
                nodes = (self.r.get("control_plane_count") or 1) + (self.r.get("worker_count") or 0)
                if nodes > max_nodes:
                    self.error(f"POD_CIDR={pod} ne permet que {max_nodes} nœud(s) (un /24 par nœud), {nodes} prévus.")
            if svc.prefixlen < 12:
                self.error(f"SERVICE_CIDR={svc} est trop grand : Kubernetes limite le réseau des Services à un /12.")
            if svc.prefixlen > 24:
                self.warn(f"SERVICE_CIDR={svc} est petit : {svc.num_addresses - 2} Services au plus.")
        reserved = netutil.parse_cidr_list(cfg.get("RESERVED_CIDRS"))
        node_net_text = self.r.get("node_network_cidr") or ""
        node_net = None
        if node_net_text:
            try:
                node_net = netutil.parse_cidr(node_net_text)
            except netutil.NetError as exc:
                self.error(f"Réseau des nœuds : {exc}")
        for label, net in (("POD_CIDR", pod), ("SERVICE_CIDR", svc)):
            if net is None:
                continue
            for other in reserved:
                if net.overlaps(other):
                    self.error(f"{label}={net} chevauche le réseau réservé {other} (RESERVED_CIDRS).",
                               "Les Pods/Services masqueraient ce réseau : choisissez une plage libre "
                               "(ex : POD_CIDR=10.244.0.0/16, SERVICE_CIDR=10.250.0.0/16 si 10.96.0.0/12 est utilisé).")
            if node_net and net.overlaps(node_net):
                self.error(f"{label}={net} chevauche le réseau des nœuds {node_net}.")
        reserved_ips = netutil.parse_ranges(cfg.get("RESERVED_IPS"))
        node_ips = [netutil.parse_range(n["ip"]) for n in self.plan.nodes if _looks_like_ip(n["ip"])]
        for node, rng in zip([n for n in self.plan.nodes if _looks_like_ip(n["ip"])], node_ips):
            for res in reserved_ips:
                if rng.overlaps(res):
                    self.error(f"Le nœud {node['name']} ({node['ip']}) utilise une adresse réservée ({res.text}).",
                               "Changez ip_start (terraform.tfvars) ou corrigez RESERVED_IPS.")
            if node_net and ipaddress.ip_address(node["ip"]) not in node_net:
                self.error(f"Le nœud {node['name']} ({node['ip']}) est hors du réseau des nœuds {node_net}.")
        vip = self.r.get("control_plane_vip")
        if vip:
            vip_range = netutil.parse_range(vip)
            if node_net and vip_range.first not in node_net:
                self.error(f"CONTROL_PLANE_VIP={vip} est hors du réseau des nœuds {node_net} (ARP impossible).")
            for node, rng in zip([n for n in self.plan.nodes if _looks_like_ip(n["ip"])], node_ips):
                if rng.overlaps(vip_range):
                    self.error(f"CONTROL_PLANE_VIP={vip} est l'adresse du nœud {node['name']}.")
            for res in reserved_ips:
                if vip_range.overlaps(res):
                    self.error(f"CONTROL_PLANE_VIP={vip} est dans RESERVED_IPS ({res.text}).")
        self.r["_node_ranges"] = node_ips
        self.r["_reserved_ips"] = reserved_ips
        self.r["_node_net"] = node_net

    # --- sélecteurs : Gateway, LoadBalancer ------------------------------------------------
    def _profile(self) -> dict[str, Any]:
        name = self.cfg.get("ADDON_PROFILE", "minimal")
        return self.catalog.profiles[name]

    def _addons_from_list(self) -> tuple[list[str], list[str]]:
        adds, removes = [], []
        for item in self.cfg.list("ADDONS"):
            # « nom » ou « +nom » : ajouté au profil ; « -nom » : retiré du profil.
            if item.startswith("-"):
                removes.append(item[1:])
            else:
                adds.append(item[1:] if item.startswith("+") else item)
        return adds, removes

    def _selector_from_addons(self, selector: str, adds: list[str]) -> Optional[str]:
        """Valeur d'un sélecteur impliquée par ADDONS (ex : ADDONS=metallb -> LOADBALANCER_PROVIDER=metallb)."""
        implied = []
        for addon_id in adds:
            addon = self.catalog.addons.get(addon_id)
            if addon and selector in addon.selected_by:
                implied.append((addon_id, addon.selected_by[selector][0]))
        values = sorted({v for _, v in implied})
        if len(values) > 1:
            self.error(f"ADDONS contient plusieurs choix pour {selector} : "
                       f"{', '.join(a for a, _ in implied)}.", "Un seul est possible à la fois.")
        return values[0] if values else None

    def _selectors(self) -> None:
        cfg = self.cfg
        adds, _ = self._addons_from_list()
        defaults = self._profile().get("defaults", {})
        cni, kpr = self.r["cni"], self.r["kube_proxy_replacement"]

        # Gateway
        gc = cfg.get("GATEWAY_CONTROLLER", "auto")
        implied = self._selector_from_addons("GATEWAY_CONTROLLER", adds)
        if implied and gc not in ("auto", implied):
            self.error(f"Contradiction : GATEWAY_CONTROLLER={gc} mais ADDONS sélectionne {GATEWAY_ADDON.get(implied, implied)}.")
        if gc == "auto":
            gc = implied or defaults.get("GATEWAY_CONTROLLER", "none")
            if gc == "auto-cilium-or-traefik":
                gc = "cilium" if (cni == "cilium" and kpr) else "traefik"
            if gc != "none":
                self.info(f"GATEWAY_CONTROLLER=auto → {gc} (profil {cfg.get('ADDON_PROFILE')}).")
        if gc == "cilium":
            if cni != "cilium" and self.platform != "attach":
                self.error("GATEWAY_CONTROLLER=cilium exige CNI=cilium.",
                           "Choisissez traefik ou envoy-gateway avec ce CNI, ou passez à CNI=cilium.")
            elif not kpr and self.platform != "attach":
                self.error("La Gateway API de Cilium exige le remplacement de kube-proxy (KUBE_PROXY_MODE=cilium).")
            if self.platform == "attach":
                self.error("GATEWAY_CONTROLLER=cilium n'est pas disponible en mode attach : il modifie la "
                           "configuration du CNI, ce que le mode attach ne fait jamais.")
        self.r["gateway_controller"] = gc
        if gc != "none":
            controller = {"traefik": "traefik", "envoy-gateway": "envoy-gateway", "cilium": "cilium"}[gc]
            required = self.catalog.component(controller).get("gateway_api", "")
            version = cfg.get("GATEWAY_API_VERSION") or required
            known = self.catalog.component("gateway-api")["sha256"]
            if version not in known:
                self.error(f"GATEWAY_API_VERSION={version} : manifeste sans SHA-256 connu.",
                           f"Versions verrouillées : {', '.join(sorted(known))}")
            if required and version != required:
                self.warn(f"Gateway API {version} au lieu de {required} (version déclarée par {gc}) : non validé.")
            channel = cfg.get("GATEWAY_API_CHANNEL", "standard")
            self.r["gateway_api"] = {"version": version, "channel": channel,
                                     "install_with_cni": gc == "cilium"}
        else:
            self.r["gateway_api"] = {}
            if cfg.explicit("GATEWAY_API_VERSION"):
                self.info("GATEWAY_API_VERSION est ignoré sans contrôleur Gateway (GATEWAY_CONTROLLER=none).")

        # LoadBalancer
        lb = cfg.get("LOADBALANCER_PROVIDER", "auto")
        implied = self._selector_from_addons("LOADBALANCER_PROVIDER", adds)
        if implied and lb not in ("auto", implied):
            self.error(f"Contradiction : LOADBALANCER_PROVIDER={lb} mais ADDONS contient {LB_ADDON.get(implied, implied)}.")
        pool_text = cfg.get("LOADBALANCER_IP_POOL")
        if lb == "auto":
            lb = implied or defaults.get("LOADBALANCER_PROVIDER", "none")
            if lb == "auto-if-pool":
                if pool_text and self.platform in KUBEADM_PLATFORMS:
                    lb = "cilium-l2" if (cni == "cilium" and kpr) else "metallb"
                else:
                    lb = "none"
                    if self.platform in KUBEADM_PLATFORMS:
                        self.info("Aucun LoadBalancer : définissez LOADBALANCER_IP_POOL (plage libre de votre "
                                  "réseau) pour activer MetalLB ou Cilium L2.")
            if lb != "none":
                self.info(f"LOADBALANCER_PROVIDER=auto → {lb}.")
        if lb != "none":
            if self.platform == "eks":
                self.error(f"LOADBALANCER_PROVIDER={lb} n'a pas de sens sur EKS : AWS fournit les load balancers.",
                           "Laissez LOADBALANCER_PROVIDER=none (ou auto) en mode eks.")
            if self.platform == "minikube":
                self.warn("LoadBalancer sur minikube : préférez « minikube tunnel » ; MetalLB y est expérimental.")
            if lb.startswith("cilium"):
                if self.platform == "attach":
                    self.error(f"LOADBALANCER_PROVIDER={lb} modifie la configuration de Cilium : impossible en mode attach.")
                elif cni != "cilium":
                    self.error(f"LOADBALANCER_PROVIDER={lb} exige CNI=cilium.",
                               "Avec Flannel ou Calico, utilisez LOADBALANCER_PROVIDER=metallb.")
                elif not kpr:
                    self.error(f"LOADBALANCER_PROVIDER={lb} exige KUBE_PROXY_MODE=cilium (annonces L2/BGP de Cilium).")
            if lb == "cilium-bgp" or (lb == "metallb" and cfg.get("LOADBALANCER_MODE") == "bgp"):
                missing = [k for k in ("BGP_LOCAL_ASN", "BGP_PEER_ADDRESS", "BGP_PEER_ASN") if not cfg.get(k)]
                if missing:
                    self.error(f"Le mode BGP exige {', '.join(missing)}.",
                               "Le routeur pair (ex : Stormshield) n'est JAMAIS supposé configuré : activez BGP "
                               "seulement après avoir créé et validé la session BGP de son côté.")
            if not pool_text:
                self.error(f"LOADBALANCER_PROVIDER={lb} exige LOADBALANCER_IP_POOL (ex : 10.20.0.200-10.20.0.210).",
                           "Choisissez une plage LIBRE de votre réseau : hors DHCP, hors IP fixes.")
            else:
                self._check_pool(lb, netutil.parse_ranges(pool_text))
        elif pool_text and cfg.explicit("LOADBALANCER_IP_POOL"):
            self.info("LOADBALANCER_IP_POOL est défini mais aucun LoadBalancer n'est installé (LOADBALANCER_PROVIDER=none).")
        pool_ips: list[str] = []
        if lb != "none" and pool_text:
            try:
                ranges = netutil.parse_ranges(pool_text)
                if sum(r.size for r in ranges) <= 4096:
                    pool_ips = [str(ipaddress.ip_address(n)) for r in ranges for n in range(int(r.first), int(r.last) + 1)]
            except netutil.NetError:
                pass
        self.r["loadbalancer"] = {"provider": lb, "mode": cfg.get("LOADBALANCER_MODE") if lb == "metallb" else
                                  ("bgp" if lb == "cilium-bgp" else ("l2" if lb == "cilium-l2" else "")),
                                  "pool": netutil.split_list(pool_text) if lb != "none" else [],
                                  "pool_ips": pool_ips,
                                  "interfaces": cfg.get("LOADBALANCER_INTERFACES")}

        # Gateway : type de Service et TLS
        svc_type = cfg.get("GATEWAY_SERVICE_TYPE", "auto")
        if svc_type == "auto":
            svc_type = "LoadBalancer" if (lb != "none" or self.platform == "eks") else "NodePort"
        self.r["gateway_service_type"] = svc_type
        if gc != "none" and svc_type == "LoadBalancer" and lb == "none" and self.platform not in ("eks", "attach"):
            self.warn("GATEWAY_SERVICE_TYPE=LoadBalancer sans LoadBalancer installé : l'adresse de la Gateway "
                      "restera <pending>.")
        if gc == "cilium" and svc_type == "NodePort":
            self.info("Gateway Cilium sans LoadBalancer : le Service de la Gateway restera en attente d'IP ; "
                      "testez-la depuis le cluster ou installez cilium-l2 (LOADBALANCER_IP_POOL).")

    def _check_pool(self, lb: str, pool: list[netutil.IPRange]) -> None:
        total = sum(r.size for r in pool)
        self.r["loadbalancer_pool_size"] = total
        node_net = self.r.get("_node_net")
        l2 = lb in ("metallb", "cilium-l2") and (lb != "metallb" or self.cfg.get("LOADBALANCER_MODE") == "l2")
        for rng in pool:
            if l2 and node_net and not rng.within(node_net):
                self.error(f"LOADBALANCER_IP_POOL : {rng.text} est hors du réseau des nœuds {node_net}.",
                           "En L2 (ARP), les IP annoncées doivent appartenir au réseau des nœuds.")
            for res in self.r.get("_reserved_ips", []):
                if rng.overlaps(res):
                    self.error(f"LOADBALANCER_IP_POOL : {rng.text} chevauche une adresse réservée ({res.text}).",
                               "Excluez la plage DHCP et les IP fixes (RESERVED_IPS).")
            for node, nrng in zip([n for n in self.plan.nodes if _looks_like_ip(n["ip"])], self.r.get("_node_ranges", [])):
                if rng.overlaps(nrng):
                    self.error(f"LOADBALANCER_IP_POOL : {rng.text} contient l'adresse du nœud {node['name']} ({node['ip']}).")
            vip = self.r.get("control_plane_vip")
            if vip and rng.contains_ip(ipaddress.ip_address(vip)):
                self.error(f"LOADBALANCER_IP_POOL : {rng.text} contient la VIP de l'API ({vip}).")
            for other in netutil.parse_cidr_list(self.cfg.get("RESERVED_CIDRS")) if not l2 else []:
                if rng.overlaps(netutil.network_as_range(other)):
                    self.error(f"LOADBALANCER_IP_POOL : {rng.text} chevauche le réseau réservé {other}.")
        for i, a in enumerate(pool):
            for b in pool[i + 1:]:
                if a.overlaps(b):
                    self.error(f"LOADBALANCER_IP_POOL : les plages {a.text} et {b.text} se chevauchent.")
        if self.r.get("_node_net") is None and self.platform in KUBEADM_PLATFORMS:
            self.warn("Réseau des nœuds inconnu : impossible de vérifier que LOADBALANCER_IP_POOL lui appartient "
                      "(définissez NODE_NETWORK_CIDR).")
        self.info(f"Pool LoadBalancer : {total} adresse(s) — à valider dans votre IPAM avant le déploiement.")

    # --- stockage ---------------------------------------------------------------------------
    def _storage(self) -> None:
        cfg = self.cfg
        adds, removes = self._addons_from_list()
        backends = list(dict.fromkeys(cfg.list("STORAGE_BACKENDS")))
        for alias, backend in (("NFS_CSI_ENABLED", "nfs-csi"), ("LONGHORN_ENABLED", "longhorn")):
            if cfg.get(alias):
                if cfg.bool(alias) and backend not in backends:
                    backends.append(backend)
                if not cfg.bool(alias) and backend in backends:
                    self.error(f"Contradiction : {alias}=false mais {backend} est dans STORAGE_BACKENDS.")
        for addon_id in adds:
            if addon_id in ("nfs-csi", "longhorn") and addon_id not in backends:
                backends.append(addon_id)
        for addon_id in removes:
            if addon_id in backends:
                self.error(f"Contradiction : -{addon_id} dans ADDONS mais {addon_id} est sélectionné comme backend de stockage.")
        self.r["storage_backends"] = backends
        if "nfs-csi" in backends:
            for key in ("NFS_SERVER", "NFS_SHARE"):
                if not cfg.get(key):
                    self.error(f"NFS CSI : {key} n'est pas défini.",
                               "Indiquez le serveur et l'export NFS (l'export doit exister et autoriser les nœuds).")
            if cfg.get("NFS_RECLAIM_POLICY") == "Delete":
                self.warn("NFS_RECLAIM_POLICY=Delete : supprimer un PVC SUPPRIME ses données sur le NAS.")
            self.info("NFS CSI : vérifiez que les flux NFS (TCP 2049, NFSv4) sont autorisés entre les nœuds et le "
                      f"serveur {cfg.get('NFS_SERVER') or '?'} (pare-feu inter-VLAN) : jamais modifié automatiquement.")
        if "longhorn" in backends:
            self._longhorn()
        # StorageClass par défaut
        default = cfg.get("DEFAULT_STORAGE_CLASS", "auto")
        legacy = cfg.get("NFS_DEFAULT_STORAGE_CLASS")
        if legacy and to_bool(legacy):
            if default not in ("auto", "nfs-csi", cfg.get("NFS_STORAGE_CLASS")):
                self.error(f"Contradiction : NFS_DEFAULT_STORAGE_CLASS=true et DEFAULT_STORAGE_CLASS={default}.")
            default = "nfs-csi"
        names = {"nfs-csi": cfg.get("NFS_STORAGE_CLASS"), "longhorn": cfg.get("LONGHORN_STORAGE_CLASS")}
        if default == "auto":
            if len(backends) == 1:
                default = backends[0]
            elif len(backends) > 1:
                self.error("Deux backends de stockage sont choisis : précisez DEFAULT_STORAGE_CLASS (nfs-csi ou longhorn).",
                           "Une seule StorageClass peut être celle par défaut.")
                default = "none"
            else:
                default = "platform"
        if default in ("nfs-csi", "longhorn") and default not in backends:
            self.error(f"DEFAULT_STORAGE_CLASS={default} mais {default} n'est pas dans STORAGE_BACKENDS.")
        if default in names.values():
            default = next(k for k, v in names.items() if v == default)
        self.r["default_storage_class"] = {"backend": default, "name": names.get(default, "")}
        if default in ("nfs-csi", "longhorn") and self.platform in ("kind", "minikube", "eks"):
            self.info(f"La StorageClass « standard » de {self.platform} ne sera plus celle par défaut "
                      f"({names[default]} le devient).")

    def _longhorn(self) -> None:
        cfg = self.cfg
        if self.platform in ("kind", "minikube"):
            self.error(f"Longhorn n'est pas supporté en mode {self.platform} (open-iscsi et disques réels requis).")
            return
        if self.platform == "eks":
            self.error("Longhorn n'est pas proposé sur EKS par ce framework : utilisez les volumes EBS (CSI AWS).",
                       "docs/storage.md (EKS)")
            return
        comp = self.catalog.component("longhorn")
        version = cfg.get("LONGHORN_VERSION")
        if version == "auto-compatible":
            version = comp["version"]
            self.info(f"LONGHORN_VERSION=auto-compatible → {version} (verrouillée dans config/versions.yaml).")
        elif version.lstrip("v") != comp["version"].lstrip("v"):
            self.warn(f"Longhorn {version} n'est pas la version verrouillée ({comp['version']}) : non validé.")
        self.r["longhorn_version"] = version
        workers = self.r.get("worker_count")
        replicas = cfg.int("LONGHORN_REPLICA_COUNT", 3)
        if workers is not None:
            storage_nodes = workers if workers > 0 else (self.r.get("control_plane_count") or 1)
            if replicas > storage_nodes:
                self.error(f"LONGHORN_REPLICA_COUNT={replicas} > {storage_nodes} nœud(s) de stockage : "
                           "chaque réplica doit être sur un nœud distinct.",
                           f"Réduisez LONGHORN_REPLICA_COUNT à {storage_nodes} au plus, ou ajoutez des workers.")
        if replicas == 1:
            self.warn("LONGHORN_REPLICA_COUNT=1 : aucune redondance (la perte d'un nœud perd ses volumes).")
        if self.platform in VM_PLATFORMS:
            self.warn("Longhorn : des réplicas sur des VMs d'UN SEUL hyperviseur ne protègent ni d'une panne de cet "
                      "hyperviseur, ni d'une panne de son stockage.")
        os_info = self.r.get("node_os", {})
        if os_info.get("name") not in ("platform", "auto", None):
            key = f"{os_info['name']}-{os_info.get('version', '')}"
            if key not in comp.get("os_verified", []) and f"{os_info['name']}-{str(os_info.get('version', '')).split('.')[0]}" not in comp.get("os_verified", []):
                self.warn(f"Longhorn {comp['version']} n'a pas été vérifié par son projet sur {os_info['name']} "
                          f"{os_info.get('version')} (vérifiés : {', '.join(comp.get('os_verified', []))}).")
        dedicated = cfg.bool("LONGHORN_DEDICATED_DISK")
        if dedicated:
            if self.platform == "existing" and not cfg.get("LONGHORN_DISK_DEVICE"):
                self.error("Mode existing : LONGHORN_DEDICATED_DISK=true exige LONGHORN_DISK_DEVICE "
                           "(ex : /dev/disk/by-id/...) : le disque n'est jamais deviné.")
            if self.platform == "vsphere":
                self.info("vSphere : le disque dédié est le 2e disque SCSI (unité 1) de chaque worker.")
        elif self.platform in VM_PLATFORMS:
            self.info("Longhorn utilisera le disque système (LONGHORN_DEDICATED_DISK=false) : un disque dédié est "
                      "recommandé (isolation, taille, performances).")
        if self.platform == "attach":
            self.warn("Longhorn en mode attach : les prérequis des nœuds (open-iscsi, NFSv4, dm_crypt) ne peuvent pas "
                      "être installés par le framework ; ils sont vérifiés par le test de l'addon.")
        if cfg.bool("LONGHORN_BACKUP_ENABLED") and not cfg.get("LONGHORN_BACKUP_TARGET"):
            self.error("LONGHORN_BACKUP_ENABLED=true exige LONGHORN_BACKUP_TARGET (nfs://... ou s3://...).")
        target = cfg.get("LONGHORN_BACKUP_TARGET")
        if target.startswith("s3://") and not (cfg.get("LONGHORN_BACKUP_S3_ACCESS_KEY") and cfg.get("LONGHORN_BACKUP_S3_SECRET_KEY")):
            self.error("Cible Longhorn S3 : LONGHORN_BACKUP_S3_ACCESS_KEY et LONGHORN_BACKUP_S3_SECRET_KEY doivent "
                       "être définies dans .env.")

    # --- addons -----------------------------------------------------------------------------
    def _add(self, addon_id: str, reason: str) -> None:
        self.selected.setdefault(addon_id, [])
        if reason not in self.selected[addon_id]:
            self.selected[addon_id].append(reason)

    def _addons(self) -> None:
        cfg, catalog = self.cfg, self.catalog
        profile_name = cfg.get("ADDON_PROFILE", "minimal")
        profile = self._profile()
        adds, removes = self._addons_from_list()
        for unknown in [a for a in adds + removes if a not in catalog.addons]:
            close = difflib.get_close_matches(unknown, list(catalog.addons), n=1)
            self.error(f"ADDONS : addon inconnu « {unknown} »" + (f" (vouliez-vous {close[0]} ?)" if close else "."),
                       "Catalogue : make addons-catalog")
        both = set(adds) & set(removes)
        if both:
            self.error(f"ADDONS contradictoire : {', '.join(sorted(both))} à la fois ajouté et retiré.")
        if profile_name == "custom" and removes:
            self.error("ADDON_PROFILE=custom : ADDONS est la liste complète, les retraits (-nom) n'ont pas de sens.")
        if profile_name != "custom":
            for addon_id in profile.get("addons", []):
                if addon_id not in removes:
                    self._add(addon_id, f"profil {profile_name}")
        self.removed = {r for r in removes if r in catalog.addons}
        for addon_id in adds:
            if addon_id in catalog.addons:
                self._add(addon_id, "ADDONS")
        if self.r.get("cni_install") == "none":
            if self.selected:
                self.error("CNI=none : aucun addon ne peut être installé automatiquement sans réseau de Pods.")
            self.selected = {}
            return
        # Sélecteurs -> addons
        gc = self.r["gateway_controller"]
        if gc != "none":
            self._add(GATEWAY_ADDON[gc], f"GATEWAY_CONTROLLER={gc}")
            self._add("gateway", "Gateway partagée du contrôleur choisi")
        lb = self.r["loadbalancer"]["provider"]
        if lb != "none":
            self._add(LB_ADDON[lb], f"LOADBALANCER_PROVIDER={lb}")
        for backend in self.r["storage_backends"]:
            self._add(backend, "STORAGE_BACKENDS")
        if self.r["hubble"]["enabled"]:
            self._add("hubble", "ENABLE_HUBBLE=true")
        tls = cfg.get("GATEWAY_TLS", "auto")
        if gc != "none" and tls == "true":
            self._add("cert-manager", "GATEWAY_TLS=true")
        # Retraits incompatibles avec un sélecteur explicite
        for addon_id in self.removed:
            if addon_id in self.selected and any(not r.startswith("profil") for r in self.selected[addon_id]):
                self.error(f"ADDONS retire {addon_id} mais il est requis par : {', '.join(self.selected[addon_id])}.")
        # Dépendances (fermeture transitive)
        queue = list(self.selected)
        while queue:
            addon_id = queue.pop(0)
            addon = catalog.addons.get(addon_id)
            if addon is None:
                continue
            for dep in addon.depends_on:
                if dep == "gateway-controller":
                    if gc == "none":
                        self.error(f"{addon_id} exige un contrôleur Gateway API (GATEWAY_CONTROLLER).")
                    continue
                if dep in self.removed:
                    self.error(f"Contradiction : -{dep} dans ADDONS, mais {addon_id} en dépend.")
                    continue
                if dep not in self.selected:
                    queue.append(dep)
                self._add(dep, f"dépendance de {addon_id}")
        # Résolution finale de GATEWAY_TLS
        cert = "cert-manager" in self.selected and cfg.get("CERT_MANAGER_ISSUER") != "none"
        self.r["gateway_tls"] = (tls == "true") or (tls == "auto" and cert)
        if gc != "none" and tls == "auto" and not cert:
            self.info("Gateway sans écouteur HTTPS (cert-manager absent) : ajoutez cert-manager pour TLS.")
        self._check_addons()
        self._order_addons()

    def _check_addons(self) -> None:
        cfg = self.cfg
        for addon_id in list(self.selected):
            addon = self.catalog.addons[addon_id]
            support = addon.support_for(self.platform)
            if support.status == "unsupported":
                self.error(f"L'addon {addon_id} n'est pas supporté en mode {self.platform}."
                           + (f" {support.note}" if support.note else ""))
            elif support.status == "experimental":
                self.warn(f"L'addon {addon_id} est expérimental en mode {self.platform}."
                          + (f" {support.note}" if support.note else ""))
            elif support.status == "configured" and support.note:
                self.info(f"{addon_id} ({self.platform}) : {support.note}")
            req = addon.requires
            if req.get("cni") and self.r["cni"] not in req["cni"] and self.platform != "attach":
                self.error(f"L'addon {addon_id} exige le CNI {' ou '.join(req['cni'])} (CNI actuel : {self.r['cni']}).")
            if req.get("kube_proxy_replacement") and not self.r["kube_proxy_replacement"] and self.platform != "attach":
                self.error(f"L'addon {addon_id} exige KUBE_PROXY_MODE=cilium.")
            for key in req.get("settings", []):
                if not cfg.get(key):
                    self.error(f"L'addon {addon_id} exige {key} (non défini).",
                               f"Voir la fiche de l'addon : docs/addons.md#{addon_id}")
            for key in req.get("secrets", []):
                if not cfg.get(key):
                    self.error(f"L'addon {addon_id} exige le secret {key} dans .env (jamais dans un fichier versionné).")
            any_addon = req.get("any_addon", [])
            if any_addon and not set(any_addon) & set(self.selected):
                self.error(f"L'addon {addon_id} n'est utile qu'avec {' ou '.join(any_addon)} (aucun n'est sélectionné).")
            workers = self.r.get("worker_count")
            if workers is not None and workers < req.get("min_workers", 0):
                self.error(f"L'addon {addon_id} exige au moins {req['min_workers']} worker(s).")
            for conflict in addon.conflicts_with:
                if conflict in self.selected:
                    self.error(f"Les addons {addon_id} et {conflict} sont incompatibles (un seul à la fois).")
            if req.get("storage_class") and self.r["default_storage_class"]["backend"] in ("none",) and \
                    not self.r["storage_backends"] and self.platform in KUBEADM_PLATFORMS:
                self.warn(f"L'addon {addon_id} utilise des volumes persistants mais aucun stockage n'est installé.")
            kernel_min = req.get("kernel_min")
            os_info = self.r.get("node_os", {})
            if kernel_min and os_info.get("kernel") and version_tuple(os_info["kernel"]) < version_tuple(kernel_min) \
                    and os_info.get("family") != "redhat":
                self.error(f"L'addon {addon_id} exige un noyau >= {kernel_min} ({os_info['name']} : {os_info['kernel']}).")
        # Paramètres propres à certains addons
        if "external-dns" in self.selected:
            provider = cfg.get("EXTERNAL_DNS_PROVIDER")
            needs = {"rfc2136": ["RFC2136_NAMESERVER", "RFC2136_TSIG_KEY_NAME", "RFC2136_TSIG_SECRET"],
                     "cloudflare": ["CLOUDFLARE_API_TOKEN"], "pihole": ["PIHOLE_SERVER", "PIHOLE_PASSWORD"]}
            for key in needs.get(provider, []):
                if not cfg.get(key):
                    self.error(f"ExternalDNS ({provider}) exige {key}.")
        if "cert-manager" in self.selected:
            issuer = cfg.get("CERT_MANAGER_ISSUER")
            if issuer.startswith("acme") and not cfg.get("ACME_EMAIL"):
                self.error("cert-manager ACME : ACME_EMAIL est obligatoire.")
            if issuer == "acme-http01":
                self.warn("ACME HTTP-01 exige que <app>.GATEWAY_DOMAIN soit joignable DEPUIS INTERNET sur le port 80 ; "
                          "pour un lab interne, préférez selfsigned-ca ou DNS-01.")
            if issuer == "acme-dns01":
                provider = cfg.get("ACME_DNS01_PROVIDER")
                needs = {"cloudflare": ["CLOUDFLARE_API_TOKEN"], "rfc2136": ["RFC2136_NAMESERVER", "RFC2136_TSIG_KEY_NAME", "RFC2136_TSIG_SECRET"],
                         "route53": []}
                if not provider:
                    self.error("CERT_MANAGER_ISSUER=acme-dns01 exige ACME_DNS01_PROVIDER.")
                for key in needs.get(provider, []):
                    if not cfg.get(key):
                        self.error(f"DNS-01 ({provider}) exige {key}.")
        if "argo-cd" in self.selected and cfg.get("ARGOCD_REPO_URL") and cfg.bool("ARGOCD_AUTO_SYNC"):
            self.info("Argo CD : synchronisation automatique de l'application d'exemple activée.")
        for flag, addon_id in (("ARGOCD_EXPOSE", "argo-cd"), ("GRAFANA_EXPOSE", "monitoring"),
                               ("LONGHORN_UI_EXPOSE", "longhorn")):
            if cfg.bool(flag) and addon_id in self.selected and self.r["gateway_controller"] == "none":
                self.error(f"{flag}=true exige un contrôleur Gateway API (GATEWAY_CONTROLLER).")

    def _order_addons(self) -> None:
        """Tri topologique : dépendances d'abord, puis par phase (5 réseau → 8 plateforme)."""
        catalog, selected = self.catalog, self.selected
        edges: dict[str, set[str]] = {a: set() for a in selected}
        for addon_id in selected:
            addon = catalog.addons[addon_id]
            for dep in addon.depends_on + addon.optional_deps:
                if dep in selected:
                    edges[addon_id].add(dep)
            if "gateway-controller" in addon.depends_on:
                for ctrl in GATEWAY_ADDON.values():
                    if ctrl in selected:
                        edges[addon_id].add(ctrl)
        indegree = {a: len(d) for a, d in edges.items()}
        heap = [(catalog.addons[a].phase, a) for a, n in indegree.items() if n == 0]
        heapq.heapify(heap)
        order = []
        while heap:
            _, addon_id = heapq.heappop(heap)
            order.append(addon_id)
            for other, deps in edges.items():
                if addon_id in deps:
                    deps.discard(addon_id)
                    indegree[other] -= 1
                    if indegree[other] == 0:
                        heapq.heappush(heap, (catalog.addons[other].phase, other))
        if len(order) != len(selected):
            cycle = sorted(set(selected) - set(order))
            self.error(f"Dépendances circulaires entre addons : {', '.join(cycle)} (erreur du catalogue).")
            order += cycle
        for addon_id in order:
            addon = catalog.addons[addon_id]
            support = addon.support_for(self.platform)
            comps = []
            for name in addon.components:
                comp = catalog.component(name)
                version = comp.get("version", "")
                if name == "longhorn":
                    version = self.r.get("longhorn_version", version)
                comps.append({"name": name, "version": version, "chart": comp.get("chart", ""),
                              "repo": comp.get("repo", ""), "type": comp["type"]})
            self.plan.addons.append(AddonPlan(id=addon_id, phase=addon.phase, reasons=selected[addon_id],
                                              support=support.status, support_note=support.note,
                                              components=comps, addon=addon))

    # --- sauvegardes ----------------------------------------------------------------------------
    def _backup(self) -> None:
        cfg = self.cfg
        enabled = cfg.bool("BACKUP_ENABLED")
        provider = cfg.get("BACKUP_PROVIDER")
        etcd = enabled and provider in ("etcd-snapshot", "both")
        if etcd and not self.kubeadm:
            self.error(f"BACKUP_PROVIDER={provider} : les instantanés etcd ne concernent que les clusters kubeadm "
                       f"(mode {self.platform} : etcd géré par la plateforme).",
                       "Utilisez BACKUP_PROVIDER=velero.")
        velero_wanted = enabled and provider in ("velero", "both")
        if velero_wanted and "velero" not in self.selected:
            self.error("BACKUP_PROVIDER inclut velero : ajoutez velero à ADDONS (stockage S3 requis).")
        try:
            on_calendar = cron_to_oncalendar(cfg.get("BACKUP_SCHEDULE"))
        except (ValueError, IndexError):
            self.error(f"BACKUP_SCHEDULE={cfg.get('BACKUP_SCHEDULE')} : expression cron non reconnue (ex : 0 3 * * *).")
            on_calendar = ""
        self.r["backup"] = {"enabled": enabled, "etcd_snapshots": etcd and self.kubeadm, "velero": "velero" in self.selected,
                            "schedule": cfg.get("BACKUP_SCHEDULE"), "on_calendar": on_calendar,
                            "retention_days": cfg.int("BACKUP_RETENTION_DAYS", 7)}

    # --- compatibilité des versions ----------------------------------------------------------
    def _compatibility(self) -> None:
        minor = self.r.get("kubernetes_minor")
        if not minor:
            return
        strict = self.cfg.get("COMPATIBILITY_POLICY") == "strict"
        components: list[tuple[str, str]] = []
        if self.r.get("cni") in ("calico", "cilium") and self.r.get("cni_install") in ("kubeadm", "helm-local"):
            components.append((self.r["cni"], f"CNI {self.r['cni']}"))
        for plan in self.plan.addons:
            for comp in plan.components:
                components.append((comp["name"], f"addon {plan.id}"))
        seen = set()
        for name, label in components:
            if (name, label) in seen:
                continue
            seen.add((name, label))
            comp = self.catalog.component(name)
            kube_min = comp.get("kube_min")
            if kube_min and version_tuple(minor) < version_tuple(kube_min):
                self.error(f"{label} ({name} {comp.get('version')}) exige Kubernetes >= {kube_min} (cluster : {minor}).")
            tested = comp.get("kube_tested")
            if tested and minor not in tested:
                message = (f"{label} : {name} {comp.get('version')} n'est pas déclaré testé par son projet avec "
                           f"Kubernetes {minor} (testé : {', '.join(tested)}).")
                hint = "Choisissez une version testée (KUBERNETES_VERSION) ou acceptez le risque (COMPATIBILITY_POLICY=warn)."
                if strict:
                    self.error(message, hint)
                else:
                    self.warn(message, hint)

    # --- capacité --------------------------------------------------------------------------------
    def _capacity(self) -> None:
        if self.platform not in VM_PLATFORMS:
            return
        mem = self.cfg.int("NODE_MEMORY_MB", 2048)
        workers = self.r.get("worker_count") or 0
        cps = self.r.get("control_plane_count") or 1
        schedulable = workers if workers else cps
        # ~1 Go par nœud pour le système, kubelet, containerd et le CNI.
        available = schedulable * max(mem - 1024, 0)
        needed = sum(a.addon.resources.get("memory_mb", 0) for a in self.plan.addons)
        self.r["capacity"] = {"available_mb": available, "addons_requests_mb": needed}
        if needed and available and needed > 0.8 * available:
            self.warn(f"Les addons demandent ~{needed} Mo de mémoire pour ~{available} Mo disponibles sur les nœuds "
                      "applicatifs : risque de Pods en attente.", "Augmentez NODE_MEMORY_MB ou WORKER_COUNT.")


DOW_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def cron_to_oncalendar(cron: str) -> str:
    """Convertit une expression cron (5 champs) en OnCalendar systemd.

    0 3 * * *     -> *-*-* 3:0:00
    */15 * * * 1-5 -> Mon..Fri *-*-* *:0/15:00
    """
    fields = cron.split()
    if len(fields) != 5:
        raise ValueError(f"expression cron invalide : {cron}")
    minute, hour, dom, month, dow = fields

    def part(value: str, first: int) -> str:
        if value == "*":
            return "*"
        out = []
        for item in value.split(","):
            if item.startswith("*/"):
                out.append(f"{first}/{item[2:]}")
            elif "/" in item:
                base, step = item.split("/", 1)
                out.append(f"{base.replace('-', '..')}/{step}")
            else:
                out.append(item.replace("-", ".."))
        return ",".join(out)

    def weekday(value: str) -> str:
        if value == "*":
            return ""
        out = []
        for item in value.split(","):
            if "-" in item:
                start, end = item.split("-", 1)
                out.append(f"{DOW_NAMES[int(start)]}..{DOW_NAMES[int(end)]}")
            else:
                out.append(DOW_NAMES[int(item)])
        return ",".join(out) + " "

    return f"{weekday(dow)}*-{part(month, 1)}-{part(dom, 1)} {part(hour, 0)}:{part(minute, 0)}:00"


def _looks_like_ip(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def resolve(cfg: Config, catalog: Catalog, mode: str, provider: str = "", cluster_version: str = "") -> Plan:
    return Resolver(cfg, catalog, mode, provider, cluster_version).run()
