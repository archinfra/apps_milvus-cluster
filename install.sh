#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="milvus-cluster"
APP_VERSION="0.1.6"
PACKAGE_PROFILE="integrated"
WORKDIR="/tmp/${APP_NAME}-installer"
CHART_DIR="${WORKDIR}/charts/milvus"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_INDEX="${IMAGE_DIR}/image-index.tsv"

ACTION="help"
RELEASE_NAME="milvus-cluster"
NAMESPACE="milvus-system"
MODE="cluster"
MESSAGE_QUEUE="woodpecker"
STREAMING_ENABLED="true"
STORAGE_CLASS="nfs"
STORAGE_SIZE="500Gi"
IMAGE_PULL_POLICY="IfNotPresent"
WAIT_TIMEOUT="15m"
REGISTRY_REPO="sealos.hub:5000/kube4"
REGISTRY_REPO_EXPLICIT="false"
REGISTRY_USER=""
REGISTRY_PASSWORD=""
SKIP_IMAGE_PREPARE="false"
ENABLE_METRICS="true"
ENABLE_SERVICEMONITOR="true"
ENABLE_PROMETHEUSRULE="true"
SERVICE_MONITOR_INTERVAL="30s"
SERVICE_MONITOR_SCRAPE_TIMEOUT="10s"
AUTO_YES="false"
COMPACT_MODE="false"
RESOURCE_PROFILE="mid"
APPLY_SERVICE_MONITOR="true"
APPLY_POD_MONITOR="true"
APPLY_PROMETHEUS_RULE="true"
HELM_ARGS=()
MINIO_MODE="distributed"

MILVUS_PROXY_REPLICAS="${MILVUS_PROXY_REPLICAS:-2}"
MILVUS_PROXY_REQUEST_CPU="${MILVUS_PROXY_REQUEST_CPU:-200m}"
MILVUS_PROXY_REQUEST_MEM="${MILVUS_PROXY_REQUEST_MEM:-512Mi}"
MILVUS_PROXY_LIMIT_CPU="${MILVUS_PROXY_LIMIT_CPU:-1000m}"
MILVUS_PROXY_LIMIT_MEM="${MILVUS_PROXY_LIMIT_MEM:-2Gi}"
MILVUS_QUERYNODE_REPLICAS="${MILVUS_QUERYNODE_REPLICAS:-2}"
MILVUS_QUERYNODE_REQUEST_CPU="${MILVUS_QUERYNODE_REQUEST_CPU:-500m}"
MILVUS_QUERYNODE_REQUEST_MEM="${MILVUS_QUERYNODE_REQUEST_MEM:-2Gi}"
MILVUS_QUERYNODE_LIMIT_CPU="${MILVUS_QUERYNODE_LIMIT_CPU:-2000m}"
MILVUS_QUERYNODE_LIMIT_MEM="${MILVUS_QUERYNODE_LIMIT_MEM:-8Gi}"
MILVUS_DATANODE_REPLICAS="${MILVUS_DATANODE_REPLICAS:-2}"
MILVUS_DATANODE_REQUEST_CPU="${MILVUS_DATANODE_REQUEST_CPU:-500m}"
MILVUS_DATANODE_REQUEST_MEM="${MILVUS_DATANODE_REQUEST_MEM:-2Gi}"
MILVUS_DATANODE_LIMIT_CPU="${MILVUS_DATANODE_LIMIT_CPU:-2000m}"
MILVUS_DATANODE_LIMIT_MEM="${MILVUS_DATANODE_LIMIT_MEM:-8Gi}"
MILVUS_INDEXNODE_REPLICAS="${MILVUS_INDEXNODE_REPLICAS:-1}"
MIX_COORDINATOR_REPLICAS="${MIX_COORDINATOR_REPLICAS:-1}"
MIX_COORDINATOR_REQUEST_CPU="${MIX_COORDINATOR_REQUEST_CPU:-200m}"
MIX_COORDINATOR_REQUEST_MEM="${MIX_COORDINATOR_REQUEST_MEM:-512Mi}"
MIX_COORDINATOR_LIMIT_CPU="${MIX_COORDINATOR_LIMIT_CPU:-1000m}"
MIX_COORDINATOR_LIMIT_MEM="${MIX_COORDINATOR_LIMIT_MEM:-2Gi}"

ETCD_REPLICAS="${ETCD_REPLICAS:-3}"
ETCD_REQUEST_CPU="${ETCD_REQUEST_CPU:-200m}"
ETCD_REQUEST_MEM="${ETCD_REQUEST_MEM:-512Mi}"
ETCD_LIMIT_CPU="${ETCD_LIMIT_CPU:-1000m}"
ETCD_LIMIT_MEM="${ETCD_LIMIT_MEM:-2Gi}"
MINIO_REPLICAS="${MINIO_REPLICAS:-4}"
MINIO_REQUEST_CPU="${MINIO_REQUEST_CPU:-200m}"
MINIO_REQUEST_MEM="${MINIO_REQUEST_MEM:-512Mi}"
MINIO_LIMIT_CPU="${MINIO_LIMIT_CPU:-1000m}"
MINIO_LIMIT_MEM="${MINIO_LIMIT_MEM:-2Gi}"
PULSAR_REPLICAS="${PULSAR_REPLICAS:-3}"
ZOOKEEPER_REPLICAS="${ZOOKEEPER_REPLICAS:-3}"
BOOKKEEPER_REPLICAS="${BOOKKEEPER_REPLICAS:-3}"

