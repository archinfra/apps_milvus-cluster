# apps_milvus-cluster

Milvus 集群离线交付仓库。

这个仓库不是单纯放一个 Helm chart，而是把“镜像准备 + Helm 安装 + 监控接入 + 离线交付”一起打成了 `.run` 安装包，方便在内网、半离线、受限环境里直接落地。

它沿用了我们在 MySQL、Redis、MinIO 项目里已经稳定下来的交付范式：

- 支持 `amd64` / `arm64` 多架构离线安装包
- 安装包内嵌镜像 payload，适合离线或弱网环境
- 安装时显式渲染内网镜像地址，不依赖 chart 的隐式默认值
- 默认开启 metrics 和 `ServiceMonitor`
- GitHub Actions 负责构建和发布 release

## 这套安装器是怎么设计的

普通使用者可以把它理解成一个“Milvus 离线安装器”，核心只有 4 个动作：

- `install`
- `status`
- `uninstall`
- `help`

其中 `install` 做的事情是：

1. 解包 `.run` 里的 chart、镜像元数据和镜像 tar
2. 按目标仓库地址准备镜像
3. 检查集群里是否支持 `ServiceMonitor`
4. 生成最终的 Helm 参数
5. 执行 `helm upgrade --install`
6. 输出 Pod、Service、PVC、ServiceMonitor 状态

这意味着使用者不需要先手动处理：

- `docker load`
- `docker tag`
- `docker push`
- `helm dependency build`
- `kubectl apply ServiceMonitor`

安装器已经把这些流程编排好了。

## 默认值

下面这些是安装器当前的默认业务参数：

- namespace: `milvus-system`
- release name: `milvus-cluster`
- mode: `cluster`
- message queue: `woodpecker`
- streaming: `true`
- storage class: `nfs`
- shared storage size hint: `500Gi`
- metrics: `true`
- ServiceMonitor: `true`
- ServiceMonitor interval: `30s`
- ServiceMonitor scrape timeout: `10s`
- registry repo: `sealos.hub:5000/kube4`
- image pull policy: `IfNotPresent`
- wait timeout: `15m`

资源默认值也已经内置进安装器，例如：

- proxy replicas: `2`
- querynode replicas: `2`
- datanode replicas: `2`
- indexnode replicas: `1`
- mixcoord replicas: `1`
- etcd replicas: `3`
- minio replicas: `4`
- pulsar replicas: `3`

这套默认值更适合“有一定资源余量的标准集群”。

## 快速开始

### 1. 看帮助

```bash
./milvus-cluster-installer-amd64.run --help
./milvus-cluster-installer-amd64.run help
```

### 2. 用默认参数安装

```bash
./milvus-cluster-installer-amd64.run install -y
```

### 3. 查看状态

```bash
./milvus-cluster-installer-amd64.run status
```

### 4. 卸载

```bash
./milvus-cluster-installer-amd64.run uninstall -y
```

## 最常见的 5 种使用场景

### 场景 1：标准集群，直接安装

适合资源比较充足、想快速起一套标准 Milvus 集群的场景。

```bash
./milvus-cluster-installer-amd64.run install -y
```

### 场景 2：单机测试环境，推荐用 compact

如果你的测试环境是单节点，或者节点上已经跑了很多业务，建议直接使用 `--compact`。

这个模式会自动把下面这些副本数收敛到更适合测试机的规模：

- `etcd=1`
- `minio=1`
- `proxy=1`
- `querynode=1`
- `datanode=1`
- `indexnode=1`
- `mixcoord=1`
- `pulsar/zookeeper/bookkeeper=1`

同时会把 MinIO 模式切成 `standalone`，避免默认分布式 MinIO 在单机环境里卡住。

```bash
./milvus-cluster-installer-amd64.run install \
  --compact \
  --skip-image-prepare \
  -y
```

### 场景 3：目标仓库已经有镜像，不想重复推送

如果你的内网仓库里已经有安装器需要的镜像，可以跳过镜像准备阶段：

```bash
./milvus-cluster-installer-amd64.run install \
  --registry sealos.hub:5000/kube4 \
  --skip-image-prepare \
  -y
```

### 场景 4：使用 Pulsar 而不是 woodpecker

```bash
./milvus-cluster-installer-amd64.run install \
  --mq pulsar \
  --pulsar-replicas 5 \
  --zookeeper-replicas 5 \
  --bookkeeper-replicas 5 \
  -y
```

### 场景 5：用 standalone 模式做更轻量的验证

```bash
./milvus-cluster-installer-amd64.run install \
  --mode standalone \
  --mq woodpecker \
  -y
```

