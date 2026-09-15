#!/usr/bin/env bash
# shellcheck shell=bash
#
# Archinfra Milvus delivery overlay.
# This file is injected into the generated .run installer immediately before
# main "$@". It intentionally reuses the proven legacy image/Helm plumbing while
# replacing user-facing delivery semantics for the 0.2.0 baseline.

APP_VERSION="0.2.0"
RESOURCE_PROFILE="standard"
COMPACT_MODE="false"

ENABLE_AUTH="true"
AUTH_SECRET="milvus-auth"
MILVUS_ROOT_PASSWORD=""
ROOT_PASSWORD_EXPLICIT="false"
AUTH_VALUES_FILE="${WORKDIR}/archinfra-auth-values.yaml"
DELIVERY_VALUES_FILE="${CHART_DIR}/archinfra-values.yaml"
HELP_TOPIC="overview"

MILVUS_STREAMINGNODE_REPLICAS="${MILVUS_STREAMINGNODE_REPLICAS:-1}"
MILVUS_STREAMINGNODE_REQUEST_CPU="${MILVUS_STREAMINGNODE_REQUEST_CPU:-500m}"
MILVUS_STREAMINGNODE_REQUEST_MEM="${MILVUS_STREAMINGNODE_REQUEST_MEM:-1Gi}"
MILVUS_STREAMINGNODE_LIMIT_CPU="${MILVUS_STREAMINGNODE_LIMIT_CPU:-2}"
MILVUS_STREAMINGNODE_LIMIT_MEM="${MILVUS_STREAMINGNODE_LIMIT_MEM:-4Gi}"

MILVUS_STANDALONE_REQUEST_CPU="${MILVUS_STANDALONE_REQUEST_CPU:-1}"
MILVUS_STANDALONE_REQUEST_MEM="${MILVUS_STANDALONE_REQUEST_MEM:-2Gi}"
MILVUS_STANDALONE_LIMIT_CPU="${MILVUS_STANDALONE_LIMIT_CPU:-2}"
MILVUS_STANDALONE_LIMIT_MEM="${MILVUS_STANDALONE_LIMIT_MEM:-8Gi}"

# Preserve the original implementation under private compatibility names.
eval "$(declare -f parse_args | sed '1s/^parse_args /legacy_parse_args /')"
eval "$(declare -f normalize_flags | sed '1s/^normalize_flags /legacy_normalize_flags /')"
eval "$(declare -f install_release | sed '1s/^install_release /legacy_install_release /')"
eval "$(declare -f uninstall_release | sed '1s/^uninstall_release /legacy_uninstall_release /')"
eval "$(declare -f show_status | sed '1s/^show_status /legacy_show_status /')"

show_help_overview() {
  local cmd="./$(program_name)"
  cat <<EOF
Milvus Cluster Offline Installer ${APP_VERSION}

Usage:
  ${cmd} <install|uninstall|status|help> [options] [-- <helm_args>]
  ${cmd} help <overview|install|params|examples>

Current delivery baseline:
  Milvus                 2.6.23
  Default mode           cluster
  Default MQ             woodpecker
  Authentication         ON
  Service                ClusterIP only
  Metrics                ON
  ServiceMonitor         ON when CRD exists
  PrometheusRule         ON when CRD exists
  Resource profile       standard

Resource profiles:
  lite                    Test/demo profile; compact replica topology
  standard                Default production delivery baseline
  large                   Higher query/write pressure and larger working set

Important:
  * Only lite / standard / large are accepted. Legacy low/mid/high aliases and
    --compact are intentionally rejected.
  * Embedded etcd and MinIO versions are frozen in this release and are not part
    of the 0.2.0 dependency upgrade.
  * New installations enable Milvus authentication and generate a root password
    into Secret/${AUTH_SECRET} unless --root-password is explicitly supplied.

Run `${cmd} help install` for the recommended standard command.
EOF
}