ETCD_STORAGE_SIZE="${ETCD_STORAGE_SIZE:-20Gi}"
MINIO_STORAGE_SIZE="${MINIO_STORAGE_SIZE:-100Gi}"
PULSAR_STORAGE_SIZE="${PULSAR_STORAGE_SIZE:-50Gi}"
ZOOKEEPER_STORAGE_SIZE="${ZOOKEEPER_STORAGE_SIZE:-20Gi}"
BOOKKEEPER_JOURNAL_SIZE="${BOOKKEEPER_JOURNAL_SIZE:-100Gi}"
BOOKKEEPER_LEDGER_SIZE="${BOOKKEEPER_LEDGER_SIZE:-200Gi}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

MILVUS_IMAGE_REF=""
ETCD_IMAGE_REF=""
MINIO_IMAGE_REF=""
PULSAR_IMAGE_REF=""

log() {
  echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

die() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}$*${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
}

program_name() {
  basename "$0"
}

usage() {
  local cmd="./$(program_name)"
  cat <<EOF
Usage:
  ${cmd} <install|uninstall|status|help> [options] [-- <helm_args>]
  ${cmd} -h|--help

Actions:
  install       Prepare images and install or upgrade Milvus
  uninstall     Uninstall the Milvus Helm release
  status        Show Helm release and Kubernetes resource status
  help          Show this message

Core options:
  -n, --namespace <ns>                 Namespace, default: ${NAMESPACE}
  --release-name <name>                Helm release name, default: ${RELEASE_NAME}
  --mode <mode>                        cluster|standalone, default: ${MODE}
  --mq <type>                          woodpecker|pulsar, default: ${MESSAGE_QUEUE}
  --streaming <bool>                   true|false, default: ${STREAMING_ENABLED}
  --storage-class <name>               StorageClass, default: ${STORAGE_CLASS}
  --storage-size <size>                Shared storage size hint, default: ${STORAGE_SIZE}
  --resource-profile <name>            Resource profile: low|mid|midd|high, default: ${RESOURCE_PROFILE}
  --wait-timeout <duration>            Helm wait timeout, default: ${WAIT_TIMEOUT}
  --image-pull-policy <policy>         Always|IfNotPresent|Never, default: ${IMAGE_PULL_POLICY}
  --registry <repo-prefix>             Target image repo prefix, default: ${REGISTRY_REPO}
  --registry-user <user>               Optional registry username
  --registry-password <password>       Optional registry password
  --skip-image-prepare                 Reuse images already present in the target registry
  --compact                            Single-node compact profile for test environments
  -y, --yes                            Skip confirmation

Monitoring:
  --enable-metrics                     Enable metrics, default: ${ENABLE_METRICS}
  --disable-metrics                    Disable metrics
  --enable-servicemonitor              Enable ServiceMonitor, default: ${ENABLE_SERVICEMONITOR}
  --disable-servicemonitor             Disable ServiceMonitor
  --enable-prometheusrule              Enable PrometheusRule, default: ${ENABLE_PROMETHEUSRULE}
  --disable-prometheusrule             Disable PrometheusRule
  --service-monitor-interval <value>   Default: ${SERVICE_MONITOR_INTERVAL}
  --service-monitor-scrape-timeout <v> Default: ${SERVICE_MONITOR_SCRAPE_TIMEOUT}

Replica sizing defaults:
  --proxy-replicas <num>               Default: ${MILVUS_PROXY_REPLICAS}
  --querynode-replicas <num>           Default: ${MILVUS_QUERYNODE_REPLICAS}
  --datanode-replicas <num>            Default: ${MILVUS_DATANODE_REPLICAS}
  --indexnode-replicas <num>           Default: ${MILVUS_INDEXNODE_REPLICAS}
  --mixcoord-replicas <num>            Default: ${MIX_COORDINATOR_REPLICAS}
  --etcd-replicas <num>                Default: ${ETCD_REPLICAS}
  --minio-replicas <num>               Default: ${MINIO_REPLICAS}
  --pulsar-replicas <num>              Default: ${PULSAR_REPLICAS}
  --zookeeper-replicas <num>           Default: ${ZOOKEEPER_REPLICAS}
  --bookkeeper-replicas <num>          Default: ${BOOKKEEPER_REPLICAS}

Storage defaults:
  --etcd-storage-size <size>           Default: ${ETCD_STORAGE_SIZE}
  --minio-storage-size <size>          Default: ${MINIO_STORAGE_SIZE}
  --pulsar-storage-size <size>         Default: ${PULSAR_STORAGE_SIZE}
  --zookeeper-storage-size <size>      Default: ${ZOOKEEPER_STORAGE_SIZE}
  --bookkeeper-journal-size <size>     Default: ${BOOKKEEPER_JOURNAL_SIZE}
  --bookkeeper-ledger-size <size>      Default: ${BOOKKEEPER_LEDGER_SIZE}

Environment-based resource tuning examples:
  MILVUS_PROXY_REQUEST_CPU=200m        Default env value
  MILVUS_PROXY_REQUEST_MEM=512Mi       Default env value
  MILVUS_PROXY_LIMIT_CPU=1000m         Default env value
  MILVUS_PROXY_LIMIT_MEM=2Gi           Default env value
  MILVUS_QUERYNODE_REQUEST_CPU=500m    Default env value
  MILVUS_QUERYNODE_REQUEST_MEM=2Gi     Default env value
  MILVUS_QUERYNODE_LIMIT_CPU=2000m     Default env value
  MILVUS_QUERYNODE_LIMIT_MEM=8Gi       Default env value

Examples:
  ${cmd} install -y
  ${cmd} install --resource-profile high -y
  ${cmd} install --compact --skip-image-prepare -y
  ${cmd} install --mode standalone --mq woodpecker -y
  ${cmd} install --mq pulsar --pulsar-replicas 5 --zookeeper-replicas 5 -y
  ${cmd} install --skip-image-prepare --registry sealos.hub:5000/kube4 -y
  ${cmd} status -n ${NAMESPACE}
  ${cmd} uninstall -n ${NAMESPACE} -y
EOF
}

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