## 监控是怎么处理的

这个仓库里，监控默认就是开启的：

- `metrics.enabled=true`
- `metrics.serviceMonitor.enabled=true`

并且默认会带平台统一标签：

- `monitoring.archinfra.io/stack=default`

如果你的 Prometheus Stack 已经按平台约定配置了跨 namespace 自动发现，那么 Milvus 装完后通常就会自动被发现。

如果集群中没有 `ServiceMonitor` CRD，安装器不会直接失败，而是会提示后自动降级：

- 保留 metrics
- 关闭 `ServiceMonitor`

如果你明确不想开监控，也可以手动关闭：

```bash
./milvus-cluster-installer-amd64.run install \
  --disable-metrics \
  -y
```

或者只关闭 `ServiceMonitor`：

```bash
./milvus-cluster-installer-amd64.run install \
  --disable-servicemonitor \
  -y
```

## 普通使用者最常用的参数

### 核心安装参数

- `-n, --namespace <ns>`
- `--release-name <name>`
- `--mode <cluster|standalone>`
- `--mq <woodpecker|pulsar>`
- `--streaming <true|false>`
- `--storage-class <name>`
- `--storage-size <size>`
- `--wait-timeout <duration>`
- `--registry <repo-prefix>`
- `--skip-image-prepare`
- `--compact`
- `-y, --yes`

### 监控参数

- `--enable-metrics`
- `--disable-metrics`
- `--enable-servicemonitor`
- `--disable-servicemonitor`
- `--service-monitor-interval <value>`
- `--service-monitor-scrape-timeout <value>`

### 副本和容量参数

- `--proxy-replicas <num>`
- `--querynode-replicas <num>`
- `--datanode-replicas <num>`
- `--indexnode-replicas <num>`
- `--mixcoord-replicas <num>`
- `--etcd-replicas <num>`
- `--minio-replicas <num>`
- `--pulsar-replicas <num>`
- `--zookeeper-replicas <num>`
- `--bookkeeper-replicas <num>`
- `--etcd-storage-size <size>`
- `--minio-storage-size <size>`
- `--pulsar-storage-size <size>`
- `--zookeeper-storage-size <size>`
- `--bookkeeper-journal-size <size>`
- `--bookkeeper-ledger-size <size>`

## 想更自定义，应该怎么做

安装器提供了 3 层自定义能力，建议按这个顺序理解。

### 第一层：直接用安装器参数

这是最推荐的方式，适合 80% 的使用场景。

例如：

```bash
./milvus-cluster-installer-amd64.run install \
  --namespace aict \
  --release-name milvus-demo \
  --storage-class nfs \
  --minio-replicas 1 \
  --etcd-replicas 1 \
  -y
```

### 第二层：用环境变量改资源请求和限制

一些资源参数已经做成了环境变量，适合你在不改脚本的情况下快速调小或调大资源。

例如：

```bash
MILVUS_PROXY_REQUEST_CPU=100m \
MILVUS_PROXY_REQUEST_MEM=256Mi \
MILVUS_QUERYNODE_REQUEST_CPU=250m \
MILVUS_QUERYNODE_REQUEST_MEM=1Gi \
MILVUS_DATANODE_REQUEST_CPU=250m \
MILVUS_DATANODE_REQUEST_MEM=1Gi \
./milvus-cluster-installer-amd64.run install --compact -y
```

当前已支持的一类典型环境变量包括：

- `MILVUS_PROXY_REQUEST_CPU`
- `MILVUS_PROXY_REQUEST_MEM`
- `MILVUS_PROXY_LIMIT_CPU`
- `MILVUS_PROXY_LIMIT_MEM`
- `MILVUS_QUERYNODE_REQUEST_CPU`
- `MILVUS_QUERYNODE_REQUEST_MEM`
- `MILVUS_QUERYNODE_LIMIT_CPU`
- `MILVUS_QUERYNODE_LIMIT_MEM`
- `MILVUS_DATANODE_REQUEST_CPU`
- `MILVUS_DATANODE_REQUEST_MEM`
- `MILVUS_DATANODE_LIMIT_CPU`
- `MILVUS_DATANODE_LIMIT_MEM`
- `MIX_COORDINATOR_REQUEST_CPU`
- `MIX_COORDINATOR_REQUEST_MEM`
- `ETCD_REQUEST_CPU`
- `ETCD_REQUEST_MEM`
- `MINIO_REQUEST_CPU`
- `MINIO_REQUEST_MEM`

### 第三层：把 Helm 原生参数透传进去

