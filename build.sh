#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${ROOT_DIR}/.build-payload"
PAYLOAD_DIR="${TEMP_DIR}/payload"
PAYLOAD_FILE="${TEMP_DIR}/payload.tar.gz"
DIST_DIR="${ROOT_DIR}/dist"
IMAGES_DIR="${ROOT_DIR}/images"
IMAGE_JSON="${IMAGES_DIR}/image.json"
CHARTS_DIR="${ROOT_DIR}/charts"
INSTALLER_TEMPLATE="${ROOT_DIR}/install.sh"
INSTALLER_BASENAME="milvus-cluster-installer"

ARCH="amd64"
PLATFORM="linux/amd64"
BUILD_ALL_ARCH="false"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

cleanup() {
  rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--arch amd64|arm64|all]

Examples:
  ./build.sh --arch amd64
  ./build.sh --arch arm64
  ./build.sh --arch all
EOF
}

normalize_arch() {
  case "$1" in
    amd64|amd|x86_64)
      ARCH="amd64"
      PLATFORM="linux/amd64"
      BUILD_ALL_ARCH="false"
      ;;
    arm64|arm|aarch64)
      ARCH="arm64"
      PLATFORM="linux/arm64"
      BUILD_ALL_ARCH="false"
      ;;
    all)
      BUILD_ALL_ARCH="true"
      ;;
    *)
      die "Unsupported arch: $1"
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch)
        [[ $# -ge 2 ]] || die "--arch requires a value"
        normalize_arch "$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

check_prereqs() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || die "python or python3 is required"
  [[ -f "${INSTALLER_TEMPLATE}" ]] || die "missing install.sh"
  [[ -d "${CHARTS_DIR}/milvus" ]] || die "missing charts/milvus"
  [[ -f "${IMAGE_JSON}" ]] || die "missing images/image.json"
  grep -q '^__PAYLOAD_BELOW__$' "${INSTALLER_TEMPLATE}" || die "install.sh must contain __PAYLOAD_BELOW__ marker"
}

python_cmd() {
  if command -v python >/dev/null 2>&1; then
    printf 'python'
  else
    printf 'python3'
  fi
}

build_index_for_arch() {
  local arch="$1"
  local output="$2"
  "$(python_cmd)" - "${IMAGE_JSON}" "${arch}" > "${output}" <<'PY'
import json
import sys

path = sys.argv[1]
arch = sys.argv[2]

with open(path, "r", encoding="utf-8") as fh:
    items = json.load(fh)

matched = [item for item in items if item.get("arch") == arch]
if not matched:
    raise SystemExit(f"no image metadata for arch={arch}")

for item in matched:
    print("\t".join([
        item["tar"],
        item["pull"],
        item["tag"],
        item["platform"],
    ]))
PY
}

build_arch() {
  local arch="$1"
  local platform="$2"
  local arch_payload_dir="${PAYLOAD_DIR}/${arch}"
  local installer_name="${INSTALLER_BASENAME}-${arch}.run"
  local installer_path="${DIST_DIR}/${installer_name}"
  local image_index="${arch_payload_dir}/images/image-index.tsv"

  rm -rf "${arch_payload_dir}"
  mkdir -p "${arch_payload_dir}/images" "${arch_payload_dir}/charts"

  cp -R "${CHARTS_DIR}/milvus" "${arch_payload_dir}/charts/"
  cp "${IMAGE_JSON}" "${arch_payload_dir}/images/image.json"
  build_index_for_arch "${arch}" "${image_index}"

  while IFS=$'\t' read -r tar_name pull_ref target_ref img_platform; do
    [[ -n "${tar_name}" ]] || continue
    log "Pulling ${pull_ref} for ${img_platform}"
    docker pull --platform "${img_platform}" "${pull_ref}"
    docker tag "${pull_ref}" "${target_ref}"
    log "Saving ${target_ref} to ${tar_name}"
    docker save -o "${arch_payload_dir}/images/${tar_name}" "${target_ref}"
  done < "${image_index}"

  mkdir -p "${DIST_DIR}" "${TEMP_DIR}"
  (
    cd "${arch_payload_dir}"
    tar -czf "${PAYLOAD_FILE}" .
  )

  cat "${INSTALLER_TEMPLATE}" "${PAYLOAD_FILE}" > "${installer_path}"
  chmod +x "${installer_path}"
  sha256sum "${installer_path}" > "${installer_path}.sha256"

  success "Built ${installer_path}"
}

main() {
  parse_args "$@"
  check_prereqs
  rm -rf "${TEMP_DIR}"
  mkdir -p "${TEMP_DIR}" "${DIST_DIR}"

  if [[ "${BUILD_ALL_ARCH}" == "true" ]]; then
    build_arch "amd64" "linux/amd64"
    build_arch "arm64" "linux/arm64"
  else
    build_arch "${ARCH}" "${PLATFORM}"
  fi

  success "All requested installers have been built"
}

main "$@"
