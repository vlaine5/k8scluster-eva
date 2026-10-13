"""Fixtures des tests unitaires du résolveur (aucun réseau, aucune infrastructure)."""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))

from labcore.catalog import Catalog  # noqa: E402
from labcore.config import Config  # noqa: E402
from labcore.resolve import Plan, Resolver  # noqa: E402


@pytest.fixture()
def lab_root(tmp_path: Path) -> Path:
    """Copie minimale du dépôt : config/, addons/ et variables Terraform (sans .env ni tfvars)."""
    shutil.copytree(REPO / "config", tmp_path / "config")
    (tmp_path / "addons").symlink_to(REPO / "addons")
    for provider in ("proxmox", "vsphere", "libvirt", "eks"):
        target = tmp_path / "terraform" / "providers" / provider
        target.mkdir(parents=True)
        shutil.copy(REPO / "terraform" / "providers" / provider / "variables.tf", target / "variables.tf")
    (tmp_path / "ansible" / "inventories").mkdir(parents=True)
    return tmp_path


class Lab:
    """Aide : écrit un .env, résout, et donne accès au plan."""

    def __init__(self, root: Path):
        self.root = root

    def env(self, text: str) -> "Lab":
        (self.root / ".env").write_text(text.strip() + "\n", encoding="utf-8")
        return self

    def tfvars(self, provider: str, text: str) -> "Lab":
        (self.root / "terraform" / "providers" / provider / "terraform.tfvars").write_text(text, encoding="utf-8")
        return self

    def file(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def config(self, environ: dict[str, str] | None = None) -> Config:
        return Config.load(self.root, environ=environ or {})

    def plan(self, mode: str = "kind", provider: str = "", environ: dict[str, str] | None = None,
             cluster_version: str = "") -> Plan:
        cfg = self.config(environ)
        return Resolver(cfg, Catalog.load(self.root), mode, provider, cluster_version).run()


@pytest.fixture()
def lab(lab_root: Path) -> Lab:
    return Lab(lab_root)


def messages(plan: Plan, level: str = "error") -> str:
    """Messages (et conseils) d'un niveau donné, pour les assertions."""
    return "\n".join(f"{i.message} {i.hint}" for i in plan.issues if i.level == level)