parse_args() {
  if [[ $# -eq 0 ]]; then
    ACTION="help"
    return
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status|help)
        ACTION="$1"
        shift
        ;;
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      --release-name)
        RELEASE_NAME="$2"
        shift 2
        ;;
      --mode)
        MODE="$2"
        shift 2
        ;;
      --mq)
        MESSAGE_QUEUE="$2"
        shift 2
        ;;
      --streaming)
        STREAMING_ENABLED="$2"
        shift 2
        ;;
      --storage-class)
        STORAGE_CLASS="$2"
        shift 2
        ;;
      --storage-size)
        STORAGE_SIZE="$2"
        shift 2
        ;;
      --resource-profile)
        RESOURCE_PROFILE="$2"
        shift 2
        ;;
      --wait-timeout)
        WAIT_TIMEOUT="$2"
        shift 2
        ;;
      --image-pull-policy)
        IMAGE_PULL_POLICY="$2"
        shift 2
        ;;
      --registry)
        REGISTRY_REPO="$2"
        REGISTRY_REPO_EXPLICIT="true"
        shift 2
        ;;
      --registry-user)
        REGISTRY_USER="$2"
        shift 2
        ;;
      --registry-password)
        REGISTRY_PASSWORD="$2"
        shift 2
        ;;
      --skip-image-prepare)
        SKIP_IMAGE_PREPARE="true"
        shift
        ;;
      --compact)
        COMPACT_MODE="true"
        shift
        ;;
      --enable-metrics)
        ENABLE_METRICS="true"
        shift
        ;;
      --disable-metrics)
        ENABLE_METRICS="false"
        ENABLE_SERVICEMONITOR="false"
        shift
        ;;
      --enable-servicemonitor)
        ENABLE_SERVICEMONITOR="true"
        ENABLE_METRICS="true"
        shift
        ;;
      --disable-servicemonitor)
        ENABLE_SERVICEMONITOR="false"
        shift
        ;;
      --enable-prometheusrule)
        ENABLE_PROMETHEUSRULE="true"
        shift
        ;;
      --disable-prometheusrule)
        ENABLE_PROMETHEUSRULE="false"
        shift
        ;;
      --service-monitor-interval)
        SERVICE_MONITOR_INTERVAL="$2"
        shift 2
        ;;
      --service-monitor-scrape-timeout)
        SERVICE_MONITOR_SCRAPE_TIMEOUT="$2"
        shift 2
        ;;
      --proxy-replicas)
        MILVUS_PROXY_REPLICAS="$2"
        shift 2
        ;;
      --querynode-replicas)
        MILVUS_QUERYNODE_REPLICAS="$2"
        shift 2
        ;;
      --datanode-replicas)
        MILVUS_DATANODE_REPLICAS="$2"
        shift 2
        ;;
      --indexnode-replicas)
        MILVUS_INDEXNODE_REPLICAS="$2"
        shift 2
        ;;
      --mixcoord-replicas)
        MIX_COORDINATOR_REPLICAS="$2"
        shift 2
        ;;
      --etcd-replicas)
        ETCD_REPLICAS="$2"
        shift 2
        ;;
      --minio-replicas)
        MINIO_REPLICAS="$2"
        shift 2
        ;;
      --pulsar-replicas)
        PULSAR_REPLICAS="$2"
        shift 2
        ;;
      --zookeeper-replicas)
        ZOOKEEPER_REPLICAS="$2"
        shift 2
        ;;
      --bookkeeper-replicas)
        BOOKKEEPER_REPLICAS="$2"
        shift 2
        ;;
      --etcd-storage-size)
        ETCD_STORAGE_SIZE="$2"
        shift 2
        ;;
      --minio-storage-size)
        MINIO_STORAGE_SIZE="$2"
        shift 2
        ;;
      --pulsar-storage-size)
        PULSAR_STORAGE_SIZE="$2"
        shift 2
        ;;
      --zookeeper-storage-size)
        ZOOKEEPER_STORAGE_SIZE="$2"
        shift 2
        ;;
      --bookkeeper-journal-size)
        BOOKKEEPER_JOURNAL_SIZE="$2"
        shift 2
        ;;
      --bookkeeper-ledger-size)
        BOOKKEEPER_LEDGER_SIZE="$2"
        shift 2
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          HELM_ARGS+=("$1")
          shift
        done
        ;;
      -y|--yes)
        AUTO_YES="true"
        shift
        ;;
      -h|--help)
        ACTION="help"
        shift
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