show_help_install() {
  local cmd="./$(program_name)"
  cat <<EOF
Recommended standard installation:

  ${cmd} install \
    --namespace milvus-system \
    --resource-profile standard \
    --storage-class ceph-rbd \
    --enable-auth \
    --enable-metrics \
    --enable-servicemonitor \
    --enable-prometheusrule \
    --mq woodpecker \
    --streaming true \
    --wait-timeout 15m \
    -y

Standard profile topology / per-pod limits:
  proxy          replicas=2   limit=1C/2Gi
  queryNode      replicas=2   limit=2C/8Gi
  dataNode       replicas=2   limit=2C/8Gi
  mixCoordinator replicas=1   limit=1C/2Gi
  streamingNode  replicas=1   limit=2C/4Gi
  etcd           replicas=3   image/version unchanged in this release
  MinIO          replicas=4   image/version unchanged in this release

Authentication:
  --enable-auth                      Default; required for standard delivery
  --disable-auth                     Explicit compatibility/testing escape hatch
  --auth-secret <name>               Default: ${AUTH_SECRET}
  --root-password <password>         New install: optional; random if omitted

Upgrade safety:
  Existing releases created before this baseline may not have Secret/${AUTH_SECRET}.
  For such releases, install refuses to guess the current root credential. Supply
  --root-password with the CURRENT root password, or temporarily use --disable-auth
  and complete credential migration deliberately.
EOF
}

show_help_params() {
  cat <<EOF
Core:
  -n, --namespace <ns>                 Default: ${NAMESPACE}
  --release-name <name>                Default: ${RELEASE_NAME}
  --mode cluster|standalone            Default: ${MODE}
  --mq woodpecker|pulsar               Default: ${MESSAGE_QUEUE}
  --streaming true|false               Default: ${STREAMING_ENABLED}
  --resource-profile <name>            lite|standard|large; default: standard
  --storage-class <name>               Default: ${STORAGE_CLASS}
  --wait-timeout <duration>            Default: ${WAIT_TIMEOUT}

Security:
  --enable-auth / --disable-auth
  --auth-secret <name>                 Default: ${AUTH_SECRET}
  --root-password <password>           Max 72 chars; never printed by installer

Monitoring:
  --enable-metrics / --disable-metrics
  --enable-servicemonitor / --disable-servicemonitor
  --enable-prometheusrule / --disable-prometheusrule
  --service-monitor-interval <value>   Default: ${SERVICE_MONITOR_INTERVAL}
  --service-monitor-scrape-timeout <v> Default: ${SERVICE_MONITOR_SCRAPE_TIMEOUT}

Images / registry:
  --registry <repo-prefix>             Default: ${REGISTRY_REPO}
  --registry-user <user>
  --registry-password <password>
  --skip-image-prepare

Replica overrides:
  --proxy-replicas <num>
  --querynode-replicas <num>
  --datanode-replicas <num>
  --indexnode-replicas <num>
  --mixcoord-replicas <num>
  --etcd-replicas <num>
  --minio-replicas <num>
  --pulsar-replicas <num>
  --zookeeper-replicas <num>
  --bookkeeper-replicas <num>

Storage sizing (dependency versions are unchanged):
  --etcd-storage-size <size>           Default: ${ETCD_STORAGE_SIZE}
  --minio-storage-size <size>          Default: ${MINIO_STORAGE_SIZE}
  --zookeeper-storage-size <size>      Default: ${ZOOKEEPER_STORAGE_SIZE}
  --bookkeeper-journal-size <size>     Default: ${BOOKKEEPER_JOURNAL_SIZE}
  --bookkeeper-ledger-size <size>      Default: ${BOOKKEEPER_LEDGER_SIZE}
EOF
}

