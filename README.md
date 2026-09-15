# apps_milvus-cluster

面向 Kubernetes / Sealos 私有化环境的 Milvus 集群离线交付包。

本仓库把 **镜像准备、Helm 安装、认证、资源规格、监控、告警、Dashboard 和离线双架构打包** 收敛到一个可重复执行的 `.run` 安装器中。

## 当前标准交付基线

| 项目 | 当前基线 |
| --- | --- |
| apps_milvus-cluster | `0.2.0` |
| Milvus | **`2.6.23`** |
| Bundled Helm chart | `5.0.12`（保留现有依赖骨架） |
| 默认模式 | `cluster` |
| 默认 MQ | `woodpecker` |
| Streaming | 开启 |
| Authentication | **默认开启** |
| Service | `ClusterIP` |
| Metrics | 默认开启 |
| ServiceMonitor | 默认开启，CRD 不存在时自动跳过 |
| PrometheusRule | 默认开启，CRD 不存在时自动跳过 |
| 日志格式 | `json` |
| 架构 | `amd64` / `arm64` |
| 默认资源档位 | `standard` |

### 本轮明确冻结的内嵌依赖

本次 `0.2.0` 只升级 Milvus 本体与交付层，**不升级内嵌 etcd 和 MinIO**：

```text
etcd   milvusdb/etcd:3.5.25-r1
MinIO  minio/minio:RELEASE.2024-12-18T13-15-44Z
```

这两个版本后续单独做兼容性、安全与数据迁移评估，不和本轮 Milvus 安全升级混在一起。

可选 Pulsar 模式的运行镜像更新为：

```text
apachepulsar/pulsar:3.0.17
```

标准交付仍然推荐 `woodpecker`，不会默认启动 Pulsar。

---

# 1. 为什么升级到 Milvus 2.6.23

旧基线是 `2.6.9`。该版本处于 Milvus `CVE-2026-26190` 的受影响区间（`>=2.6.0,<2.6.10`），涉及 `9091` 管理/REST 端口未认证访问问题。

当前交付基线升级到 `2.6.23`，继续停留在 2.6 patch 维护线，不在本轮直接跨到 Milvus 3.x。

这样做的目标是：

1. 先消除已知安全版本风险；
2. 保持现有 2.6 架构、Woodpecker 和数据路径不发生代际变化；
3. 不把 etcd / MinIO 升级风险绑进同一次交付；
4. Milvus 3.x 后续单独做 migration / rollback / E2E 设计。

---

# 2. 推荐标准安装命令

新环境正式交付推荐显式写出关键参数：

```bash
./milvus-cluster-installer-amd64.run install \
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
```

这条命令代表当前 Archinfra Milvus 标准交付：

```text
Milvus                 2.6.23
Mode                   cluster
MQ                     woodpecker
Streaming              ON
Resource Profile       standard
Authentication         ON
Service                ClusterIP
Metrics                ON
ServiceMonitor         ON
PrometheusRule         ON
Log format             json
StorageClass           ceph-rbd（示例，按现场替换）
```

> `ceph-rbd` 是生产块存储示例，不是硬编码要求。实际交付应替换成客户环境经过确认的 StorageClass。

客户使用私有 Harbor / Registry 时追加：

```bash
--registry harbor.example.com/kube4
```

如果镜像已经预先导入目标仓库：

```bash
--skip-image-prepare
```

---

# 3. 资源规格：只保留 lite / standard / large

对外只支持：

```text
lite
standard
large
```

不再把以下名称作为交付参数：

```text
low
mid
midd
middle
medium
high
compact
```

传旧 profile 会直接失败；旧 `--compact` 也会明确提示改用：

```bash
--resource-profile lite
```

## 3.1 lite

用于 Demo、开发测试、资源紧张的单机环境。

