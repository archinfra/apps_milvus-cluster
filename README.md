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
- resource profile: `mid`

## Resource profile

Installer now supports:

- `--resource-profile low`
- `--resource-profile mid`
- `--resource-profile midd`
- `--resource-profile high`

Default is `mid`. `midd` is accepted as an alias of `mid`.

Profile intent:

- `low`: demo, smoke test, or resource-tight shared environment
- `mid`: normal shared environment, baseline for `500-1000` concurrency and around `10000` users
- `high`: higher query/write pressure or larger vector working set

Per-pod baseline for the components that the installer explicitly sizes:

| Profile | `proxy` | `querynode` | `datanode` | `mixcoord` | `etcd` | `minio` |
| --- | --- | --- | --- | --- | --- | --- |
| `low` | `100m / 256Mi` request, `500m / 1Gi` limit | `250m / 1Gi` request, `1 / 4Gi` limit | `250m / 1Gi` request, `1 / 4Gi` limit | `100m / 256Mi` request, `500m / 1Gi` limit | `100m / 256Mi` request, `500m / 1Gi` limit | `100m / 256Mi` request, `500m / 1Gi` limit |
| `mid` | `200m / 512Mi` request, `1 / 2Gi` limit | `500m / 2Gi` request, `2 / 8Gi` limit | `500m / 2Gi` request, `2 / 8Gi` limit | `200m / 512Mi` request, `1 / 2Gi` limit | `200m / 512Mi` request, `1 / 2Gi` limit | `200m / 512Mi` request, `1 / 2Gi` limit |
| `high` | `500m / 1Gi` request, `2 / 4Gi` limit | `1 / 4Gi` request, `4 / 12Gi` limit | `1 / 4Gi` request, `4 / 12Gi` limit | `500m / 1Gi` request, `2 / 4Gi` limit | `500m / 1Gi` request, `2 / 4Gi` limit | `500m / 1Gi` request, `2 / 4Gi` limit |

`--compact` continues to control replica counts. `--resource-profile` only changes per-pod requests and limits, so the two flags can be combined safely.

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

## 默认部署拓扑

如果你直接执行默认安装：

```bash
./milvus-cluster-installer-amd64.run install -y
```

默认会部署的核心工作负载是：

- `proxy`
- `querynode`
- `datanode`
- `mixcoord`
- `streamingnode`
- `etcd`
- `minio`

几个容易误解的点也提前说明：

- 默认消息队列是 `woodpecker`
- 当前 chart 里 `woodpecker` 是嵌入式模式，不会额外起独立的 `woodpecker` StatefulSet
- 默认启用的是 `mixcoord`，不是拆分的 `rootcoord/querycoord/datacoord/indexcoord`
- 默认没有启用独立 `indexnode`
- 默认没有启用 `attu`
- 默认没有依赖 MySQL、Redis、Nacos

也就是说，Milvus 自己是一个相对独立的业务组件，它和其他组件之间最常见的关系不是“依赖它们启动”，而是“被业务系统调用”或者“被 Prometheus 抓监控”。

## 资源需求矩阵

下面这部分很重要。

这里统计的是“安装器和默认 chart 显式声明的 requests/limits”，也就是调度器和平台最容易直接感知到的资源边界。

需要注意：

- `streamingnode` 当前没有显式 request/limit
- 默认 `woodpecker` 是嵌入在 `streamingnode` 路径里的，不单独统计 Pod 资源
- `--mq pulsar` 时，Pulsar 子组件大多只设置了 request，没有统一 limit，所以真实峰值可能高于表格里的“显式上限”

### 默认模式资源明细

默认模式指：

- `mode=cluster`
- `mq=woodpecker`
- `streaming=true`
- 不加 `--compact`

| 组件 | 默认副本 | 单 Pod Request | 单 Pod Limit | 默认总 Request | 默认总 Limit | 说明 |
| --- | ---: | --- | --- | --- | --- | --- |
| `proxy` | 2 | `200m / 512Mi` | `1000m / 2Gi` | `400m / 1Gi` | `2 CPU / 4Gi` | 安装器显式下发 |
| `querynode` | 2 | `500m / 2Gi` | `2000m / 8Gi` | `1 CPU / 4Gi` | `4 CPU / 16Gi` | 安装器显式下发 |
| `datanode` | 2 | `500m / 2Gi` | `2000m / 8Gi` | `1 CPU / 4Gi` | `4 CPU / 16Gi` | 安装器显式下发 |
| `mixcoord` | 1 | `200m / 512Mi` | `1000m / 2Gi` | `200m / 512Mi` | `1 CPU / 2Gi` | 安装器显式下发 |
| `etcd` | 3 | `200m / 512Mi` | `1000m / 2Gi` | `600m / 1.5Gi` | `3 CPU / 6Gi` | 安装器显式下发 |
| `minio` | 4 | `200m / 512Mi` | `1000m / 2Gi` | `800m / 2Gi` | `4 CPU / 8Gi` | 安装器显式下发 |
| `streamingnode` | 1 | 未显式设置 | 未显式设置 | 未计入 | 未计入 | 默认启用 |

