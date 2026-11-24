#!/usr/bin/env bash
# Install (or upgrade) the lab's sample apps into a namespace with the repository's `common` Helm chart.
#
#   ./deploy.sh <namespace> <app> [<app> ...]      apps: curl curl-other httpbin helloworld-v1 helloworld-v2 fortio
#   ./deploy.sh lab-sidecar curl httpbin
#   ./deploy.sh lab-sidecar --delete               remove every app release from the namespace
#
# Honours KUBECONFIG and `KUBE_CONTEXT` (optional): the apps go to whichever cluster kubectl would use.
# The namespace is created if it does not exist; labels (injection / ambient) are set by each lab, not here.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="${CHART:-$HERE/../../../kubernetes/charts/common}"
APPS=(curl curl-other httpbin helloworld-v1 helloworld-v2 fortio)
CTX=()
[[ -n "${KUBE_CONTEXT:-}" ]] && CTX=(--kube-context "$KUBE_CONTEXT")
KCTX=()
[[ -n "${KUBE_CONTEXT:-}" ]] && KCTX=(--context "$KUBE_CONTEXT")

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }
[[ $# -ge 2 ]] || usage
ns="$1"; shift

if [[ "$1" == "--delete" ]]; then
  for app in "${APPS[@]}"; do
    helm "${CTX[@]}" -n "$ns" uninstall "$app" >/dev/null 2>&1 && echo "removed $app from $ns" || true
  done
  exit 0
fi

kubectl "${KCTX[@]}" get namespace "$ns" >/dev/null 2>&1 || kubectl "${KCTX[@]}" create namespace "$ns"
for app in "$@"; do
  file="$HERE/$app.values.yaml"
  [[ -f "$file" ]] || { echo "unknown app '$app' (have: ${APPS[*]})" >&2; exit 1; }
  helm "${CTX[@]}" upgrade --install "$app" "$CHART" -n "$ns" -f "$file" --wait --timeout 3m >/dev/null
  echo "deployed $app in $ns"
done
