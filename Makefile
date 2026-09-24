# =============================================================================
#  k8s-lab — raccourcis "make" (ils appellent tous ./k8s-lab).
#
#    make help
#    make doctor MODE=kind
#    make deploy MODE=kind
#    make deploy MODE=terraform PROVIDER=proxmox
#    make destroy MODE=kind
#
#  Variables : MODE, PROVIDER, WORKERS (nombre de workers), YES=1 (pas de
#  confirmation), RECREATE=1. Toute clé de config/lab.env peut aussi être
#  passée : make deploy MODE=vagrant NODE_MEMORY_MB=4096
# =============================================================================

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

LAB      := ./k8s-lab
MODE     ?=
PROVIDER ?=
WORKERS  ?=
YES      ?=
RECREATE ?=

truthy   = $(filter 1 true yes oui,$(1))
OPTIONS  := $(if $(call truthy,$(YES)),--yes) $(if $(call truthy,$(RECREATE)),--recreate)
LAB_ENV  := $(if $(WORKERS),WORKER_COUNT=$(WORKERS))

TF_DIRS  := terraform/providers/proxmox terraform/providers/vsphere terraform/providers/libvirt
TF_MODS  := terraform/modules/k8s-nodes terraform/modules/ansible-inventory
SHELL_SCRIPTS := k8s-lab $(wildcard scripts/*.sh scripts/lib/*.sh tests/*/*.sh)

.PHONY: help help-dev menu doctor deploy destroy status kubeconfig test config \
        lint shellcheck ruby-check vagrant-validate yamllint ansible-lint ansible-syntax \
        terraform-fmt terraform-validate terraform-test tflint markdownlint check-docs \
        check-config test-kubeadm

## --- Utilisation -------------------------------------------------------------

help: ## Aide : les commandes principales
	@printf '%s\n' \
	  '' \
	  'Kubernetes Lab - commandes principales' \
	  '' \
	  '  make doctor MODE=kind      vérifier votre machine (sans MODE : tous les modes)' \
	  '  make deploy MODE=kind      créer le cluster (ne détruit jamais un cluster existant)' \
	  '  make status                voir les clusters du lab' \
	  '  make test                  tester le cluster actif (nginx + Service + DNS)' \
	  '  make kubeconfig            utiliser kubectl avec le lab' \
	  '  make destroy MODE=kind     supprimer le cluster (confirmation demandée)' \
	  '' \
	  'Modes     MODE=kind   MODE=minikube   MODE=vagrant' \
	  '          MODE=terraform PROVIDER=proxmox   (ou PROVIDER=vsphere, PROVIDER=libvirt)' \
	  'Options   WORKERS=3 (nombre de workers)   RECREATE=1 (recréer)   YES=1 (sans question)' \
	  '' \
	  'Puis : export KUBECONFIG="$$PWD/.kube/config" && kubectl get nodes' \
	  'Guides : docs/deployment.md   Menu interactif : ./k8s-lab   Toutes les cibles : make help-dev' \
	  ''

help-dev: ## Toutes les cibles, y compris la qualité (CI)
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-20s %s\n", $$1, $$2}'

menu: ## Menu interactif
	@$(LAB)

doctor: ## Vérifie les prérequis (MODE=... PROVIDER=... facultatifs)
	@$(LAB_ENV) $(LAB) doctor $(MODE) $(PROVIDER)

deploy: ## Crée un cluster (MODE=kind par défaut)
	@$(LAB_ENV) $(LAB) deploy $(MODE) $(PROVIDER) $(OPTIONS)

destroy: ## Détruit un cluster (MODE obligatoire, confirmation demandée)
	@$(LAB_ENV) $(LAB) destroy $(MODE) $(PROVIDER) $(OPTIONS)

status: ## État des clusters du lab
	@$(LAB) status

kubeconfig: ## Écrit .kube/config (MODE=... pour le rafraîchir)
	@$(LAB) kubeconfig $(MODE) $(PROVIDER)

test: ## Test applicatif (nginx) sur le cluster actif
	@$(LAB) test

config: ## Affiche la configuration effective
	@$(LAB_ENV) $(LAB) config

## --- Qualité (utilisé par la CI) ------------------------------------------------

lint: shellcheck ruby-check yamllint ansible-lint ansible-syntax terraform-fmt terraform-validate terraform-test tflint markdownlint check-docs check-config ## Tous les contrôles statiques (+ vagrant-validate en CI)

shellcheck: ## ShellCheck sur les scripts
	shellcheck --external-sources --source-path=SCRIPTDIR $(SHELL_SCRIPTS)

ruby-check: ## Syntaxe du Vagrantfile
	ruby -c vagrant/Vagrantfile

vagrant-validate: ## vagrant validate, sans hyperviseur (VirtualBox, 2 puis 4 workers ; Vagrant requis)
	cd vagrant && for n in 2 4; do VAGRANT_CHECKPOINT_DISABLE=1 VAGRANT_PROVIDER=virtualbox WORKER_COUNT=$$n vagrant validate --ignore-provider || exit 1; done

yamllint: ## yamllint sur tout le dépôt
	yamllint --strict .

ansible-lint: ## ansible-lint (profil production)
	cd ansible && ansible-lint

ansible-syntax: ## ansible-playbook --syntax-check
	cd ansible && for p in site.yml reset.yml kubeconfig.yml; do ansible-playbook -i inventories/example.ini "$$p" --syntax-check || exit 1; done

terraform-fmt: ## terraform fmt -check
	terraform fmt -check -recursive -diff terraform

terraform-validate: ## terraform init (sans backend) + validate pour chaque provider
	for d in $(TF_DIRS); do (cd "$$d" && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; done

terraform-test: ## terraform test sur les modules communs
	for d in $(TF_MODS); do (cd "$$d" && terraform init -backend=false -input=false >/dev/null && terraform test) || exit 1; done

tflint: ## TFLint sur tout le code Terraform
	tflint --init --config "$(CURDIR)/.tflint.hcl" >/dev/null
	tflint --recursive --config "$(CURDIR)/.tflint.hcl" --chdir terraform

markdownlint: ## markdownlint sur la documentation
	markdownlint-cli2 "**/*.md"

check-docs: ## Liens, pages docs/*.md et commandes make cités dans la documentation
	scripts/check-docs.sh

test-kubeadm: ## Test d'intégration : site.yml sur des nœuds conteneurs systemd (Docker requis)
	tests/kubeadm-in-docker/run.sh

check-config: ## Vérifie la cohérence des valeurs par défaut (lab.env / Terraform / Ansible / kind)
	scripts/check-config-sync.sh