### compact 模式资源明细

`--compact` 适合单机测试环境，它会把副本数收敛到更适合测试机的规模。

| 组件 | compact 副本 | 单 Pod Request | 单 Pod Limit | compact 总 Request | compact 总 Limit |
| --- | ---: | --- | --- | --- | --- |
| `proxy` | 1 | `200m / 512Mi` | `1000m / 2Gi` | `200m / 512Mi` | `1 CPU / 2Gi` |
| `querynode` | 1 | `500m / 2Gi` | `2000m / 8Gi` | `500m / 2Gi` | `2 CPU / 8Gi` |
| `datanode` | 1 | `500m / 2Gi` | `2000m / 8Gi` | `500m / 2Gi` | `2 CPU / 8Gi` |
| `mixcoord` | 1 | `200m / 512Mi` | `1000m / 2Gi` | `200m / 512Mi` | `1 CPU / 2Gi` |
| `etcd` | 1 | `200m / 512Mi` | `1000m / 2Gi` | `200m / 512Mi` | `1 CPU / 2Gi` |
| `minio` | 1 | `200m / 512Mi` | `1000m / 2Gi` | `200m / 512Mi` | `1 CPU / 2Gi` |
| `streamingnode` | 1 | 未显式设置 | 未显式设置 | 未计入 | 未计入 |

### Pulsar 模式资源增量

如果你把消息队列切成：

```bash
--mq pulsar
```

资源需求会明显上升，因为会带起 Pulsar 子组件。按当前默认值，Pulsar 相关显式 request 大致是：

| 组件 | 默认副本 | 单 Pod Request | 默认总 Request | 说明 |
| --- | ---: | --- | --- | --- |
| `pulsarv3.zookeeper` | 3 | `200m / 256Mi` | `600m / 768Mi` | 只有 request，无统一 limit |
| `pulsarv3.bookkeeper` | 3 | `500m / 2Gi` | `1.5 CPU / 6Gi` | 只有 request，无统一 limit |
| `pulsarv3.autorecovery` | 1 | `100m / 128Mi` | `100m / 128Mi` | 只有 request，无统一 limit |
| `pulsarv3.broker` | 3 | `500m / 2Gi` | `1.5 CPU / 6Gi` | 默认由 `--pulsar-replicas` 控制 |
| `pulsarv3.proxy` | 2 | `500m / 1Gi` | `1 CPU / 2Gi` | chart 默认值 |

### 资源总览

为了方便使用者快速判断，下面给出几个常见安装档位的汇总值。

| 安装档位 | 调度最小 request | 已显式声明的 limit 总和 | 默认持久化存储下限 | 适用建议 |
| --- | --- | --- | --- | --- |
| 默认 `cluster + woodpecker` | `4 CPU / 13Gi` | `18 CPU / 52Gi` | `460Gi` | 标准多节点环境 |
| `--compact + woodpecker` | `1.8 CPU / 6Gi` | `8 CPU / 24Gi` | `120Gi` | 单机或共享测试机 |
| 默认 `cluster + pulsar` | `8.7 CPU / 27.9Gi` | 仅 Milvus/etcd/minio 部分有显式 limit | `1420Gi` | 资源较充足的集群 |
| `--compact + pulsar` | `4.1 CPU / 12.4Gi` | 仅 Milvus/etcd/minio 部分有显式 limit | `440Gi` | 勉强可测，不推荐长期使用 |

几个解释：

- “调度最小 request” 是调度器最容易直接感知到的最低资源门槛
- “已显式声明的 limit 总和” 不是整个系统的绝对最大峰值，只是当前 chart/安装器里明确写出的上限
- `streamingnode` 目前没显式 request/limit，所以真实峰值会高于上表
- `--mq pulsar` 时，Pulsar 子组件大多没有统一 limit，因此不能把上表看成硬上限

## 存储需求与容量说明

存储这块也建议使用者提前看清楚。

默认 `woodpecker` 模式下，主要持久化数据来自：