normalize_flags() {
  case "${MODE}" in
    cluster|standalone)
      ;;
    *)
      die "Unsupported mode: ${MODE}"
      ;;
  esac

  case "${MESSAGE_QUEUE}" in
    woodpecker|pulsar)
      ;;
    *)
      die "Unsupported mq type: ${MESSAGE_QUEUE}"
      ;;
  esac

  case "${STREAMING_ENABLED}" in
    true|false)
      ;;
    *)
      die "--streaming must be true or false"
      ;;
  esac

  if [[ "${ENABLE_SERVICEMONITOR}" == "true" ]]; then
    ENABLE_METRICS="true"
  fi

  case "${RESOURCE_PROFILE,,}" in
    low)
      RESOURCE_PROFILE="low"
      ;;
    mid|midd|middle|medium)
      RESOURCE_PROFILE="mid"
      ;;
    high)
      RESOURCE_PROFILE="high"
      ;;
    *)
      die "Unsupported resource profile: ${RESOURCE_PROFILE}"
      ;;
  esac

  apply_resource_if_default() {
    local name="$1"
    local expected="$2"
    local value="$3"
    if [[ "${!name}" == "${expected}" ]]; then
      printf -v "${name}" '%s' "${value}"
    fi
  }

  case "${RESOURCE_PROFILE}" in
    low)
      apply_resource_if_default MILVUS_PROXY_REQUEST_CPU 200m 100m
      apply_resource_if_default MILVUS_PROXY_REQUEST_MEM 512Mi 256Mi
      apply_resource_if_default MILVUS_PROXY_LIMIT_CPU 1000m 500m
      apply_resource_if_default MILVUS_PROXY_LIMIT_MEM 2Gi 1Gi
      apply_resource_if_default MILVUS_QUERYNODE_REQUEST_CPU 500m 250m
      apply_resource_if_default MILVUS_QUERYNODE_REQUEST_MEM 2Gi 1Gi
      apply_resource_if_default MILVUS_QUERYNODE_LIMIT_CPU 2000m 1000m
      apply_resource_if_default MILVUS_QUERYNODE_LIMIT_MEM 8Gi 4Gi
      apply_resource_if_default MILVUS_DATANODE_REQUEST_CPU 500m 250m
      apply_resource_if_default MILVUS_DATANODE_REQUEST_MEM 2Gi 1Gi
      apply_resource_if_default MILVUS_DATANODE_LIMIT_CPU 2000m 1000m
      apply_resource_if_default MILVUS_DATANODE_LIMIT_MEM 8Gi 4Gi
      apply_resource_if_default MIX_COORDINATOR_REQUEST_CPU 200m 100m
      apply_resource_if_default MIX_COORDINATOR_REQUEST_MEM 512Mi 256Mi
      apply_resource_if_default MIX_COORDINATOR_LIMIT_CPU 1000m 500m
      apply_resource_if_default MIX_COORDINATOR_LIMIT_MEM 2Gi 1Gi
      apply_resource_if_default ETCD_REQUEST_CPU 200m 100m
      apply_resource_if_default ETCD_REQUEST_MEM 512Mi 256Mi
      apply_resource_if_default ETCD_LIMIT_CPU 1000m 500m
      apply_resource_if_default ETCD_LIMIT_MEM 2Gi 1Gi
      apply_resource_if_default MINIO_REQUEST_CPU 200m 100m
      apply_resource_if_default MINIO_REQUEST_MEM 512Mi 256Mi
      apply_resource_if_default MINIO_LIMIT_CPU 1000m 500m
      apply_resource_if_default MINIO_LIMIT_MEM 2Gi 1Gi
      ;;
    high)
      apply_resource_if_default MILVUS_PROXY_REQUEST_CPU 200m 500m
      apply_resource_if_default MILVUS_PROXY_REQUEST_MEM 512Mi 1Gi
      apply_resource_if_default MILVUS_PROXY_LIMIT_CPU 1000m 2
      apply_resource_if_default MILVUS_PROXY_LIMIT_MEM 2Gi 4Gi
      apply_resource_if_default MILVUS_QUERYNODE_REQUEST_CPU 500m 1
      apply_resource_if_default MILVUS_QUERYNODE_REQUEST_MEM 2Gi 4Gi
      apply_resource_if_default MILVUS_QUERYNODE_LIMIT_CPU 2000m 4
      apply_resource_if_default MILVUS_QUERYNODE_LIMIT_MEM 8Gi 12Gi
      apply_resource_if_default MILVUS_DATANODE_REQUEST_CPU 500m 1
      apply_resource_if_default MILVUS_DATANODE_REQUEST_MEM 2Gi 4Gi
      apply_resource_if_default MILVUS_DATANODE_LIMIT_CPU 2000m 4
      apply_resource_if_default MILVUS_DATANODE_LIMIT_MEM 8Gi 12Gi
      apply_resource_if_default MIX_COORDINATOR_REQUEST_CPU 200m 500m
      apply_resource_if_default MIX_COORDINATOR_REQUEST_MEM 512Mi 1Gi
      apply_resource_if_default MIX_COORDINATOR_LIMIT_CPU 1000m 2
      apply_resource_if_default MIX_COORDINATOR_LIMIT_MEM 2Gi 4Gi
      apply_resource_if_default ETCD_REQUEST_CPU 200m 500m
      apply_resource_if_default ETCD_REQUEST_MEM 512Mi 1Gi
      apply_resource_if_default ETCD_LIMIT_CPU 1000m 2
      apply_resource_if_default ETCD_LIMIT_MEM 2Gi 4Gi
      apply_resource_if_default MINIO_REQUEST_CPU 200m 500m
      apply_resource_if_default MINIO_REQUEST_MEM 512Mi 1Gi
      apply_resource_if_default MINIO_LIMIT_CPU 1000m 2
      apply_resource_if_default MINIO_LIMIT_MEM 2Gi 4Gi
      ;;
  esac

  APPLY_SERVICE_MONITOR="${ENABLE_SERVICEMONITOR}"
  APPLY_POD_MONITOR="${ENABLE_SERVICEMONITOR}"

  if [[ "${COMPACT_MODE}" == "true" ]]; then
    MILVUS_PROXY_REPLICAS="1"
    MILVUS_QUERYNODE_REPLICAS="1"
    MILVUS_DATANODE_REPLICAS="1"
    MILVUS_INDEXNODE_REPLICAS="1"
    MIX_COORDINATOR_REPLICAS="1"
    ETCD_REPLICAS="1"
    MINIO_REPLICAS="1"
    MINIO_MODE="standalone"
    PULSAR_REPLICAS="1"
    ZOOKEEPER_REPLICAS="1"
    BOOKKEEPER_REPLICAS="1"
  fi
}

