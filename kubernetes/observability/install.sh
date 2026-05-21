#!/usr/bin/env bash
# =============================================================================
# Install the observability stack (kube-prometheus-stack + loki-stack) onto
# a freshly applied PayEye dev cluster.
#
# Usage:
#   $(terraform -chdir=../../terraform/environments/dev output -raw eks_kubeconfig_command)
#   ./install.sh
#
# The lean values used here are intentionally sized for a 2x t3.medium dev
# cluster (~6 GiB total pod RAM). For prod, edit values-kube-prometheus-stack.yaml
# to raise retention, scale Prometheus to HA, enable Alertmanager with SNS,
# and switch storage to gp3 + KMS-encrypted EBS.
# =============================================================================

set -euo pipefail

NS="observability"

echo "=== ensuring observability namespace ==="
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

echo
echo "=== adding helm repos ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo
echo "=== installing kube-prometheus-stack ==="
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace "${NS}" \
  --values "$(dirname "$0")/values-kube-prometheus-stack.yaml" \
  --wait \
  --timeout=10m

echo
echo "=== installing loki-stack (single binary + promtail DaemonSet) ==="
helm upgrade --install loki grafana/loki-stack \
  --namespace "${NS}" \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=2Gi \
  --set loki.persistence.storageClassName=gp2 \
  --set loki.resources.requests.cpu=50m \
  --set loki.resources.requests.memory=128Mi \
  --set loki.resources.limits.memory=384Mi \
  --set promtail.enabled=true \
  --set promtail.resources.requests.cpu=25m \
  --set promtail.resources.requests.memory=64Mi \
  --wait \
  --timeout=10m

echo
echo "=== final pod status ==="
kubectl -n "${NS}" get pods

echo
echo "=== access Grafana locally ==="
echo "  kubectl -n ${NS} port-forward svc/kps-grafana 3000:80"
echo "  open http://localhost:3000  (admin / payeye-demo)"
echo
echo "=== access Prometheus locally ==="
echo "  kubectl -n ${NS} port-forward svc/kps-prometheus 9090:9090"
echo "  open http://localhost:9090"
