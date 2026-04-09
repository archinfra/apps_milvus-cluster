# apps_milvus-cluster

Milvus Cluster offline delivery repository for Kubernetes.

This repository follows the same delivery style used in the MySQL, Redis and MinIO repositories:

- multi-arch offline `.run` installers for `amd64` and `arm64`
- metadata-driven embedded image payloads
- explicit internal-registry image rendering during Helm install
- GitHub Actions build and GitHub Release publishing
- public upstream image pulls at build time, then retagged into `sealos.hub:5000/kube4/*` inside the offline package

The Milvus business defaults are kept explicit in the installer help:

- namespace: `milvus-system`
- release name: `milvus-cluster`
- mode: `cluster`
- message queue: `woodpecker`
- streaming: `true`
- storage class: `nfs`
- storage size hint: `500Gi`
- metrics: `enabled`
- ServiceMonitor: `enabled`

## Layout

- `build.sh`: build multi-arch `.run` installers
- `install.sh`: self-extracting offline installer template
- `images/image.json`: multi-arch image manifest
- `charts/milvus`: vendored Milvus Helm chart
- `.github/workflows/build-offline-installer.yml`: GitHub Actions build and release

## Local Build

Requirements:

- `bash`
- `docker`
- `python` or `python3`

Examples:

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

Artifacts are generated in `dist/`:

- `milvus-cluster-installer-amd64.run`
- `milvus-cluster-installer-amd64.run.sha256`
- `milvus-cluster-installer-arm64.run`
- `milvus-cluster-installer-arm64.run.sha256`

## Installer Usage

Show help:

```bash
./milvus-cluster-installer-amd64.run --help
./milvus-cluster-installer-amd64.run help
```

Install with the defaults:

```bash
./milvus-cluster-installer-amd64.run install -y
```

Install with Pulsar:

```bash
./milvus-cluster-installer-amd64.run install \
  --mq pulsar \
  --pulsar-replicas 5 \
  -y
```

Reuse images already present in the target registry:

```bash
./milvus-cluster-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

Show status:

```bash
./milvus-cluster-installer-amd64.run status -n milvus-system
```

Uninstall:

```bash
./milvus-cluster-installer-amd64.run uninstall -n milvus-system -y
```

## Monitoring

Monitoring is enabled by default in this repository:

- `metrics.enabled=true`
- `metrics.serviceMonitor.enabled=true`
- `metrics.serviceMonitor.additionalLabels.monitoring.archinfra.io/stack=default`

If the cluster does not contain the `ServiceMonitor` CRD, the installer warns and downgrades automatically.

## Image Sources

The offline payload now builds from public multi-arch upstream images for the default install path:

- `milvusdb/milvus:v2.6.9`
- `milvusdb/etcd:3.5.25-r1`
- `minio/minio:RELEASE.2024-12-18T13-15-44Z`
- `apachepulsar/pulsar:3.0.7`

`heaptrack` is intentionally not bundled in the offline payload because the upstream public image currently exposes `amd64` only. The chart keeps `heaptrack` disabled by default.

## GitHub Actions Release Flow

Push to `main`:

- build `amd64` and `arm64` installers
- upload installer artifacts

Push tag `v*`:

- build installers
- publish GitHub Release with `.run` and `.sha256`