- `etcd`: `3 x 20Gi = 60Gi`
- `minio`: `4 x 100Gi = 400Gi`

所以默认最低持久化容量大约是：

- `460Gi`

如果是 `--compact`，则会变成：

- `etcd`: `1 x 20Gi = 20Gi`
- `minio`: `1 x 100Gi = 100Gi`
- 合计：`120Gi`

如果切到 `--mq pulsar`，还会额外增加：

- `zookeeper`: `3 x 20Gi = 60Gi`
- `bookkeeper journal`: `3 x 100Gi = 300Gi`
- `bookkeeper ledger`: `3 x 200Gi = 600Gi`

所以默认 Pulsar 模式下，最低持久化容量大约是：

- `1420Gi`

这里还有一个兼容性说明：

- `--storage-size` 目前保留为兼容参数和展示提示
- 当前实际生效的持久化容量，主要由 `--etcd-storage-size`、`--minio-storage-size`、`--zookeeper-storage-size`、`--bookkeeper-journal-size`、`--bookkeeper-ledger-size` 这些组件级参数控制

如果你要给别人或给 AI 一条“不会误解”的规则，应该优先使用组件级容量参数，不要只传一个总的 `--storage-size`。

## 使用前置条件与依赖

这个安装器要成功运行，前置条件建议明确成下面这些。

### 必要条件

- Kubernetes 集群可用
- `kubectl` 可正常访问目标集群
- `helm` 已安装
- 集群里存在可用的 `StorageClass`
- 默认或指定的 `storageClass` 可以正常动态供给 PVC

### 镜像相关条件

- 如果不带 `--skip-image-prepare`，执行机器需要有 `docker`
- 如果带 `--skip-image-prepare`，目标镜像仓库里需要已经有安装器所需镜像

### 监控相关条件

- 如果集群里有 `ServiceMonitor` CRD，安装器会创建 `ServiceMonitor`
- 如果没有，安装器会自动降级，只保留 metrics

### 对其他组件的关系

- Milvus 默认不依赖 MySQL
- Milvus 默认不依赖 Redis
- Milvus 默认不依赖 Nacos
- Milvus 与 Prometheus Stack 的对接，是通过 `ServiceMonitor + monitoring.archinfra.io/stack=default`

## 和其他组件对接时怎么理解

如果你的系统里还有 MySQL、Redis、Nacos 或更多业务组件，Milvus 最常见的对接方式是下面这些。

### 作为业务系统的向量库

业务系统通常只需要知道 Milvus 的服务地址：

- 服务名：`<release-name>.<namespace>.svc`
- 默认端口：`19530`

按默认值展开以后就是：

- `milvus-cluster.milvus-system.svc:19530`

如果你在别的组件里写配置，例如放到 Nacos、ConfigMap、环境变量里，通常就写这个 DNS 地址即可。

### 作为 Prometheus 被监控对象

Milvus 默认会暴露 metrics，并带上统一标签：

- `monitoring.archinfra.io/stack=default`

所以只要 Prometheus Stack 按平台规则启用了跨 namespace 发现，Milvus 通常装完就能自动接入监控。

### 如果业务需要外部访问

默认 Service 是：

- `ClusterIP`

如果业务需要集群外访问，可以透传 Helm 参数调整，例如：

```bash
./milvus-cluster-installer-amd64.run install \
  -y \
  -- \
  --set service.type=NodePort \
  --set service.nodePort=31953
```

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
- `etcd.metrics.enabled=true`
- `etcd.metrics.podMonitor.enabled=true`
- `minio.metrics.serviceMonitor.enabled=true`

并且默认会带平台统一标签：

- `monitoring.archinfra.io/stack=default`

如果你的 Prometheus Stack 已经按平台约定配置了跨 namespace 自动发现，那么 Milvus 装完后通常就会自动被发现。

默认情况下会覆盖到这些监控对象：

- Milvus 主服务 `ServiceMonitor`
- 内嵌 `etcd` 的 `PodMonitor`
- 内嵌 `minio` 的 `ServiceMonitor`

如果集群中没有 `ServiceMonitor` 或 `PodMonitor` CRD，安装器不会直接失败，而是会提示后自动降级：

- 保留 metrics
- 关闭缺失 CRD 对应的监控资源

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

## 给 AI 或自动化系统使用时，建议再补齐这些信息

如果这份文档未来是给大模型、自动化代理、或者运维机器人直接参考的，我建议把下面这些当成“执行规约”。

这样做的目标不是把文档写得更长，而是让执行者少猜、少试错、少误判。