show_help_examples() {
  local cmd="./$(program_name)"
  cat <<EOF
Examples:
  # Standard cluster
  ${cmd} install --resource-profile standard --storage-class ceph-rbd -y

  # Small test environment
  ${cmd} install --resource-profile lite --storage-class nfs -y

  # Larger Milvus worker sizing
  ${cmd} install --resource-profile large --storage-class ceph-rbd -y

  # Existing pre-0.2.0 release: explicitly provide the CURRENT root credential
  ${cmd} install --resource-profile standard --root-password '<CURRENT_PASSWORD>' -y

  # Optional Pulsar mode (Woodpecker remains the standard default)
  ${cmd} install --resource-profile standard --mq pulsar -y

  # Private registry already preloaded
  ${cmd} install --skip-image-prepare --registry harbor.example.com/kube4 -y

  # Retrieve generated root password
  kubectl get secret -n ${NAMESPACE} ${AUTH_SECRET} \
    -o jsonpath='{.data.root-password}' | base64 -d; echo
EOF
}

usage() {
  case "${HELP_TOPIC}" in
    overview) show_help_overview ;;
    install)  show_help_install ;;
    params)   show_help_params ;;
    examples) show_help_examples ;;
    *) die "Unknown help topic: ${HELP_TOPIC}" ;;
  esac
}

parse_args() {
  local passthrough=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      help)
        passthrough+=("help")
        if [[ $# -ge 2 ]]; then
          case "$2" in
            overview|install|params|examples)
              HELP_TOPIC="$2"
              shift 2
              continue
              ;;
          esac
        fi
        shift
        ;;
      --enable-auth)
        ENABLE_AUTH="true"
        shift
        ;;
      --disable-auth)
        ENABLE_AUTH="false"
        shift
        ;;
      --auth-secret)
        [[ $# -ge 2 ]] || die "--auth-secret requires a value"
        AUTH_SECRET="$2"
        shift 2
        ;;
      --root-password)
        [[ $# -ge 2 ]] || die "--root-password requires a value"
        MILVUS_ROOT_PASSWORD="$2"
        ROOT_PASSWORD_EXPLICIT="true"
        shift 2
        ;;
      --compact)
        die "--compact 已移除；请使用 --resource-profile lite"
        ;;
      --)
        passthrough+=("--")
        shift
        while [[ $# -gt 0 ]]; do
          passthrough+=("$1")
          shift
        done
        ;;
      *)
        passthrough+=("$1")
        shift
        ;;
    esac
  done

  legacy_parse_args "${passthrough[@]}"
}

apply_streaming_profile() {
  case "${RESOURCE_PROFILE}" in
    lite)
      MILVUS_STREAMINGNODE_REPLICAS="1"
      MILVUS_STREAMINGNODE_REQUEST_CPU="250m"
      MILVUS_STREAMINGNODE_REQUEST_MEM="512Mi"
      MILVUS_STREAMINGNODE_LIMIT_CPU="1"
      MILVUS_STREAMINGNODE_LIMIT_MEM="2Gi"
      MILVUS_STANDALONE_REQUEST_CPU="500m"
      MILVUS_STANDALONE_REQUEST_MEM="1Gi"
      MILVUS_STANDALONE_LIMIT_CPU="1"
      MILVUS_STANDALONE_LIMIT_MEM="2Gi"
      ;;
    standard)
      MILVUS_STREAMINGNODE_REPLICAS="1"
      MILVUS_STREAMINGNODE_REQUEST_CPU="500m"
      MILVUS_STREAMINGNODE_REQUEST_MEM="1Gi"
      MILVUS_STREAMINGNODE_LIMIT_CPU="2"
      MILVUS_STREAMINGNODE_LIMIT_MEM="4Gi"
      MILVUS_STANDALONE_REQUEST_CPU="1"
      MILVUS_STANDALONE_REQUEST_MEM="2Gi"
      MILVUS_STANDALONE_LIMIT_CPU="2"
      MILVUS_STANDALONE_LIMIT_MEM="8Gi"
      ;;
    large)
      MILVUS_STREAMINGNODE_REPLICAS="2"
      MILVUS_STREAMINGNODE_REQUEST_CPU="1"
      MILVUS_STREAMINGNODE_REQUEST_MEM="2Gi"
      MILVUS_STREAMINGNODE_LIMIT_CPU="4"
      MILVUS_STREAMINGNODE_LIMIT_MEM="8Gi"
      MILVUS_STANDALONE_REQUEST_CPU="2"
      MILVUS_STANDALONE_REQUEST_MEM="8Gi"
      MILVUS_STANDALONE_LIMIT_CPU="4"
      MILVUS_STANDALONE_LIMIT_MEM="16Gi"
      ;;
  esac
}

