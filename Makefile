# =============================================================================
#  k8s-lab — raccourcis "make" (ils appellent tous ./k8s-lab).
#
#    make help
#    make doctor MODE=kind
#    make deploy MODE=kind
#    make deploy MODE=terraform PROVIDER=proxmox
#    make addons-apply MODE=attach
#    make destroy MODE=kind
#
#  Variables : MODE, PROVIDER (sinon DEPLOYMENT_MODE/DEPLOYMENT_PROVIDER de .env),
#  WORKERS, ADDON, NODE, SNAPSHOT, YES=1, RECREATE=1, KEEP=1, DESTRUCTIVE=1.
#  Toute variable de config/lab.env peut aussi être passée :
#    make deploy MODE=vagrant NODE_MEMORY_MB=4096
# =============================================================================

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

LAB      := ./k8s-lab
MODE     ?=
PROVIDER ?=
WORKERS  ?=
YES      ?=
RECREATE ?=
KEEP     ?=
DESTRUCTIVE ?=
ADDON    ?=
NODE     ?=
SNAPSHOT ?=
PYTHON   ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

truthy   = $(filter 1 true yes oui,$(1))
OPTIONS  := $(if $(call truthy,$(YES)),--yes) $(if $(call truthy,$(RECREATE)),--recreate) \
            $(if $(call truthy,$(KEEP)),--keep) $(if $(call truthy,$(DESTRUCTIVE)),--destructive) \
            $(if $(ADDON),--addon $(ADDON))
LAB_ENV  := $(if $(WORKERS),WORKER_COUNT=$(WORKERS)) $(if $(NODE),NODE=$(NODE)) $(if $(SNAPSHOT),SNAPSHOT=$(SNAPSHOT))
TARGET   := $(MODE) $(PROVIDER)

TF_DIRS  := terraform/providers/proxmox terraform/providers/vsphere terraform/providers/libvirt terraform/providers/eks
TF_TESTS := terraform/modules/k8s-nodes terraform/modules/ansible-inventory terraform/providers/eks
SHELL_SCRIPTS := k8s-lab $(wildcard scripts/*.sh scripts/lib/*.sh tests/*/*.sh)
PLAYBOOKS := site.yml preflight.yml addons.yml cni-local.yml reset.yml kubeconfig.yml backup.yml etcd-restore.yml \
             upgrade.yml os-update.yml node-remove.yml health.yml

.PHONY: help help-dev menu doctor config validate deploy destroy uninstall status kubeconfig test manifest \
        addons-plan addons-apply addons-status addons-test addons-upgrade addons-remove addons-catalog \
        upgrade-plan upgrade os-update backup restore health node-remove versions versions-check \
        venv test-unit catalog-check schema-check docs-generate matrix-check addons-render-check \
        lint shellcheck ruby-check vagrant-validate actionlint yamllint ansible-lint ansible-syntax \
        terraform-fmt terraform-validate terraform-test tflint markdownlint check-docs \
        check-config test-kubeadm

## --- Utilisation -------------------------------------------------------------

help: ## Aide : les commandes principales
	@printf '%s\n' \
	  '' \
	  'Kubernetes Lab - commandes principales' \
	  '' \
	  '  make doctor MODE=kind          vérifier votre machine et la configuration' \
	  '  make config MODE=kind          configuration effective et plan résolu (secrets masqués)' \
	  '  make deploy MODE=kind          créer / compléter le cluster puis installer les addons' \
	  '  make status                    voir les clusters du lab' \
	  '  make test                      tester le cluster actif (nginx + Service + DNS)' \
	  '  make destroy MODE=kind         supprimer le cluster (confirmation demandée)' \
	  '' \
	  '  make addons-plan|addons-apply|addons-status|addons-test|addons-upgrade MODE=...' \
	  '  make addons-remove MODE=... ADDON=nom      make addons-catalog' \
	  '  make upgrade-plan|upgrade|os-update|backup|health MODE=...   (clusters kubeadm)' \
	  '  make restore MODE=... SNAPSHOT=fichier     make node-remove MODE=... NODE=nom' \
	  '  make versions | versions-check             make uninstall MODE=existing' \
	  '' \
	  'Modes     MODE=kind   MODE=minikube   MODE=vagrant   MODE=existing   MODE=attach' \
	  '          MODE=terraform PROVIDER=proxmox   (ou PROVIDER=vsphere, PROVIDER=libvirt, PROVIDER=eks)' \
	  '          sans MODE : DEPLOYMENT_MODE de .env' \
	  'Options   WORKERS=3   RECREATE=1   YES=1   KEEP=1   DESTRUCTIVE=1   ADDON=a,b' \
	  '' \
	  'Puis : export KUBECONFIG="$$PWD/.kube/config" && kubectl get nodes' \
	  'Guides : docs/README.md   Menu interactif : ./k8s-lab   Toutes les cibles : make help-dev' \
	  ''