check_deps() {
  command -v helm >/dev/null 2>&1 || die "helm is required"
  command -v kubectl >/dev/null 2>&1 || die "kubectl is required"

  if [[ "${ACTION}" == "install" && "${SKIP_IMAGE_PREPARE}" != "true" ]]; then
    command -v docker >/dev/null 2>&1 || die "docker is required unless --skip-image-prepare is used"
  fi
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return 0

  echo
  echo "Action: ${ACTION}"
  echo "Namespace: ${NAMESPACE}"
  echo "Release: ${RELEASE_NAME}"
  echo "Mode: ${MODE}"
  echo "Message queue: ${MESSAGE_QUEUE}"
  echo "Streaming: ${STREAMING_ENABLED}"
  echo "Resource profile: ${RESOURCE_PROFILE}"
  echo "Metrics: ${ENABLE_METRICS}"
  echo "ServiceMonitor: ${ENABLE_SERVICEMONITOR}"
  echo "Compact mode: ${COMPACT_MODE}"
  echo "StorageClass: ${STORAGE_CLASS}"
  echo "Registry: ${REGISTRY_REPO}"
  echo "Skip image prepare: ${SKIP_IMAGE_PREPARE}"
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "Aborted"
}

payload_start_offset() {
  local marker_line payload_offset skip_bytes byte_hex
  marker_line="$(awk '/^__PAYLOAD_BELOW__$/ { print NR; exit }' "$0")"
  [[ -n "${marker_line}" ]] || return 1
  payload_offset="$(( $(head -n "${marker_line}" "$0" | wc -c | tr -d ' ') + 1 ))"

  skip_bytes=0
  while :; do
    byte_hex="$(dd if="$0" bs=1 skip="$((payload_offset + skip_bytes - 1))" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "${byte_hex}" in
      0a|0d)
        skip_bytes=$((skip_bytes + 1))
        ;;
      "")
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  printf '%s' "$((payload_offset + skip_bytes))"
}

extract_payload() {
  local offset
  section "Extract Payload"
  rm -rf "${WORKDIR}"
  mkdir -p "${IMAGE_DIR}" "${WORKDIR}/charts"

  offset="$(payload_start_offset)" || die "failed to find payload marker"
  tail -c +"${offset}" "$0" | tar -xzf - -C "${WORKDIR}" || die "failed to extract payload"

  [[ -d "${CHART_DIR}" ]] || die "missing charts/milvus in payload"
  [[ -f "${IMAGE_INDEX}" ]] || die "missing image index in payload"
}