| 组件 | 副本 | Request | Limit |
| --- | ---: | --- | --- |
| proxy | 1 | `100m / 256Mi` | `500m / 1Gi` |
| queryNode | 1 | `250m / 1Gi` | `1C / 4Gi` |
| dataNode | 1 | `250m / 1Gi` | `1C / 4Gi` |
| mixCoordinator | 1 | `100m / 256Mi` | `500m / 1Gi` |
| streamingNode | 1 | `250m / 512Mi` | `1C / 2Gi` |
| etcd | 1 | 轻量资源档位 | **版本不变** |
| MinIO | 1 | 轻量资源档位 | **版本不变** |

示例：

```bash
./milvus-cluster-installer-amd64.run install \
  --resource-profile lite \
  --storage-class nfs \
  -y
```

## 3.2 standard

默认正式交付规格。

| 组件 | 副本 | Request | Limit |
| --- | ---: | --- | --- |
| proxy | 2 | `200m / 512Mi` | `1C / 2Gi` |
| queryNode | 2 | `500m / 2Gi` | `2C / 8Gi` |
| dataNode | 2 | `500m / 2Gi` | `2C / 8Gi` |
| mixCoordinator | 1 | `200m / 512Mi` | `1C / 2Gi` |
| streamingNode | 1 | `500m / 1Gi` | `2C / 4Gi` |
| etcd | 3 | `200m / 512Mi` | `1C / 2Gi`，**版本不变** |
| MinIO | 4 | `200m / 512Mi` | `1C / 2Gi`，**版本不变** |

## 3.3 large

用于更大的向量工作集、更高并发搜索和写入压力。

| 组件 | 副本 | Request | Limit |
| --- | ---: | --- | --- |
| proxy | 2 | `500m / 1Gi` | `2C / 4Gi` |
| queryNode | 2 | `1C / 4Gi` | `4C / 12Gi` |
| dataNode | 2 | `1C / 4Gi` | `4C / 12Gi` |
| mixCoordinator | 1 | `500m / 1Gi` | `2C / 4Gi` |
| streamingNode | 2 | `1C / 2Gi` | `4C / 8Gi` |
| etcd | 3 | profile 资源随档位调整 | **版本不变** |
| MinIO | 4 | profile 资源随档位调整 | **版本不变** |

具体生产规模仍应根据：

- 向量数量；
- 向量维度；
- 索引类型；
- 搜索 `nq/topK`；
- 数据写入速率；
- 热数据工作集；
- 查询延迟目标；

通过压测决定，而不是只根据“用户数”估算。

---

# 4. Authentication 和 root Secret

## 4.1 新安装默认开启认证

标准安装默认：

```text
common.security.authorizationEnabled = true
```

Milvus 官方默认 root 密码是 `Milvus`，本安装器不会把这个固定弱口令作为新环境交付密码。

新安装如果不传：

```bash
--root-password
```

installer 会自动生成随机密码，并保存：

```text
Secret/milvus-auth
key: root-password
```

查看密码：

```bash
kubectl get secret -n milvus-system milvus-auth \
  -o jsonpath='{.data.root-password}' | base64 -d; echo
```

也可以由外部密码系统生成后显式传入：

```bash
--root-password '<STRONG_PASSWORD>'
```

密码最大 72 字符，不能包含换行。

## 4.2 Secret reconcile 规则

- Secret 已存在：重复 `install` 自动复用；
- Secret 已存在但显式传入不同密码：拒绝执行；
- 普通 `install` 不偷偷做 root 密码轮换；
- `uninstall` 默认保留 `Secret/milvus-auth`，方便保留数据后的重装。

## 4.3 从旧版本升级的特殊注意

`defaultRootPassword` 主要用于 root credential 初始化。旧集群已经在 etcd 中存在 root credential，因此不能假设“修改 Helm 值”就会可靠地旋转旧密码。

如果 installer 检测到：

```text
已有 Helm release
+
没有 Secret/milvus-auth
```

会停止安装，要求明确选择：

```bash
--root-password '<CURRENT_PASSWORD>'
```