help-dev: ## Toutes les cibles, y compris la qualité (CI)
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-22s %s\n", $$1, $$2}'

menu: ## Menu interactif
	@$(LAB)

doctor: ## Vérifie les prérequis et la configuration (MODE=... PROVIDER=... facultatifs)
	@$(LAB_ENV) $(LAB) doctor $(TARGET)

config: ## Configuration effective, plan résolu, avertissements (secrets masqués)
	@$(LAB_ENV) $(LAB) config $(TARGET)

validate: ## Valide la configuration sans rien modifier
	@$(LAB_ENV) $(LAB) validate $(TARGET)

deploy: ## Crée / complète un cluster puis installe les addons
	@$(LAB_ENV) $(LAB) deploy $(TARGET) $(OPTIONS)

destroy: ## Détruit un cluster (confirmation ; refusé en modes existing et attach)
	@$(LAB_ENV) $(LAB) destroy $(TARGET) $(OPTIONS)

uninstall: ## Mode existing : retire Kubernetes des machines (machines conservées)
	@$(LAB_ENV) $(LAB) uninstall $(TARGET) $(OPTIONS)

status: ## État des clusters du lab
	@$(LAB) status

kubeconfig: ## Écrit .kube/config (MODE=... pour le rafraîchir)
	@$(LAB) kubeconfig $(TARGET)

test: ## Test applicatif (nginx) sur le cluster actif
	@$(LAB) test $(OPTIONS)

manifest: ## Manifeste du déploiement (.lab/manifests/, sans secret)
	@$(LAB_ENV) $(LAB) manifest $(TARGET)

addons-plan: ## Plan des addons (profil, dépendances, ordre, versions)
	@$(LAB_ENV) $(LAB) addons-plan $(TARGET)

addons-apply: ## Installe / synchronise les addons (ADDON=... pour en limiter la liste)
	@$(LAB_ENV) $(LAB) addons-apply $(TARGET) $(OPTIONS)

addons-status: ## État et santé des addons
	@$(LAB_ENV) $(LAB) addons-status $(TARGET) $(OPTIONS)

addons-test: ## Tests fonctionnels des addons (KEEP=1, DESTRUCTIVE=1)
	@$(LAB_ENV) $(LAB) addons-test $(TARGET) $(OPTIONS)

addons-upgrade: ## Met à jour les addons vers les versions verrouillées (après confirmation)
	@$(LAB_ENV) $(LAB) addons-upgrade $(TARGET) $(OPTIONS)

addons-remove: ## Désinstalle des addons (ADDON=... obligatoire ; données conservées)
	@$(LAB_ENV) $(LAB) addons-remove $(TARGET) $(OPTIONS)

addons-catalog: ## Liste des addons disponibles
	@$(LAB) addons-catalog

upgrade-plan: ## Plan de mise à niveau de Kubernetes (lecture seule)
	@$(LAB_ENV) $(LAB) upgrade-plan $(TARGET)

upgrade: ## Mise à niveau de Kubernetes (kubeadm, nœud par nœud, après confirmation)
	@$(LAB_ENV) $(LAB) upgrade $(TARGET) $(OPTIONS)

os-update: ## Mises à jour de l'OS des nœuds, un par un (après confirmation)
	@$(LAB_ENV) $(LAB) os-update $(TARGET) $(OPTIONS)

