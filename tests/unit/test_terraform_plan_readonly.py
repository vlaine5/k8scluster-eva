"""Non-régression : make plan Proxmox est sans effet sur les VM.

Ce test traverse le CLI Bash et le résolveur Python réels, mais remplace
uniquement la commande Terraform par une simulation locale. Aucun Proxmox
ni accès réseau ne sont nécessaires. Les configurations privées ne sont
jamais lues : le test crée un dépôt minimal dans tmp_path.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def test_make_plan_exports_config_and_never_applies(lab_root: Path) -> None:
    """Le plan reçoit les 4 nœuds de .env et ne peut pas faire apply."""
    # Le fixture lab_root prépare config/, addons/ et les variables providers.
    shutil.copytree(REPO / "scripts", lab_root / "scripts")
    shutil.copy2(REPO / "Makefile", lab_root / "Makefile")
    shutil.copy2(REPO / "k8s-lab", lab_root / "k8s-lab")
    shutil.copy2(REPO / "examples/profiles/homelab-pv05.env", lab_root / ".env")
    shutil.copy2(
        REPO / "examples/homelab/terraform.tfvars.example",
        lab_root / "terraform/providers/proxmox/terraform.tfvars",
    )

    log = lab_root / "terraform-calls.txt"
    variables = lab_root / "terraform-vars.txt"
    fake = lab_root / "fake-terraform"
    fake.write_text(
        '#!/usr/bin/env bash\n'
        'set -euo pipefail\n'
        'printf "%s\\n" "$*" >> "$TF_TEST_LOG"\n'
        'case " $* " in *" apply "* | *" destroy "*) exit 98 ;; esac\n'
        'printf "%s\\n" "$TF_VAR_control_plane_count" "$TF_VAR_worker_count" '
        '"$TF_VAR_node_cpus" "$TF_VAR_node_memory_mb" "$TF_VAR_node_disk_gb" '
        '"$TF_VAR_longhorn_disk_gb" "$TF_VAR_node_os" > "$TF_TEST_VARS"\n'
    )
    fake.chmod(0o700)
    environ = {k: v for k, v in os.environ.items() if not k.startswith("TF_VAR_")}
    environ.update({
        "TERRAFORM_BIN": str(fake),
        "K8S_LAB_SKIP_DOCTOR": "1",
        "TF_TEST_LOG": str(log),
        "TF_TEST_VARS": str(variables),
        # Protéger le home / la configuration de l’utilisateur et éviter le réseau.
        "HOME": str(lab_root),
    })
    proc = subprocess.run(
        ["make", "plan", "MODE=terraform", "PROVIDER=proxmox"],
        cwd=lab_root, env=environ, capture_output=True, text=True, check=False,
        timeout=90,
    )
    assert proc.returncode == 0, proc.stdout + "\n" + proc.stderr
    commands = log.read_text(encoding="utf-8").splitlines()
    assert len(commands) == 2, commands
    assert commands[0].endswith(" init -input=false")
    assert commands[1].endswith(" plan -input=false")
    assert all(" apply " not in f" {c} " for c in commands)
    assert all(" destroy " not in f" {c} " for c in commands)
    assert variables.read_text(encoding="utf-8").splitlines() == [
        "1", "3", "4", "4096", "300", "100", "debian",
    ]
