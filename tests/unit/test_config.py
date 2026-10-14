"""Chargement de la configuration : formats, priorités, types, anciens noms."""
from conftest import messages

from labcore import envfile
from labcore.config import SOURCE_DEFAULT, SOURCE_DOTENV, SOURCE_ENV


def test_env_file_format():
    values, warnings = envfile.parse_env_text(
        '# commentaire\n\nA=1\nB="deux mots"\nC=\'x\'\nmauvaise ligne\nD=a=b\nE=\n', "test")
    assert values == {"A": "1", "B": "deux mots", "C": "x", "D": "a=b", "E": ""}
    assert len(warnings) == 1 and "mauvaise ligne" in warnings[0]


def test_priority_environment_over_dotenv_over_defaults(lab):
    lab.env("WORKER_COUNT=3\nCLUSTER_NAME=depuis-env-file")
    cfg = lab.config({"WORKER_COUNT": "5"})
    assert cfg.get("WORKER_COUNT") == "5" and cfg.source("WORKER_COUNT") == SOURCE_ENV
    assert cfg.get("CLUSTER_NAME") == "depuis-env-file" and cfg.source("CLUSTER_NAME") == SOURCE_DOTENV
    assert cfg.get("POD_CIDR") == "10.244.0.0/16" and cfg.source("POD_CIDR") == SOURCE_DEFAULT


def test_values_already_exported_by_bash_keep_their_origin(lab):
    # Le CLI Bash exporte .env puis lab.env : l'origine doit rester lisible.
    lab.env("WORKER_COUNT=3")
    cfg = lab.config({"WORKER_COUNT": "3", "POD_CIDR": "10.244.0.0/16"})
    assert cfg.source("WORKER_COUNT") == SOURCE_DOTENV
    assert cfg.source("POD_CIDR") == SOURCE_DEFAULT
    assert not cfg.explicit("POD_CIDR") and cfg.explicit("WORKER_COUNT")


def test_type_errors_are_reported_before_anything_else(lab):
    lab.env("WORKER_COUNT=trois\nCNI=weave\nPOD_CIDR=10.244.1.0/16\nNODE_OS=arch")
    plan = lab.plan("kind")
    errors = messages(plan)
    assert "WORKER_COUNT=trois" in errors
    assert "CNI=weave" in errors
    assert "bits d'hôte" in errors
    assert "NODE_OS=arch" in errors
    assert not plan.addons


def test_unknown_variable_in_dotenv_is_flagged_with_suggestion(lab):
    lab.env("WORKER_COUNTS=3")
    plan = lab.plan("kind")
    assert "WORKER_COUNTS" in messages(plan, "warning")
    assert "WORKER_COUNT" in messages(plan, "warning")


def test_secrets_are_masked(lab):
    lab.env("PROXMOX_VE_API_TOKEN=terraform@pve!lab=secret-value")
    cfg = lab.config()
    assert cfg.masked("PROXMOX_VE_API_TOKEN") == "****"
    assert "PROXMOX_VE_API_TOKEN" in cfg.secrets_present()


def test_legacy_vm_image_url_still_works(lab):
    lab.env("VM_IMAGE_URL=https://example.org/custom.img\nVM_IMAGE_SHA256=" + "a" * 64)
    plan = lab.plan("terraform", "proxmox")
    assert plan.resolved["image"] == {"source": "url", "url": "https://example.org/custom.img", "sha256": "a" * 64}
    assert "VM_IMAGE_URL est un ancien nom" in messages(plan, "info")


def test_conflicting_legacy_and_new_image_variables(lab):
    lab.env("VM_IMAGE_URL=https://a.example/x.img\nNODE_IMAGE_URL=https://b.example/y.img")
    assert "NODE_IMAGE_URL et VM_IMAGE_URL" in messages(lab.plan("terraform", "proxmox"))


def test_legacy_flannel_version(lab):
    lab.env("FLANNEL_VERSION=v0.28.9")
    plan = lab.plan("vagrant")
    assert plan.resolved["cni_version"] == "v0.28.9"


def test_unknown_mode_and_provider(lab):
    assert "Mode inconnu" in messages(lab.plan("docker"))
    assert "Provider Terraform inconnu" in messages(lab.plan("terraform", "openstack"))
    assert "ne prend pas de provider" in messages(lab.plan("kind", "proxmox"))
