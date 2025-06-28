# CoreDNS azroute 插件

## 项目简介
azroute 是一个为 CoreDNS 设计的可用区（AZ）就近调度插件，结合 hosts 插件和 API 动态网段-AZ 映射，实现内部服务 DNS 解析的智能就近返回。

## 主要特性
- 支持通过 API 动态获取网段与可用区（AZ）映射
- 与 hosts 插件配合，自动优选同 AZ 的 IP 返回
- 支持 A/AAAA 记录，IPv4/IPv6
- API 热加载，异常自动容错
- 用户只需维护 hosts 文件，无需关心 AZ 信息

## 目录结构
```
.
├── azroute/         # 插件源码
├── az-mock-api/     # Gin API 示例服务
├── docs/            # 使用文档与设计文档
└── README.md
```

## 快速上手
1. 按照 [docs/usage.md](docs/usage.md) 配置 Corefile、hosts 和 API 服务
2. 集成插件到 CoreDNS 主项目并编译
3. 启动 CoreDNS 和 API 服务，体验就近调度

## 编译

```bash
mkdir -p /code/plugins
cd /code/plugins
git clone https://github.com/kbsonlong/azroute.git
cd /code
git clone https://github.com/coredns/coredns.git
cd coredns
```

- 修改go.mod

```text
require (
    azroute v0.0.0
    ...
)
...
replace azroute => ../azroute/azroute

```

- 修改plugin.cfg

```bash
sed -i 's/hosts:hosts/azroute:azroute\nhosts:hosts/g' plugin.cfg
```

- 加载azroute插件

```bash
# vim core/plugin/zplugin.go
...
_ "azroute"

```


## 详细说明
- [使用文档](docs/usage.md)
- [设计文档](docs/design.md)

## 优化方案说明

### 1. Trie（基数树）高效网段查找
- 使用 [cidranger](https://github.com/yl2chen/cidranger) 实现网段的 Trie 存储与查找，查找复杂度低，支持大规模网段。
- 每次热加载 AZ 数据时自动重建 Trie 索引。

### 2. LRU 缓存热点 IP 查询
- 使用 [golang-lru](https://github.com/hashicorp/golang-lru) 实现最近最少使用缓存。
- IP->AZ 映射缓存，热点 IP 查询可直接命中缓存，极大提升性能。
- 缓存容量可通过 `lru_size` 参数配置，默认 1024 条。
- 热加载 AZ 数据时自动清空缓存，保证数据一致性。

### 3. 配置示例

```conf
azroute {
    azmap_api http://localhost:8080/azmap
    lru_size 4096
}
```
- `azmap_api`：网段-AZ映射API地址
- `lru_size`：LRU缓存最大条目数（不是字节数）

### 4. 内存占用估算
- 1000 条网段时，azroute 插件总占用约 330KB
- 1万条网段时，约 2MB
- LRU缓存最大占用 = lru_size × 单条entry大小（可配置，默认1024条，最大8K条也仅约0.5MB）
- 详见 [docs/memory_analysis.md](docs/memory_analysis.md)

### 5. 性能收益
- Trie结构查找大幅降低单次查找延迟
- LRU缓存极大提升热点IP查询性能，降低后端压力
- 支持大规模网段和高并发场景

## 参考
- [cidranger](https://github.com/yl2chen/cidranger)
- [golang-lru](https://github.com/hashicorp/golang-lru)