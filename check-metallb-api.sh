#!/bin/bash

VERSION="${1:-0.15.3}"

echo "=== Pulling MetalLB chart version $VERSION ==="

helm repo add metallb https://metallb.github.io/metallb >/dev/null 2>&1
helm repo update >/dev/null 2>&1

rm -rf metallb-chart

helm pull metallb/metallb --version "$VERSION" --untar -d metallb-chart

echo
echo "=== Rendering manifests ==="

helm template metallb metallb-chart/metallb > rendered.yaml

echo
echo "=== API Versions Used ==="
grep '^apiVersion:' rendered.yaml | awk '{print $2}' | sort | uniq -c

echo
echo "=== CRDs ==="
grep -A2 'kind: CustomResourceDefinition' rendered.yaml | grep name

echo
echo "=== Workloads ==="
grep '^kind:' rendered.yaml | awk '{print $2}' | sort | uniq -c