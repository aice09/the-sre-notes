#!/bin/bash

set -euo pipefail

CHART="datawire/emissary-ingress"
BASE_DIR="${HOME}/charts/emissary-ingress"
CHART_NAME="emissary-ingress"

VERSIONS=(
7.1.10
7.2.0
7.2.2
7.3.0
7.3.1
7.3.2
7.4.0
7.4.1
7.4.2
7.5.0
7.5.1
7.6.0
7.6.1
8.0.0
8.1.0
8.2.0
8.3.0
8.3.1
8.4.0
8.4.1
8.5.0
8.5.1
8.5.2
8.6.0
8.7.0
8.7.1
8.7.2
8.8.0
8.8.1
8.8.2
8.9.0
8.9.1
8.12.2
)

download() {

echo "===== DOWNLOAD MODE ====="

mkdir -p "${BASE_DIR}"

for v in "${VERSIONS[@]}"; do

TARGET="${BASE_DIR}/${v}/${CHART_NAME}"

if [ -d "$TARGET" ]; then
echo "✅ $v exists → skip"
continue
fi

echo "⬇️ downloading $v"

mkdir -p "${BASE_DIR}/${v}"

helm pull "${CHART}" \
--version "${v}" \
--untar \
--untardir "${BASE_DIR}/${v}"

done

echo "✅ Download complete"
}

diffcharts() {

echo "===== DIFF MODE ====="

for ((i=0;i<${#VERSIONS[@]}-1;i++)); do

FROM="${VERSIONS[$i]}"
TO="${VERSIONS[$((i+1))]}"

echo "🔎 diff $FROM -> $TO"

diff -ur \
"${BASE_DIR}/${FROM}" \
"${BASE_DIR}/${TO}" \
> "${BASE_DIR}/diff-${FROM}-${TO}.txt" || true

done

echo "✅ Diff files generated"
}

usage() {
echo ""
echo "Usage:"
echo "./emissary-upgrade-lab.sh download"
echo "./emissary-upgrade-lab.sh diff"
echo "./emissary-upgrade-lab.sh all"
echo ""
}

case "${1:-}" in
download)
download
;;
diff)
diffcharts
;;
all)
download
diffcharts
;;
*)
usage
;;
esac