target_registry_host() {
  local image_ref="$1"
  local first_segment="${image_ref%%/*}"
  if [[ "${image_ref}" == */* && ( "${first_segment}" == *.* || "${first_segment}" == *:* || "${first_segment}" == "localhost" ) ]]; then
    printf '%s\n' "${first_segment}"
  fi
}

target_ref_from_default() {
  local default_ref="$1"
  local suffix="${default_ref##*/}"
  printf '%s/%s\n' "${REGISTRY_REPO}" "${suffix}"
}

docker_login_if_needed() {
  local registry_host="$1"
  [[ -n "${registry_host}" ]] || return 0
  [[ -n "${REGISTRY_USER}" ]] || return 0
  [[ -n "${REGISTRY_PASSWORD}" ]] || return 0
  log "logging into registry ${registry_host}"
  printf '%s' "${REGISTRY_PASSWORD}" | docker login "${registry_host}" --username "${REGISTRY_USER}" --password-stdin >/dev/null
}

load_image_metadata() {
  local registry_host
  while IFS=$'\t' read -r tar_name _pull_ref default_target_ref _platform; do
    [[ -n "${tar_name}" ]] || continue
    local target_ref
    target_ref="$(target_ref_from_default "${default_target_ref}")"
    case "${tar_name}" in
      milvus-*.tar)
        MILVUS_IMAGE_REF="${target_ref}"
        ;;
      etcd-*.tar)
        ETCD_IMAGE_REF="${target_ref}"
        ;;
      minio-*.tar)
        MINIO_IMAGE_REF="${target_ref}"
        ;;
      pulsar-*.tar)
        PULSAR_IMAGE_REF="${target_ref}"
        ;;
    esac
  done < "${IMAGE_INDEX}"

  [[ -n "${MILVUS_IMAGE_REF}" ]] || die "failed to resolve Milvus image"
  [[ -n "${ETCD_IMAGE_REF}" ]] || die "failed to resolve etcd image"
  [[ -n "${MINIO_IMAGE_REF}" ]] || die "failed to resolve MinIO image"
  [[ -n "${PULSAR_IMAGE_REF}" ]] || die "failed to resolve Pulsar image"

  registry_host="$(target_registry_host "${MILVUS_IMAGE_REF}")"
  docker_login_if_needed "${registry_host}"
}

check_service_monitor_support() {
  if [[ "${ENABLE_SERVICEMONITOR}" != "true" ]]; then
    APPLY_SERVICE_MONITOR="false"
    APPLY_POD_MONITOR="false"
  fi

  if [[ "${ENABLE_PROMETHEUSRULE}" != "true" ]]; then
    APPLY_PROMETHEUSRULE="false"
  fi

  if [[ "${ENABLE_SERVICEMONITOR}" != "true" ]]; then
    return 0
  fi

  if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    warn "ServiceMonitor CRD not found, disabling ServiceMonitor"
    APPLY_SERVICE_MONITOR="false"
  fi

  if ! kubectl get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1; then
    warn "PodMonitor CRD not found, disabling PodMonitor"
    APPLY_POD_MONITOR="false"
  fi

  if ! kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
    warn "PrometheusRule CRD not found, disabling PrometheusRule"
    APPLY_PROMETHEUSRULE="false"
  fi
}

prepare_images() {
  if [[ "${SKIP_IMAGE_PREPARE}" == "true" ]]; then
    log "skipping image preparation because --skip-image-prepare was requested"
    return 0
  fi

  while IFS=$'\t' read -r tar_name _pull_ref default_target_ref _platform; do
    [[ -n "${tar_name}" ]] || continue
    local tar_path="${IMAGE_DIR}/${tar_name}"
    local target_ref
    target_ref="$(target_ref_from_default "${default_target_ref}")"
    [[ -f "${tar_path}" ]] || die "missing image archive ${tar_name}"
    log "loading ${tar_name}"
    docker load -i "${tar_path}" >/dev/null
    if ! docker image inspect "${target_ref}" >/dev/null 2>&1; then
      local loaded_ref="${default_target_ref}"
      docker tag "${loaded_ref}" "${target_ref}"
    fi
    log "pushing ${target_ref}"
    docker push "${target_ref}" >/dev/null
  done < "${IMAGE_INDEX}"
}

ensure_namespace() {
  kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}" >/dev/null
}

image_repo() {
  local ref="$1"
  printf '%s\n' "${ref%:*}"
}

image_tag() {
  local ref="$1"
  printf '%s\n' "${ref##*:}"
}

preview_command() {
  printf '%q ' "$@"
  echo
}

