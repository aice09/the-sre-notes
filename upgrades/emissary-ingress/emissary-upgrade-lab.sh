#!/usr/bin/env bash
set -euo pipefail

CHART="datawire/emissary-ingress"
CHART_NAME="emissary-ingress"
BASE_DIR="${HOME}/charts/emissary-ingress"

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

ensure_tools() {
  local missing=0
  for cmd in helm diff grep awk sed sort uniq find comm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "❌ missing required command: $cmd"
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}

prepare_dirs() {
  mkdir -p "${BASE_DIR}"/{raw-diff,rendered,rendered-diff,analysis,images,crd-report,values-report,logs}
}

download() {
  echo "===== DOWNLOAD MODE ====="

  for v in "${VERSIONS[@]}"; do
    local target="${BASE_DIR}/${v}/${CHART_NAME}"

    if [ -d "$target" ]; then
      echo "✅ ${v} exists -> skip"
      continue
    fi

    echo "⬇️  downloading ${v}"
    mkdir -p "${BASE_DIR}/${v}"

    helm pull "${CHART}" \
      --version "${v}" \
      --untar \
      --untardir "${BASE_DIR}/${v}"
  done

  echo "✅ Download complete"
}

raw_diff() {
  echo "===== RAW CHART DIFF MODE ====="

  for ((i=0; i<${#VERSIONS[@]}-1; i++)); do
    local from="${VERSIONS[$i]}"
    local to="${VERSIONS[$((i+1))]}"
    local outfile="${BASE_DIR}/raw-diff/diff-${from}-${to}.txt"

    echo "🔎 raw diff ${from} -> ${to}"

    diff -ur \
      "${BASE_DIR}/${from}/${CHART_NAME}" \
      "${BASE_DIR}/${to}/${CHART_NAME}" \
      > "${outfile}" || true
  done

  echo "✅ Raw diff files generated"
}

render_all() {
  echo "===== RENDER MODE ====="

  for v in "${VERSIONS[@]}"; do
    local chart_path="${BASE_DIR}/${v}/${CHART_NAME}"
    local out="${BASE_DIR}/rendered/rendered-${v}.yaml"

    echo "🧩 rendering ${v}"

    helm template "emissary-${v}" "${chart_path}" \
      > "${out}"
  done

  echo "✅ Rendered manifests generated"
}

rendered_diff() {
  echo "===== RENDERED DIFF MODE ====="

  for ((i=0; i<${#VERSIONS[@]}-1; i++)); do
    local from="${VERSIONS[$i]}"
    local to="${VERSIONS[$((i+1))]}"
    local outfile="${BASE_DIR}/rendered-diff/rendered-diff-${from}-${to}.txt"

    echo "🔎 rendered diff ${from} -> ${to}"

    diff -u \
      "${BASE_DIR}/rendered/rendered-${from}.yaml" \
      "${BASE_DIR}/rendered/rendered-${to}.yaml" \
      > "${outfile}" || true
  done

  echo "✅ Rendered diff files generated"
}

extract_images() {
  echo "===== IMAGE EXTRACTION MODE ====="

  : > "${BASE_DIR}/images/all-images-unique.txt"

  for v in "${VERSIONS[@]}"; do
    local rendered="${BASE_DIR}/rendered/rendered-${v}.yaml"
    local out="${BASE_DIR}/images/images-${v}.txt"

    echo "🖼️  extracting images from ${v}"

    grep -E '^[[:space:]]*image:' "${rendered}" \
      | sed -E 's/^[[:space:]]*image:[[:space:]]*//' \
      | sed -E 's/^"//; s/"$//' \
      | sed -E "s/^'//; s/'$//" \
      | sort -u \
      > "${out}" || true

    cat "${out}" >> "${BASE_DIR}/images/all-images-unique.txt"
  done

  sort -u "${BASE_DIR}/images/all-images-unique.txt" -o "${BASE_DIR}/images/all-images-unique.txt"

  echo "✅ Image lists generated"
}

crd_report() {
  echo "===== CRD REPORT MODE ====="

  for v in "${VERSIONS[@]}"; do
    local out="${BASE_DIR}/crd-report/crds-${v}.txt"
    local chart_path="${BASE_DIR}/${v}/${CHART_NAME}"

    {
      echo "CRD files for ${v}"
      echo "=============================="
      find "${chart_path}/crds" -type f 2>/dev/null | sed "s#${chart_path}/##" | sort || true
      echo
      echo "Rendered CRD objects"
      echo "=============================="
      awk '
        /^kind: CustomResourceDefinition$/ { print last_name "\nkind: CustomResourceDefinition\n" }
        /^  name:/ { last_name=$0 }
      ' "${BASE_DIR}/rendered/rendered-${v}.yaml" || true
    } > "${out}"
  done

  for ((i=0; i<${#VERSIONS[@]}-1; i++)); do
    local from="${VERSIONS[$i]}"
    local to="${VERSIONS[$((i+1))]}"
    local out="${BASE_DIR}/crd-report/crd-diff-${from}-${to}.txt"

    {
      echo "CRD diff ${from} -> ${to}"
      echo "=============================="
      diff -u \
        "${BASE_DIR}/crd-report/crds-${from}.txt" \
        "${BASE_DIR}/crd-report/crds-${to}.txt" || true
    } > "${out}"
  done

  echo "✅ CRD reports generated"
}

values_key_report() {
  echo "===== VALUES KEY REPORT MODE ====="

  for v in "${VERSIONS[@]}"; do
    local values_file="${BASE_DIR}/${v}/${CHART_NAME}/values.yaml"
    local out="${BASE_DIR}/values-report/values-keys-${v}.txt"

    echo "🧾 extracting top-level/indented keys from ${v}"

    awk '
      /^[a-zA-Z0-9_.-]+:/ { print $1 }
      /^[[:space:]]+[a-zA-Z0-9_.-]+:/ { print $1 }
    ' "${values_file}" \
      | sed 's/:$//' \
      | sort -u \
      > "${out}" || true
  done

  for ((i=0; i<${#VERSIONS[@]}-1; i++)); do
    local from="${VERSIONS[$i]}"
    local to="${VERSIONS[$((i+1))]}"
    local out="${BASE_DIR}/values-report/values-keys-diff-${from}-${to}.txt"

    {
      echo "Values key diff ${from} -> ${to}"
      echo "=============================="
      echo
      echo "[Added keys]"
      comm -13 \
        "${BASE_DIR}/values-report/values-keys-${from}.txt" \
        "${BASE_DIR}/values-report/values-keys-${to}.txt" || true
      echo
      echo "[Removed keys]"
      comm -23 \
        "${BASE_DIR}/values-report/values-keys-${from}.txt" \
        "${BASE_DIR}/values-report/values-keys-${to}.txt" || true
      echo
      echo "[Full values.yaml diff]"
      diff -u \
        "${BASE_DIR}/${from}/${CHART_NAME}/values.yaml" \
        "${BASE_DIR}/${to}/${CHART_NAME}/values.yaml" || true
    } > "${out}"
  done

  echo "✅ Values reports generated"
}

pair_analysis() {
  echo "===== PAIR ANALYSIS MODE ====="

  for ((i=0; i<${#VERSIONS[@]}-1; i++)); do
    local from="${VERSIONS[$i]}"
    local to="${VERSIONS[$((i+1))]}"
    local out="${BASE_DIR}/analysis/analysis-${from}-${to}.txt"

    {
      echo "=================================================="
      echo "Emissary Helm Upgrade Analysis: ${from} -> ${to}"
      echo "=================================================="
      echo

      echo "[1] Chart metadata"
      echo "--- ${from}"
      grep -E '^(version:|appVersion:|kubeVersion:)' \
        "${BASE_DIR}/${from}/${CHART_NAME}/Chart.yaml" || true
      echo
      echo "--- ${to}"
      grep -E '^(version:|appVersion:|kubeVersion:)' \
        "${BASE_DIR}/${to}/${CHART_NAME}/Chart.yaml" || true
      echo

      echo "[2] Added/removed template and CRD files"
      echo "--- Added files"
      comm -13 \
        <(cd "${BASE_DIR}/${from}/${CHART_NAME}" && find templates crds -type f 2>/dev/null | sort) \
        <(cd "${BASE_DIR}/${to}/${CHART_NAME}" && find templates crds -type f 2>/dev/null | sort) || true
      echo
      echo "--- Removed files"
      comm -23 \
        <(cd "${BASE_DIR}/${from}/${CHART_NAME}" && find templates crds -type f 2>/dev/null | sort) \
        <(cd "${BASE_DIR}/${to}/${CHART_NAME}" && find templates crds -type f 2>/dev/null | sort) || true
      echo

      echo "[3] Image changes"
      echo "--- Removed images"
      comm -23 \
        "${BASE_DIR}/images/images-${from}.txt" \
        "${BASE_DIR}/images/images-${to}.txt" || true
      echo
      echo "--- Added images"
      comm -13 \
        "${BASE_DIR}/images/images-${from}.txt" \
        "${BASE_DIR}/images/images-${to}.txt" || true
      echo

      echo "[4] Values key changes"
      echo "--- Added values keys"
      comm -13 \
        "${BASE_DIR}/values-report/values-keys-${from}.txt" \
        "${BASE_DIR}/values-report/values-keys-${to}.txt" || true
      echo
      echo "--- Removed values keys"
      comm -23 \
        "${BASE_DIR}/values-report/values-keys-${from}.txt" \
        "${BASE_DIR}/values-report/values-keys-${to}.txt" || true
      echo

      echo "[5] Rendered manifest interesting diff lines"
      grep -E '^(---|\+\+\+|@@|[-+] *(apiVersion:|kind:|  name:|metadata:|spec:|image:|serviceAccountName:|replicas:|type:|port:|targetPort:|containerPort:|verbs:|resources:|limits:|requests:|secretName:))' \
        "${BASE_DIR}/rendered-diff/rendered-diff-${from}-${to}.txt" || true
      echo

      echo "[6] Raw diff file"
      echo "${BASE_DIR}/raw-diff/diff-${from}-${to}.txt"
      echo

      echo "[7] Rendered diff file"
      echo "${BASE_DIR}/rendered-diff/rendered-diff-${from}-${to}.txt"
      echo
    } > "${out}"

    echo "📝 created ${out}"
  done

  echo "✅ Pair analysis reports generated"
}

summary_report() {
  echo "===== SUMMARY REPORT MODE ====="

  local out="${BASE_DIR}/analysis/SUMMARY.txt"

  {
    echo "Emissary Helm Summary"
    echo "====================="
    echo
    echo "Chart: ${CHART}"
    echo "Base dir: ${BASE_DIR}"
    echo
    echo "Versions analyzed:"
    printf ' - %s\n' "${VERSIONS[@]}"
    echo
    echo "Artifacts:"
    echo " - raw diffs:        ${BASE_DIR}/raw-diff/"
    echo " - rendered yaml:    ${BASE_DIR}/rendered/"
    echo " - rendered diffs:   ${BASE_DIR}/rendered-diff/"
    echo " - images:           ${BASE_DIR}/images/"
    echo " - CRD report:       ${BASE_DIR}/crd-report/"
    echo " - values report:    ${BASE_DIR}/values-report/"
    echo " - pair analysis:    ${BASE_DIR}/analysis/"
    echo
    echo "Unique image list:"
    echo " - ${BASE_DIR}/images/all-images-unique.txt"
    echo
    echo "Per-upgrade sequence:"
    for ((i=0; i<${#VERSIONS[@]}-1; i++)); do
      echo " - ${VERSIONS[$i]} -> ${VERSIONS[$((i+1))]}"
    done
  } > "${out}"

  echo "✅ Summary generated: ${out}"
}

all() {
  ensure_tools
  prepare_dirs
  download
  raw_diff
  render_all
  rendered_diff
  extract_images
  crd_report
  values_key_report
  pair_analysis
  summary_report
}

usage() {
  cat <<EOF

Usage:
  ./emissary-upgrade-lab.sh download
  ./emissary-upgrade-lab.sh rawdiff
  ./emissary-upgrade-lab.sh render
  ./emissary-upgrade-lab.sh renderdiff
  ./emissary-upgrade-lab.sh images
  ./emissary-upgrade-lab.sh crd
  ./emissary-upgrade-lab.sh values
  ./emissary-upgrade-lab.sh analyze
  ./emissary-upgrade-lab.sh summary
  ./emissary-upgrade-lab.sh all

Output directories:
  ${BASE_DIR}/raw-diff/
  ${BASE_DIR}/rendered/
  ${BASE_DIR}/rendered-diff/
  ${BASE_DIR}/images/
  ${BASE_DIR}/crd-report/
  ${BASE_DIR}/values-report/
  ${BASE_DIR}/analysis/

EOF
}

case "${1:-}" in
  download)
    ensure_tools
    prepare_dirs
    download
    ;;
  rawdiff)
    ensure_tools
    prepare_dirs
    raw_diff
    ;;
  render)
    ensure_tools
    prepare_dirs
    render_all
    ;;
  renderdiff)
    ensure_tools
    prepare_dirs
    rendered_diff
    ;;
  images)
    ensure_tools
    prepare_dirs
    extract_images
    ;;
  crd)
    ensure_tools
    prepare_dirs
    crd_report
    ;;
  values)
    ensure_tools
    prepare_dirs
    values_key_report
    ;;
  analyze)
    ensure_tools
    prepare_dirs
    pair_analysis
    ;;
  summary)
    ensure_tools
    prepare_dirs
    summary_report
    ;;
  all)
    all
    ;;
  *)
    usage
    ;;
esac