### AI 在安装前应该先收集的环境事实

建议先收集这些事实，再决定安装参数：

```bash
uname -m
kubectl get nodes -o wide
kubectl get sc
kubectl get crd servicemonitors.monitoring.coreos.com
kubectl describe node <node-name>
helm list -A | grep milvus
```

至少要弄清楚：

- 目标机器架构是 `amd64` 还是 `arm64`
- 集群是否只有 1 个节点
- `storageClass` 是否存在且可用
- 集群里是否已安装 Prometheus Operator CRD
- 目标 namespace 和 release 是否已经存在
- 目标仓库里是否已经有镜像，可以使用 `--skip-image-prepare`

### AI 选择安装档位的建议规则

如果是大模型自己执行安装，建议按下面这套判断逻辑：

- 单节点环境：优先 `--compact`
- 共享测试环境：优先 `--compact`
- 可用 request 余量明显小于 `4 CPU / 13Gi`：优先 `--compact`
- 只想快速验证 Milvus 主链路：优先默认 `woodpecker`，不要切 `pulsar`
- 只有在明确需要 Pulsar 语义时，再使用 `--mq pulsar`
- 如果打算和平台监控联动，保留默认 `metrics=true`、`ServiceMonitor=true`
- 如果镜像仓库已准备好，优先加 `--skip-image-prepare`

一句话总结给 AI：

- 不确定资源余量时，用 `--compact`
- 不确定消息队列需求时，用默认 `woodpecker`
- 不确定监控环境时，不要主动关 metrics

### AI 安装 Milvus 时推荐的默认策略

对一个陌生但看起来资源不算特别充足的环境，推荐从这个命令开始：

```bash
./milvus-cluster-installer-amd64.run install \
  --compact \
  --skip-image-prepare \
  -y
```

如果后续验证通过，再根据资源情况逐步放大副本数。

### AI 需要知道的成功标准

如果是自动化执行，不能只看 `helm` 返回 0，还应该再确认：

- `helm status <release> -n <namespace>` 为 `deployed`
- `etcd` Pod Ready
- `minio` Pod Ready
- `proxy` Pod Ready
- `querynode` Pod Ready
- `datanode` Pod Ready
- `mixcoord` Pod Ready
- `streamingnode` Pod Ready
- PVC 为 `Bound`
- 如果集群支持 `ServiceMonitor`，则 `ServiceMonitor` 已创建

### AI 需要识别的典型失败信号

下面这些报错，AI 应该优先按固定思路处理。

`Headless service domain does not have an IP per initial member in the cluster`

- 优先判断：是不是 etcd/minio 副本没起全
- 常见原因：`Insufficient cpu`、`Insufficient memory`、PVC 未绑定
- 优先动作：改用 `--compact`，或进一步下调 request

`Pending`

- 优先看 `kubectl describe pod`
- 重点检查：CPU、内存、PVC、node selector、taint/toleration

`ServiceMonitor` 没创建

- 先查 CRD 是否存在
- 如果 CRD 不存在，这是预期降级，不是安装失败

### AI 需要知道的跨组件契约

如果后续要自动部署一个更完整的系统，Milvus 这边最关键的对接契约建议固定为：

- Milvus 内部地址：`<release-name>.<namespace>.svc:19530`
- metrics 暴露端口：`9091`
- 平台监控标签：`monitoring.archinfra.io/stack=default`
- 默认不依赖 MySQL、Redis、Nacos
- 如果别的业务系统需要调用 Milvus，把上面的 DNS 地址写进它们的配置即可

这几条固定下来以后，大模型在自动拼装一个系统时，就不会把 Milvus 错误地当成“必须先装 MySQL 才能运行”的组件。

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
## Built-in Monitoring, Alerts, And Dashboards

Default install now enables:

- `metrics.enabled=true`
- `ServiceMonitor`
- `PrometheusRule`
- Grafana dashboard `ConfigMap`

Grafana auto-import contract:

- dashboard label: `grafana_dashboard=1`
- platform label: `monitoring.archinfra.io/stack=default`
- folder annotation: `grafana_folder=Middleware/Milvus`

Built-in alerts:

- `MilvusTargetsDown`
- `MilvusMemoryHigh`

Built-in dashboard panels:

- Healthy Targets
- Resident Memory
- Go Goroutines
- CPU Cores Used
- Memory By Pod
- CPU By Pod

Current Milvus dashboard first focuses on operational health and process-level capacity signals so it stays compatible across cluster, compact, and standalone deployments.