normalize_flags() {
  local canonical_profile="${RESOURCE_PROFILE,,}"

  case "${canonical_profile}" in
    lite|standard|large) ;;
    *) die "resource-profile 仅支持 lite|standard|large" ;;
  esac

  RESOURCE_PROFILE="${canonical_profile}"
  COMPACT_MODE="false"
  case "${canonical_profile}" in
    lite)
      RESOURCE_PROFILE="low"
      COMPACT_MODE="true"
      ;;
    standard)
      RESOURCE_PROFILE="mid"
      ;;
    large)
      RESOURCE_PROFILE="high"
      ;;
  esac

  legacy_normalize_flags

  case "${canonical_profile}" in
    lite) RESOURCE_PROFILE="lite" ;;
    standard) RESOURCE_PROFILE="standard" ;;
    large) RESOURCE_PROFILE="large" ;;
  esac

  # Large delivery keeps the existing dependency topology but adds a second
  # streaming worker. lite intentionally reuses the proven compact topology.
  apply_streaming_profile

  if [[ "${ENABLE_AUTH}" != "true" && "${ENABLE_AUTH}" != "false" ]]; then
    die "authentication switch must resolve to true or false"
  fi
}

generate_root_password() {
  # 192 bits of entropy represented as lowercase hexadecimal. Avoid shell/YAML
  # escaping problems while remaining far stronger than a human default.
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

validate_root_password() {
  local value="$1"
  [[ -n "${value}" ]] || die "Milvus root password must not be empty"
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || die "Milvus root password must be a single line"
  (( ${#value} <= 72 )) || die "Milvus root password must be <= 72 characters"
}

yaml_escape_double_quoted() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

prepare_auth_values() {
  ensure_namespace

  if [[ "${ENABLE_AUTH}" != "true" ]]; then
    cat >"${AUTH_VALUES_FILE}" <<'EOF'
extraConfigFiles:
  user.yaml: |+
    common:
      security:
        authorizationEnabled: false
EOF
    chmod 600 "${AUTH_VALUES_FILE}"
    warn "Milvus authentication is explicitly disabled"
    return 0
  fi

  local existing_password=""
  local release_exists="false"
  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    release_exists="true"
  fi

  if kubectl get secret -n "${NAMESPACE}" "${AUTH_SECRET}" >/dev/null 2>&1; then
    existing_password="$(kubectl get secret -n "${NAMESPACE}" "${AUTH_SECRET}" -o 'jsonpath={.data.root-password}' | base64 -d)"
  fi

  if [[ -n "${existing_password}" ]]; then
    if [[ "${ROOT_PASSWORD_EXPLICIT}" == "true" && "${MILVUS_ROOT_PASSWORD}" != "${existing_password}" ]]; then
      die "Secret/${AUTH_SECRET} 已存在且与 --root-password 不一致；普通 install 不执行 root 密码轮换"
    fi
    MILVUS_ROOT_PASSWORD="${existing_password}"
  elif [[ "${ROOT_PASSWORD_EXPLICIT}" == "true" ]]; then
    validate_root_password "${MILVUS_ROOT_PASSWORD}"
  elif [[ "${release_exists}" == "true" ]]; then
    die "检测到已有 Milvus release 但没有 Secret/${AUTH_SECRET}。为避免把现有 root 凭证猜错，请传 --root-password '<CURRENT_PASSWORD>'，或显式 --disable-auth 后先完成凭证迁移。"
  else
    MILVUS_ROOT_PASSWORD="$(generate_root_password)"
  fi

  validate_root_password "${MILVUS_ROOT_PASSWORD}"

  kubectl create secret generic "${AUTH_SECRET}" \
    -n "${NAMESPACE}" \
    --from-literal=root-password="${MILVUS_ROOT_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  local escaped_password
  escaped_password="$(yaml_escape_double_quoted "${MILVUS_ROOT_PASSWORD}")"
  cat >"${AUTH_VALUES_FILE}" <<EOF
extraConfigFiles:
  user.yaml: |+
    common:
      security:
        authorizationEnabled: true
        defaultRootPassword: "${escaped_password}"
EOF
  chmod 600 "${AUTH_VALUES_FILE}"
}

confirm() {
  [[ "${AUTO_YES}" == "true" ]] && return 0

  echo
  echo "Action: ${ACTION}"
  echo "Milvus: 2.6.23"
  echo "Namespace: ${NAMESPACE}"
  echo "Release: ${RELEASE_NAME}"
  echo "Mode: ${MODE}"
  echo "Message queue: ${MESSAGE_QUEUE}"
  echo "Streaming: ${STREAMING_ENABLED}"
  echo "Resource profile: ${RESOURCE_PROFILE}"
  echo "Authentication: ${ENABLE_AUTH}"
  echo "Auth Secret: ${AUTH_SECRET}"
  echo "Metrics: ${ENABLE_METRICS}"
  echo "ServiceMonitor: ${ENABLE_SERVICEMONITOR}"
  echo "StorageClass: ${STORAGE_CLASS}"
  echo "Registry: ${REGISTRY_REPO}"
  echo "Skip image prepare: ${SKIP_IMAGE_PREPARE}"
  echo
  read -r -p "Continue? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "Aborted"
}

install_release() {
  [[ -f "${DELIVERY_VALUES_FILE}" ]] || die "missing ${DELIVERY_VALUES_FILE}"
  prepare_auth_values

  local user_helm_args=("${HELM_ARGS[@]}")
  HELM_ARGS=(
    -f "${DELIVERY_VALUES_FILE}"
    -f "${AUTH_VALUES_FILE}"
    --set-string "streamingNode.replicas=${MILVUS_STREAMINGNODE_REPLICAS}"
    --set-string "streamingNode.resources.requests.cpu=${MILVUS_STREAMINGNODE_REQUEST_CPU}"
    --set-string "streamingNode.resources.requests.memory=${MILVUS_STREAMINGNODE_REQUEST_MEM}"
    --set-string "streamingNode.resources.limits.cpu=${MILVUS_STREAMINGNODE_LIMIT_CPU}"
    --set-string "streamingNode.resources.limits.memory=${MILVUS_STREAMINGNODE_LIMIT_MEM}"
    --set-string "standalone.resources.requests.cpu=${MILVUS_STANDALONE_REQUEST_CPU}"
    --set-string "standalone.resources.requests.memory=${MILVUS_STANDALONE_REQUEST_MEM}"
    --set-string "standalone.resources.limits.cpu=${MILVUS_STANDALONE_LIMIT_CPU}"
    --set-string "standalone.resources.limits.memory=${MILVUS_STANDALONE_LIMIT_MEM}"
  )
  HELM_ARGS+=("${user_helm_args[@]}")

  legacy_install_release
}

uninstall_release() {
  legacy_uninstall_release
  if kubectl get secret -n "${NAMESPACE}" "${AUTH_SECRET}" >/dev/null 2>&1; then
    warn "Secret/${AUTH_SECRET} 已保留，便于保留数据后的重装；确认不再需要时请手工删除"
  fi
}

show_status() {
  legacy_show_status
  echo
  section "Delivery Security"
  echo "Authentication default: enabled"
  if kubectl get secret -n "${NAMESPACE}" "${AUTH_SECRET}" >/dev/null 2>&1; then
    echo "Auth Secret: ${AUTH_SECRET} (present)"
  else
    echo "Auth Secret: ${AUTH_SECRET} (not found)"
  fi
}