如果你需要更深度地覆盖 chart 行为，可以在命令末尾用 `--` 继续追加 Helm 参数。

例如：

```bash
./milvus-cluster-installer-amd64.run install \
  --compact \
  -y \
  -- \
  --set-string extraConfig.LOG_LEVEL=debug
```

或者：

```bash
./milvus-cluster-installer-amd64.run install \
  -y \
  -- \
  --set proxy.service.type=NodePort
```

这个能力适合：

- 安装器还没内建成参数的细项
- 临时验证某个 chart 原生能力
- 不想改安装器脚本，但需要一次性覆盖

## 建议怎么选参数

### 如果你不熟悉 Milvus，也不熟悉这套安装器

直接从下面两种之一开始：

- 资源充足的集群：`install -y`
- 单机测试环境：`install --compact --skip-image-prepare -y`

### 如果你知道这是单节点、共享环境、资源偏紧

优先用：

```bash
./milvus-cluster-installer-amd64.run install --compact -y
```

必要时再配合环境变量调小 CPU 和内存请求。

### 如果你已经有自己的镜像仓库流程

优先用：

```bash
./milvus-cluster-installer-amd64.run install \
  --registry <你的仓库前缀> \
  --skip-image-prepare \
  -y
```

## 安装后怎么验证

先看整体状态：

```bash
./milvus-cluster-installer-amd64.run status
```

再看关键 Pod：

```bash
kubectl get pods -n milvus-system
```

再看监控资源：

```bash
kubectl get servicemonitor -n milvus-system
```

如果 Prometheus 已接入平台发现策略，也可以再去 Prometheus targets 页面确认 Milvus 已被抓取。

## 常见问题与排障

### 1. etcd 报错 `Headless service domain does not have an IP per initial member in the cluster`

这通常不是 etcd 本身坏了，而是副本没有起全。

常见原因：

- 节点 CPU 不够
- 节点内存不够
- MinIO/etcd 的 PVC 没绑定
- 单节点环境却用了默认多副本配置

优先排查：

```bash
kubectl get pods -n milvus-system
kubectl describe pod <pod-name> -n milvus-system
kubectl get pvc -n milvus-system
kubectl describe node <node-name>
```

如果是测试机或单机环境，优先重装为：

```bash
./milvus-cluster-installer-amd64.run install --compact -y
```

### 2. 某些 Pod 一直 Pending

通常看 `kubectl describe pod` 里的调度事件，最常见的是：

- `Insufficient cpu`
- `Insufficient memory`
- PVC 没绑定

这时建议：

- 用 `--compact`
- 调小资源请求环境变量
- 检查 `storageClass` 是否正确

### 3. Prometheus 没发现 Milvus

先检查：

```bash
kubectl get crd servicemonitors.monitoring.coreos.com
kubectl get servicemonitor -n milvus-system
```

再确认 Prometheus Stack 是否按平台约定抓取：

- `monitoring.archinfra.io/stack=default`

### 4. 想看最终 Helm 安装命令

安装器在执行前会打印 `Helm Command Preview`，可以直接从终端里看到最终拼出来的 Helm 命令。

这对排查“某个参数到底有没有生效”很有帮助。

## 目录结构

- `build.sh`: 构建多架构 `.run` 包
- `install.sh`: 自解压离线安装器模板
- `images/image.json`: 镜像清单
- `charts/milvus`: Milvus Helm chart
- `.github/workflows/build-offline-installer.yml`: GitHub Actions 构建和发布

## 本地构建

要求：

- `bash`
- `docker`
- `python` 或 `python3`

示例：

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

构建产物在 `dist/`：

- `milvus-cluster-installer-amd64.run`
- `milvus-cluster-installer-amd64.run.sha256`
- `milvus-cluster-installer-arm64.run`
- `milvus-cluster-installer-arm64.run.sha256`

## 镜像来源

离线包当前默认从公网多架构镜像构建，再重打为内网目标仓库格式：

- `milvusdb/milvus:v2.6.9`
- `milvusdb/etcd:3.5.25-r1`
- `minio/minio:RELEASE.2024-12-18T13-15-44Z`
- `apachepulsar/pulsar:3.0.7`

`heaptrack` 没有放进默认离线 payload，因为上游公开镜像当前只有 `amd64`，而 chart 中它默认也是关闭的。

## GitHub Actions 发布流程

推送到 `main`：

- 构建 `amd64` / `arm64` 安装包
- 上传构建产物

推送 tag `v*`：

- 构建安装包
- 发布 GitHub Release
- 挂载 `.run` 和 `.sha256`