backup: ## Instantané etcd (clusters kubeadm)
	@$(LAB_ENV) $(LAB) backup $(TARGET)

restore: ## Restauration etcd (SNAPSHOT=... ; après confirmation)
	@$(LAB_ENV) $(LAB) restore $(TARGET) $(OPTIONS)

health: ## Santé du cluster kubeadm (etcd, certificats, services, disques)
	@$(LAB_ENV) $(LAB) health $(TARGET)

node-remove: ## Retire un nœud (NODE=... ; après confirmation)
	@$(LAB_ENV) $(LAB) node-remove $(TARGET) $(OPTIONS)

versions: ## Versions verrouillées (config/versions.yaml)
	@$(LAB) versions

versions-check: ## Versions plus récentes disponibles en amont (rien n'est installé)
	@$(LAB) versions-check

## --- Environnement et tests du framework -----------------------------------------

venv: ## Environnement Python du lab (.venv) : ansible-core, PyYAML, kubernetes, outils de test
	python3 -m venv .venv
	.venv/bin/pip install --upgrade pip >/dev/null
	.venv/bin/pip install -r requirements-dev.txt
	.venv/bin/ansible-galaxy collection install -r ansible/requirements.yml
	@echo "Activez-le : source .venv/bin/activate"

test-unit: ## Tests unitaires du résolveur (sans réseau ni cluster)
	$(PYTHON) -m pytest -q tests/unit

catalog-check: ## Cohérence du catalogue d'addons (fichiers, dépendances, ordre)
	$(PYTHON) scripts/labctl catalog-check

schema-check: ## Cohérence entre config/lab.env et config/schema.yaml
	$(PYTHON) scripts/labctl schema-check

docs-generate: ## Régénère les matrices de compatibilité de docs/compatibility.md
	$(PYTHON) scripts/labctl matrix --write docs/compatibility.md

matrix-check: ## Vérifie que docs/compatibility.md est à jour
	$(PYTHON) scripts/labctl matrix --check docs/compatibility.md

addons-render-check: ## Rendu de tous les addons + helm template (réseau requis, aucun cluster)
	$(PYTHON) tests/addons/render-check

## --- Qualité (utilisé par la CI) ------------------------------------------------

lint: shellcheck ruby-check yamllint ansible-lint ansible-syntax terraform-fmt terraform-validate terraform-test tflint markdownlint check-docs check-config schema-check catalog-check matrix-check test-unit ## Tous les contrôles statiques (+ vagrant-validate, actionlint et addons-render-check en CI)

shellcheck: ## ShellCheck sur les scripts
	shellcheck --external-sources --source-path=SCRIPTDIR $(SHELL_SCRIPTS)

ruby-check: ## Syntaxe du Vagrantfile
	ruby -c vagrant/Vagrantfile

actionlint: ## actionlint sur les workflows GitHub Actions (actionlint requis)
	actionlint

vagrant-validate: ## vagrant validate, sans hyperviseur (VirtualBox, 2 puis 4 workers ; Vagrant requis)
	cd vagrant && for n in 2 4; do VAGRANT_CHECKPOINT_DISABLE=1 VAGRANT_PROVIDER=virtualbox WORKER_COUNT=$$n vagrant validate --ignore-provider || exit 1; done

yamllint: ## yamllint sur tout le dépôt
	yamllint --strict .

ansible-lint: ## ansible-lint (profil production, rôles + tâches des addons)
	ansible-lint

ansible-syntax: ## ansible-playbook --syntax-check sur tous les playbooks
	cd ansible && for p in $(PLAYBOOKS); do ansible-playbook -i inventories/example.ini "$$p" --syntax-check || exit 1; done

terraform-fmt: ## terraform fmt -check
	terraform fmt -check -recursive -diff terraform

terraform-validate: ## terraform init (sans backend) + validate pour chaque provider
	for d in $(TF_DIRS); do (cd "$$d" && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; done

terraform-test: ## terraform test (modules communs, provider eks avec AWS simulé)
	for d in $(TF_TESTS); do (cd "$$d" && terraform init -backend=false -input=false >/dev/null && terraform test) || exit 1; done

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
