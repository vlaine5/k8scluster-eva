#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  Tests de bon fonctionnement ("smoke tests") d'un cluster.
#  Les commandes affichées sont exactement celles que vous pouvez taper.
# =============================================================================

# Vérifications minimales, lancées à la fin de chaque déploiement.
#   smoke_basic <contexte>
smoke_basic() {
  local context="$1"
  export KUBECONFIG="${LAB_KUBECONFIG}"
  kubectl config use-context "${context}" >/dev/null

  step "Vérification du cluster \"${context}\""
  run kubectl cluster-info
  run kubectl wait --for=condition=Ready nodes --all --timeout=300s ||
    die "Des nœuds ne sont pas Ready après 5 minutes." \
      "Diagnostic : kubectl describe nodes   puis   kubectl get pods -A" \
      "Voir docs/troubleshooting.md"
  run kubectl get nodes -o wide
  run kubectl --namespace kube-system wait --for=condition=Ready pods --all \
    --field-selector=status.phase!=Succeeded --timeout=300s ||
    die "Des Pods système ne sont pas prêts après 5 minutes." \
      "Diagnostic : kubectl get pods -A   puis   kubectl -n kube-system describe pod <nom>"
  run kubectl get pods --all-namespaces
  ok "Le cluster \"${context}\" répond et tous ses nœuds sont Ready."
}

# Test applicatif : déploie examples/ (nginx), l'appelle via son Service
# depuis un Pod client (teste DNS + réseau des Pods + kube-proxy), puis nettoie
# (--cleanup) ou conserve les ressources (--keep).
#   smoke_app --cleanup|--keep
smoke_app() {
  local keep="$1" output
  export KUBECONFIG="${LAB_KUBECONFIG}"
  local context
  context="$(kubectl config current-context 2>/dev/null)" ||
    die "Aucun cluster actif dans .kube/config." "Déployez d'abord un cluster : $(hint_cmd deploy kind)"

  step "Test applicatif sur \"${context}\" : nginx + Service + DNS"
  run kubectl apply -f "${LAB_ROOT}/examples/namespace.yaml"
  run kubectl apply -f "${LAB_ROOT}/examples/nginx-deployment.yaml" -f "${LAB_ROOT}/examples/service.yaml"
  run kubectl --namespace demo rollout status deployment/nginx --timeout=300s ||
    die "Le Deployment nginx n'est pas disponible." "Diagnostic : kubectl -n demo describe pods"
  run kubectl --namespace demo get pods,service -o wide

  info "Appel du Service \"nginx\" depuis un Pod client (résolution DNS + réseau des Pods) :"
  kubectl --namespace demo delete pod smoke-client --ignore-not-found >/dev/null 2>&1 || true
  local client=(kubectl --namespace demo run smoke-client --rm -i --restart=Never
    --image=busybox:1.38 --pod-running-timeout=3m -- wget -qO- -T 10 http://nginx)
  printf '%s$ %s%s\n' "${C_CYAN}" "${client[*]}" "${C_RESET}"
  if output="$("${client[@]}" 2>&1)" && grep -q "Welcome to nginx" <<<"${output}"; then
    ok "Le Service nginx répond depuis l'intérieur du cluster."
  else
    printf '%s\n' "${output}" >&2
    die "Le Service nginx ne répond pas depuis un autre Pod." \
      "Vérifiez le CNI et CoreDNS : kubectl get pods -A" \
      "Voir docs/troubleshooting.md"
  fi

  if [[ "${keep}" == "--keep" ]]; then
    info "Ressources conservées (namespace demo). Suppression : kubectl delete namespace demo"
  else
    run kubectl delete namespace demo --wait=true --timeout=120s
  fi
  ok "Test applicatif réussi."
}