install_release() {
  local helm_cmd=()
  local use_cluster="true"
  local standalone_enabled="false"

  if [[ "${MODE}" == "standalone" ]]; then
    use_cluster="false"
    standalone_enabled="true"
  fi

  helm_cmd=(
    helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}"
    -n "${NAMESPACE}"
    --create-namespace
    --wait
    --timeout "${WAIT_TIMEOUT}"
    --set "cluster.enabled=${use_cluster}"
    --set "standalone.enabled=${standalone_enabled}"
    --set "streaming.enabled=${STREAMING_ENABLED}"
    --set-string "standalone.messageQueue=${MESSAGE_QUEUE}"
    --set "woodpecker.enabled=$([[ "${MESSAGE_QUEUE}" == "woodpecker" ]] && echo true || echo false)"
    --set "pulsar.enabled=false"
    --set "pulsarv3.enabled=$([[ "${MESSAGE_QUEUE}" == "pulsar" ]] && echo true || echo false)"
    --set-string "service.type=ClusterIP"
    --set-string "image.all.repository=$(image_repo "${MILVUS_IMAGE_REF}")"
    --set-string "image.all.tag=$(image_tag "${MILVUS_IMAGE_REF}")"
    --set-string "image.all.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "etcd.image.repository=$(image_repo "${ETCD_IMAGE_REF}")"
    --set-string "etcd.image.tag=$(image_tag "${ETCD_IMAGE_REF}")"
    --set-string "etcd.image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "minio.image.repository=$(image_repo "${MINIO_IMAGE_REF}")"
    --set-string "minio.image.tag=$(image_tag "${MINIO_IMAGE_REF}")"
    --set-string "minio.image.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "pulsarv3.images.zookeeper.repository=$(image_repo "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.zookeeper.tag=$(image_tag "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.zookeeper.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "pulsarv3.images.bookie.repository=$(image_repo "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.bookie.tag=$(image_tag "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.bookie.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "pulsarv3.images.autorecovery.repository=$(image_repo "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.autorecovery.tag=$(image_tag "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.autorecovery.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "pulsarv3.images.broker.repository=$(image_repo "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.broker.tag=$(image_tag "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.broker.pullPolicy=${IMAGE_PULL_POLICY}"
    --set-string "pulsarv3.images.proxy.repository=$(image_repo "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.proxy.tag=$(image_tag "${PULSAR_IMAGE_REF}")"
    --set-string "pulsarv3.images.proxy.pullPolicy=${IMAGE_PULL_POLICY}"
    --set "metrics.enabled=${ENABLE_METRICS}"
    --set "metrics.serviceMonitor.enabled=${APPLY_SERVICE_MONITOR}"
    --set "metrics.prometheusRule.enabled=${APPLY_PROMETHEUSRULE}"
    --set-string "metrics.serviceMonitor.interval=${SERVICE_MONITOR_INTERVAL}"
    --set-string "metrics.serviceMonitor.scrapeTimeout=${SERVICE_MONITOR_SCRAPE_TIMEOUT}"
    --set-string "metrics.serviceMonitor.additionalLabels.monitoring\\.archinfra\\.io/stack=default"
    --set-string "metrics.prometheusRule.additionalLabels.monitoring\\.archinfra\\.io/stack=default"
    --set "etcd.metrics.enabled=${ENABLE_METRICS}"
    --set "etcd.metrics.podMonitor.enabled=${APPLY_POD_MONITOR}"
    --set-string "etcd.metrics.podMonitor.interval=${SERVICE_MONITOR_INTERVAL}"
    --set-string "etcd.metrics.podMonitor.scrapeTimeout=${SERVICE_MONITOR_SCRAPE_TIMEOUT}"
    --set-string "etcd.metrics.podMonitor.additionalLabels.monitoring\\.archinfra\\.io/stack=default"
    --set-string "proxy.replicas=${MILVUS_PROXY_REPLICAS}"
    --set-string "proxy.resources.requests.cpu=${MILVUS_PROXY_REQUEST_CPU}"
    --set-string "proxy.resources.requests.memory=${MILVUS_PROXY_REQUEST_MEM}"
    --set-string "proxy.resources.limits.cpu=${MILVUS_PROXY_LIMIT_CPU}"
    --set-string "proxy.resources.limits.memory=${MILVUS_PROXY_LIMIT_MEM}"
    --set-string "queryNode.replicas=${MILVUS_QUERYNODE_REPLICAS}"
    --set-string "queryNode.resources.requests.cpu=${MILVUS_QUERYNODE_REQUEST_CPU}"
    --set-string "queryNode.resources.requests.memory=${MILVUS_QUERYNODE_REQUEST_MEM}"
    --set-string "queryNode.resources.limits.cpu=${MILVUS_QUERYNODE_LIMIT_CPU}"
    --set-string "queryNode.resources.limits.memory=${MILVUS_QUERYNODE_LIMIT_MEM}"
    --set-string "dataNode.replicas=${MILVUS_DATANODE_REPLICAS}"
    --set-string "dataNode.resources.requests.cpu=${MILVUS_DATANODE_REQUEST_CPU}"
    --set-string "dataNode.resources.requests.memory=${MILVUS_DATANODE_REQUEST_MEM}"
    --set-string "dataNode.resources.limits.cpu=${MILVUS_DATANODE_LIMIT_CPU}"
    --set-string "dataNode.resources.limits.memory=${MILVUS_DATANODE_LIMIT_MEM}"
    --set-string "indexNode.replicas=${MILVUS_INDEXNODE_REPLICAS}"
    --set-string "mixCoordinator.replicas=${MIX_COORDINATOR_REPLICAS}"
    --set-string "mixCoordinator.resources.requests.cpu=${MIX_COORDINATOR_REQUEST_CPU}"
    --set-string "mixCoordinator.resources.requests.memory=${MIX_COORDINATOR_REQUEST_MEM}"
    --set-string "mixCoordinator.resources.limits.cpu=${MIX_COORDINATOR_LIMIT_CPU}"
    --set-string "mixCoordinator.resources.limits.memory=${MIX_COORDINATOR_LIMIT_MEM}"
    --set "etcd.enabled=true"
    --set-string "etcd.replicaCount=${ETCD_REPLICAS}"
    --set "etcd.persistence.enabled=true"
    --set-string "etcd.persistence.storageClass=${STORAGE_CLASS}"
    --set-string "etcd.persistence.size=${ETCD_STORAGE_SIZE}"
    --set-string "etcd.resources.requests.cpu=${ETCD_REQUEST_CPU}"
    --set-string "etcd.resources.requests.memory=${ETCD_REQUEST_MEM}"
    --set-string "etcd.resources.limits.cpu=${ETCD_LIMIT_CPU}"
    --set-string "etcd.resources.limits.memory=${ETCD_LIMIT_MEM}"
    --set "minio.enabled=true"
    --set-string "minio.mode=${MINIO_MODE}"
    --set-string "minio.replicas=${MINIO_REPLICAS}"
    --set "minio.metrics.serviceMonitor.enabled=${APPLY_SERVICE_MONITOR}"
    --set-string "minio.metrics.serviceMonitor.interval=${SERVICE_MONITOR_INTERVAL}"
    --set-string "minio.metrics.serviceMonitor.scrapeTimeout=${SERVICE_MONITOR_SCRAPE_TIMEOUT}"
    --set-string "minio.metrics.serviceMonitor.additionalLabels.monitoring\\.archinfra\\.io/stack=default"
    --set "minio.persistence.enabled=true"
    --set-string "minio.persistence.storageClass=${STORAGE_CLASS}"
    --set-string "minio.persistence.size=${MINIO_STORAGE_SIZE}"
    --set-string "minio.resources.requests.cpu=${MINIO_REQUEST_CPU}"
    --set-string "minio.resources.requests.memory=${MINIO_REQUEST_MEM}"
    --set-string "minio.resources.limits.cpu=${MINIO_LIMIT_CPU}"
    --set-string "minio.resources.limits.memory=${MINIO_LIMIT_MEM}"
    --set-string "pulsarv3.zookeeper.replicaCount=${ZOOKEEPER_REPLICAS}"
    --set-string "pulsarv3.zookeeper.volumes.data.size=${ZOOKEEPER_STORAGE_SIZE}"
    --set-string "pulsarv3.bookkeeper.replicaCount=${BOOKKEEPER_REPLICAS}"
    --set-string "pulsarv3.bookkeeper.volumes.journal.size=${BOOKKEEPER_JOURNAL_SIZE}"
    --set-string "pulsarv3.bookkeeper.volumes.ledgers.size=${BOOKKEEPER_LEDGER_SIZE}"
    --set-string "pulsarv3.broker.replicaCount=${PULSAR_REPLICAS}"
  )

  if [[ "${MESSAGE_QUEUE}" == "pulsar" ]]; then
    helm_cmd+=(
      --set "pulsarv3.components.zookeeper=true"
      --set "pulsarv3.components.bookkeeper=true"
      --set "pulsarv3.components.autorecovery=true"
      --set "pulsarv3.components.broker=true"
      --set "pulsarv3.components.proxy=true"
    )
  fi

  if [[ "${#HELM_ARGS[@]}" -gt 0 ]]; then
    helm_cmd+=("${HELM_ARGS[@]}")
  fi

  section "Helm Command Preview"
  preview_command "${helm_cmd[@]}"

  ensure_namespace
  "${helm_cmd[@]}"
  success "Milvus release ${RELEASE_NAME} is ready"
}

show_post_install_info() {
  section "Milvus Status"
  kubectl get pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor -n "${NAMESPACE}" 2>/dev/null | awk 'NR==1 || $1 ~ /^'"${RELEASE_NAME}"'(-|$)/' || true
  fi

  if kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get prometheusrule -n "${NAMESPACE}" 2>/dev/null | awk 'NR==1 || $1 ~ /^'"${RELEASE_NAME}"'(-|$)/' || true
  fi

  if kubectl get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get podmonitor -n "${NAMESPACE}" 2>/dev/null | awk 'NR==1 || $1 ~ /^'"${RELEASE_NAME}"'(-|$)/' || true
  fi
}

uninstall_release() {
  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
    success "Release ${RELEASE_NAME} uninstalled"
  else
    warn "Helm release ${RELEASE_NAME} not found in namespace ${NAMESPACE}"
  fi
}

show_status() {
  section "Helm Status"
  helm status "${RELEASE_NAME}" -n "${NAMESPACE}" || warn "Release ${RELEASE_NAME} not found"

  section "Kubernetes Resources"
  kubectl get pods,svc,pvc -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" || true

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get servicemonitor -n "${NAMESPACE}" 2>/dev/null | awk 'NR==1 || $1 ~ /^'"${RELEASE_NAME}"'(-|$)/' || true
  fi

  if kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get prometheusrule -n "${NAMESPACE}" 2>/dev/null | awk 'NR==1 || $1 ~ /^'"${RELEASE_NAME}"'(-|$)/' || true
  fi

  if kubectl get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1; then
    echo
    kubectl get podmonitor -n "${NAMESPACE}" 2>/dev/null | awk 'NR==1 || $1 ~ /^'"${RELEASE_NAME}"'(-|$)/' || true
  fi
}

main() {
  parse_args "$@"
  normalize_flags

  case "${ACTION}" in
    help)
      usage
      ;;
    install)
      check_deps
      confirm
      extract_payload
      load_image_metadata
      check_service_monitor_support
      prepare_images
      install_release
      show_post_install_info
      ;;
    uninstall)
      check_deps
      confirm
      uninstall_release
      ;;
    status)
      check_deps
      show_status
      ;;
    *)
      die "Unsupported action: ${ACTION}"
      ;;
  esac
}

main "$@"
exit 0

__PAYLOAD_BELOW__
