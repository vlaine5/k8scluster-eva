"""Catalogue des addons (addons/<id>/addon.yaml), versions et profils."""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import yaml

PLATFORMS = ["kind", "minikube", "vagrant", "proxmox", "vsphere", "libvirt", "existing", "eks", "attach"]
STATUSES = ["supported", "configured", "experimental", "unsupported"]
STATUS_LABELS = {
    "supported": "Supporté",
    "configured": "Supporté avec configuration particulière",
    "experimental": "Expérimental",
    "unsupported": "Non supporté",
}
CATEGORIES = ["network", "storage", "security", "infrastructure", "observability", "gitops",
              "backup", "autoscaling", "operations", "mesh"]
REQUIRED_KEYS = ["id", "name", "description", "category", "phase", "support"]


class CatalogError(ValueError):
    pass


@dataclass
class Support:
    status: str
    note: str = ""


@dataclass
class Addon:
    id: str
    name: str
    description: str
    category: str
    phase: int
    path: Path
    data: dict[str, Any]
    support: dict[str, Support] = field(default_factory=dict)

    @property
    def components(self) -> list[str]:
        comp = self.data.get("components", [])
        return list(comp) if isinstance(comp, list) else [comp]

    @property
    def depends_on(self) -> list[str]:
        return list(self.data.get("depends_on", []))

    @property
    def optional_deps(self) -> list[str]:
        return list(self.data.get("integrates_with", []))

    @property
    def conflicts_with(self) -> list[str]:
        return list(self.data.get("conflicts_with", []))

    @property
    def requires(self) -> dict[str, Any]:
        return dict(self.data.get("requires", {}))

    @property
    def stateful(self) -> bool:
        return bool(self.data.get("stateful", False))

    @property
    def internal(self) -> bool:
        """Addon ajouté uniquement comme dépendance ou par un sélecteur."""
        return bool(self.data.get("internal", False))

    @property
    def selected_by(self) -> dict[str, list[str]]:
        return dict(self.data.get("selected_by", {}))

    @property
    def validated(self) -> list[str]:
        return list(self.data.get("validated", []))

    @property
    def settings(self) -> list[str]:
        return list(self.data.get("settings", []))

    @property
    def secrets(self) -> list[str]:
        return list(self.data.get("secrets", []))

    @property
    def node_prereqs(self) -> dict[str, Any]:
        return dict(self.data.get("node_prereqs", {}))

    @property
    def resources(self) -> dict[str, int]:
        return dict(self.data.get("resources", {}))

    def support_for(self, platform: str) -> Support:
        return self.support.get(platform, Support("unsupported", "non évalué"))


@dataclass
class Catalog:
    root: Path
    addons: dict[str, Addon]
    versions: dict[str, Any]
    profiles: dict[str, Any]

    @classmethod
    def load(cls, root: Path) -> "Catalog":
        versions = yaml.safe_load((root / "config" / "versions.yaml").read_text(encoding="utf-8"))
        profiles = yaml.safe_load((root / "config" / "profiles.yaml").read_text(encoding="utf-8"))["profiles"]
        addons: dict[str, Addon] = {}
        for path in sorted((root / "addons").glob("*/addon.yaml")):
            addon = load_addon(path)
            if addon.id != path.parent.name:
                raise CatalogError(f"{path}: id={addon.id} différent du nom du dossier {path.parent.name}")
            addons[addon.id] = addon
        catalog = cls(root=root, addons=addons, versions=versions, profiles=profiles)
        catalog.check()
        return catalog

    def check_files(self) -> list[str]:
        """Fichiers référencés par les addons (valeurs, manifestes, tests) : contrôle de CI."""
        problems = []
        for addon in self.addons.values():
            install = addon.data.get("install", {})
            for release in install.get("releases", []):
                values = release.get("values")
                if values and not (addon.path / values).is_file():
                    problems.append(f"addon {addon.id}: fichier de valeurs absent : {values}")
            for manifest in install.get("manifests", []) + install.get("manifests_pre", []):
                if not (addon.path / "manifests" / manifest).is_file():
                    problems.append(f"addon {addon.id}: manifeste absent : manifests/{manifest}")
            for key in ("tasks",):
                if install.get(key) and not (addon.path / install[key]).is_file():
                    problems.append(f"addon {addon.id}: tâches absentes : {install[key]}")
            tests = addon.data.get("tests")
            if tests and not (addon.path / tests).is_file():
                problems.append(f"addon {addon.id}: fichier de tests absent : {tests}")
            if not addon.data.get("docs"):
                problems.append(f"addon {addon.id}: champ docs manquant")
        return problems

    # --- versions ---------------------------------------------------------------
    def component(self, name: str) -> dict[str, Any]:
        try:
            return dict(self.versions["components"][name])
        except KeyError as exc:
            raise CatalogError(f"composant {name} absent de config/versions.yaml") from exc

    def os_entry(self, os_name: str, version: str) -> Optional[dict[str, Any]]:
        return self.versions.get("os", {}).get(os_name, {}).get(str(version))

    # --- contrôle de cohérence (lancé en CI) ---------------------------------------
    def check(self) -> None:
        components = self.versions.get("components", {})
        for addon in self.addons.values():
            for comp in addon.components:
                if comp not in components:
                    raise CatalogError(f"addon {addon.id}: composant {comp} absent de config/versions.yaml")
            for dep in addon.depends_on + addon.optional_deps + addon.conflicts_with:
                if dep not in self.addons and dep != "gateway-controller":
                    raise CatalogError(f"addon {addon.id}: référence inconnue {dep}")
            for release in addon.data.get("install", {}).get("releases", []):
                if release.get("component") not in components:
                    raise CatalogError(f"addon {addon.id}: release {release.get('name')} sans composant connu")
            for other in addon.requires.get("any_addon", []):
                if other not in self.addons:
                    raise CatalogError(f"addon {addon.id}: requires.any_addon inconnu {other}")
        for name, profile in self.profiles.items():
            for addon_id in profile.get("addons", []):
                if addon_id not in self.addons:
                    raise CatalogError(f"profil {name}: addon inconnu {addon_id}")


def load_addon(path: Path) -> Addon:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    missing = [k for k in REQUIRED_KEYS if k not in data]
    if missing:
        raise CatalogError(f"{path}: clés obligatoires manquantes : {', '.join(missing)}")
    if data["category"] not in CATEGORIES:
        raise CatalogError(f"{path}: catégorie inconnue {data['category']}")
    support = parse_support(path, data["support"])
    return Addon(id=data["id"], name=data["name"], description=data["description"],
                 category=data["category"], phase=int(data["phase"]), path=path.parent,
                 data=data, support=support)


def parse_support(path: Path, raw: dict[str, Any]) -> dict[str, Support]:
    default = raw.get("default")
    result: dict[str, Support] = {}
    for platform in PLATFORMS:
        entry = raw.get(platform, default)
        if entry is None:
            raise CatalogError(f"{path}: support non défini pour {platform} (ajoutez 'default')")
        if isinstance(entry, str):
            entry = {"status": entry}
        status = entry.get("status")
        if status not in STATUSES:
            raise CatalogError(f"{path}: statut inconnu {status} pour {platform}")
        result[platform] = Support(status=status, note=entry.get("note", ""))
    unknown = set(raw) - set(PLATFORMS) - {"default"}
    if unknown:
        raise CatalogError(f"{path}: plateformes inconnues {', '.join(sorted(unknown))}")
    return result