或者临时：

```bash
--disable-auth
```

先完成既有 credential 的迁移，再重新启用认证。

**不要让安装器猜测旧环境的 root 密码。**

## 4.4 后续账号治理 TODO

当前先保证安全交付闭环，后续再把业务账号自动化：

```text
root                管理员
rag_app             RAG 业务账号
embedding_service   向量写入账号
readonly_user       只读查询账号
```

目标是业务逐步脱离 root，并使用 Milvus RBAC 控制权限。

---

# 5. 网络暴露

当前安装器固定：

```text
service.type = ClusterIP
```

也就是默认不会创建 NodePort / LoadBalancer 对外暴露 Milvus。

标准访问方式：

```text
业务 Pod
   ↓
Kubernetes Service
   ↓
Milvus Proxy :19530
```

如果项目需要外部访问，建议通过受控 Gateway / Ingress / 内网 LB 设计，不把数据库端口无条件暴露到客户网络。

---

# 6. Monitoring

默认开启：

```text
metrics           ON
ServiceMonitor    ON
PrometheusRule    ON
etcd PodMonitor   ON
MinIO monitor     ON
```

发现标签：

```yaml
monitoring.archinfra.io/stack: default
```

Grafana Dashboard 目录：

```text
Middleware/Milvus
```

如果目标集群没有 Prometheus Operator CRD：

```text
ServiceMonitor / PodMonitor / PrometheusRule
```

installer 会告警并跳过相应 CR，不阻塞 Milvus 本体安装。

升级到 `2.6.23` 后应在真实环境重新验证 dashboard / alert 的 PromQL，因为 2.6 后续 patch 曾修正部分 Proxy metric label 行为。

---

# 7. 日志

Archinfra overlay 默认：

```yaml
log:
  format: json
```

Milvus chart 当前已经有文件滚动配置：

```text
maxSize     300 MB
maxAge      10 days
maxBackups  20
```

默认不启用日志 PVC。

正式交付推荐：

```text
Milvus stdout/stderr
       ↓
平台 DaemonSet / Agent
       ↓
Loki / Elasticsearch / 统一日志平台
```

不要把 Pod 本地日志文件当长期归档系统。

---

# 8. 存储

本轮不改变 etcd / MinIO 的版本和整体存储架构。

现有安装器仍允许：

```text
--storage-class
--etcd-storage-size
--minio-storage-size
--zookeeper-storage-size
--bookkeeper-journal-size
--bookkeeper-ledger-size
```

默认 Woodpecker 模式主要持久化来源仍是：

```text
etcd
MinIO
```

生产环境即使为了兼容保留 `nfs` 默认值，也建议在正式交付命令中显式指定经过验证的 StorageClass。

后续单独做存储架构升级时，再评估：

- etcd 独立高可靠块存储；
- MinIO / S3 外置；
- dependency-specific StorageClass；
- PVC 扩容与数据迁移规则。

---

# 9. Message Queue

标准默认：

```bash
--mq woodpecker
```

这是当前推荐路径。

如明确需要 Pulsar：

```bash
./milvus-cluster-installer-amd64.run install \
  --resource-profile standard \
  --mq pulsar \
  -y
```

当前可选 Pulsar 镜像：

```text
apachepulsar/pulsar:3.0.17
```

升级已有 Milvus 时不要在同一次升级里切换 MQ；先保持原消息队列，完成版本升级和验收后再单独设计 MQ migration。

---

# 10. Help

```bash
./milvus-cluster-installer-amd64.run help
./milvus-cluster-installer-amd64.run help overview
./milvus-cluster-installer-amd64.run help install
./milvus-cluster-installer-amd64.run help params
./milvus-cluster-installer-amd64.run help examples
```

其中现场最常用：

```bash
help install
help params
```

所有帮助统一使用：

```text
lite / standard / large
```

---

# 11. 离线运行依赖

目标客户环境运行 `.run` 需要：

