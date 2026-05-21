#!/usr/bin/env bash
# =============================================================================
# Install Istio Ambient mesh on the PayEye dev cluster.
#
# Architecture:
#   - istiod          (control plane, single Deployment in istio-system)
#   - istio-cni       (DaemonSet — programs node iptables to redirect
#                      pod traffic to ztunnel)
#   - ztunnel         (DaemonSet — per-node L4 proxy that terminates and
#                      originates mTLS for every workload in the namespace
#                      labeled istio.io/dataplane-mode=ambient. NO sidecars.)
#   - waypoint proxy  (optional, per-namespace or per-service Deployment;
#                      handles L7 features when AuthorizationPolicy needs
#                      HTTP-level matching. Spawned via Gateway API CRD.)
#
# Usage:
#   $(terraform -chdir=../../terraform/environments/dev output -raw eks_kubeconfig_command)
#   ./install-ambient.sh
#
# This is idempotent — re-running upgrades to the latest patch version of
# the chart per `helm upgrade --install`.
# =============================================================================

set -euo pipefail

ISTIO_NS="istio-system"
ISTIO_VERSION="1.24.1"
GATEWAY_API_VERSION="v1.2.0"

cd "$(dirname "$0")"

echo "=== installing Kubernetes Gateway API CRDs (required for waypoints) ==="
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo
echo "=== adding istio helm repo ==="
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update istio

echo
echo "=== creating istio-system namespace ==="
kubectl create namespace "${ISTIO_NS}" --dry-run=client -o yaml | kubectl apply -f -

echo
echo "=== installing istio-base (CRDs + ClusterRoles) ==="
helm upgrade --install istio-base istio/base \
  --namespace "${ISTIO_NS}" \
  --version "${ISTIO_VERSION}" \
  --set defaultRevision=default \
  --wait

echo
echo "=== installing istiod (ambient profile) ==="
helm upgrade --install istiod istio/istiod \
  --namespace "${ISTIO_NS}" \
  --version "${ISTIO_VERSION}" \
  --set profile=ambient \
  --wait

echo
echo "=== installing istio-cni (programs node iptables for pod traffic redirect) ==="
helm upgrade --install istio-cni istio/cni \
  --namespace "${ISTIO_NS}" \
  --version "${ISTIO_VERSION}" \
  --set profile=ambient \
  --wait

echo
echo "=== installing ztunnel (per-node L4 + mTLS DaemonSet) ==="
helm upgrade --install ztunnel istio/ztunnel \
  --namespace "${ISTIO_NS}" \
  --version "${ISTIO_VERSION}" \
  --wait

echo
echo "=== verifying control plane + dataplane ==="
kubectl -n "${ISTIO_NS}" get pods -o wide

echo
echo "=== applying STRICT mTLS PeerAuthentication ==="
kubectl apply -f peer-authentication-strict.yaml

echo
echo "Ambient mesh ready."
echo
echo "Next steps:"
echo "  - Label namespaces to opt into ambient: kubectl label ns <name> istio.io/dataplane-mode=ambient"
echo "  - Apply waypoint per namespace if you need L7 features: kubectl apply -f waypoints/"
echo "  - Apply L7 authorization policies: kubectl apply -f authz-policies/"