```text
bash
helm
kubectl
```

默认镜像导入/推送路径还需要：

```text
docker
```

如果镜像已经在目标 Registry：

```bash
--skip-image-prepare
```

则安装阶段不需要 Docker 镜像导入流程。

**目标客户环境不依赖 jq。**

当前 Helm 仍由宿主机提供；后续可以像真正 self-contained installer 一样把 amd64/arm64 Helm binary 打进 `.run`，这是下一阶段优化项。

---

# 12. Build

构建 amd64：

```bash
./build.sh --arch amd64
```

构建 arm64：

```bash
./build.sh --arch arm64
```

同时构建：

```bash
./build.sh --arch all
```

产物：

```text
dist/milvus-cluster-installer-amd64.run
dist/milvus-cluster-installer-amd64.run.sha256

dist/milvus-cluster-installer-arm64.run
dist/milvus-cluster-installer-arm64.run.sha256
```

---

# 13. CI 交付不变量

GitHub Actions 在打包前会检查：

```text
bash syntax
image.json JSON/BOM
Milvus = 2.6.23
Pulsar = 3.0.17
etcd = 3.5.25-r1               （本轮冻结）
MinIO = RELEASE.2024-12-18...  （本轮冻结）
Chart appVersion = 2.6.23
Authentication default = ON
Secret lifecycle config
resource profile = lite|standard|large
legacy mid/low/high 不可作为用户参数
Helm lint
Helm template
amd64 package
arm64 package
checksum
生成后的 installer help
```

这保证后续维护不会无意中把本轮明确冻结的依赖或安全基线改掉。

---

# 14. 安装后检查

```bash
./milvus-cluster-installer-amd64.run status -n milvus-system
```

或：

```bash
kubectl get pods -n milvus-system
kubectl get svc -n milvus-system
kubectl get pvc -n milvus-system
kubectl get servicemonitor,podmonitor,prometheusrule -n milvus-system
```

确认 root Secret：

```bash
kubectl get secret -n milvus-system milvus-auth
```

应用连接示例应使用：

```text
root:<Secret 中的密码>
```

不要再使用固定：

```text
root:Milvus
```

---

# 15. 卸载

```bash
./milvus-cluster-installer-amd64.run uninstall \
  -n milvus-system \
  -y
```

Helm release 会删除，但持久化资源是否保留取决于 chart 的 PVC/resource-policy 行为。

`Secret/milvus-auth` 由 installer 独立管理，默认保留，避免保留数据后重装却丢失 root credential。

确认环境不再需要后再手工删除：

```bash
kubectl delete secret -n milvus-system milvus-auth
```

---

# 16. 这轮不做什么

为了控制交付风险，以下内容**不在 0.2.0 本轮范围内**：

```text
内嵌 etcd 版本升级
内嵌 MinIO 版本升级
Milvus 3.x migration
external S3 默认化
external etcd 默认化
TLS 默认启用
业务 RBAC 账号自动创建
Helm binary 内嵌
备份恢复体系
```

这些应该作为独立变更逐项验证，而不是和 Milvus 2.6.23 安全升级一次性混在一起。

---

# 17. 下一步验收

代码 CI 通过之后，正式交付前建议至少做一次真实 Kubernetes / Sealos E2E：

```text
全新安装
  ↓
Milvus 2.6.23 Ready
  ↓
root Secret 生成
  ↓
无认证连接失败
  ↓
root 认证连接成功
  ↓
创建 collection
  ↓
insert / flush / index / load
  ↓
search / query
  ↓
Pod restart
  ↓
数据仍可查询
  ↓
ServiceMonitor target UP
  ↓
Dashboard / Alert 验证
  ↓
重复 install reconcile
  ↓
uninstall / 保留数据场景验证
```

这轮 E2E 通过后，可以把 `2.6.23 + 0.2.0 installer` 定为新的 Milvus 2.6 标准交付基线。
