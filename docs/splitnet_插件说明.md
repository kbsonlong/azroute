# splitnet 内外网区分解析插件

## 简介
splitnet 是为 CoreDNS 设计的内外网智能区分解析插件，支持通过 API 动态获取内网网段配置，根据客户端 IP 自动过滤下游插件（如 hosts）的解析结果，实现内外网智能路由。

## 主要特性
- 支持通过 API 动态热加载内网网段配置
- 基于 Trie（cidranger）结构高效判断 IP 归属
- 内置 LRU 缓存，热点 IP 查询性能极高，缓存容量可配置
- 智能过滤下游插件解析结果，内网用户返回内网IP，外网用户返回外网IP
- 插件参数可通过 Corefile 灵活配置

## 工作原理

### 1. 捕获下游插件结果
- splitnet 插件位于插件链中，会捕获下游插件（如 hosts、file 等）的解析结果
- 分析返回的 A/AAAA 记录，判断每个 IP 属于内网还是外网

### 2. 根据客户端IP过滤结果
- 获取客户端 IP，判断其是否属于内网
- 内网客户端：只返回内网 IP 的解析结果
- 外网客户端：只返回外网 IP 的解析结果
- 如果没有匹配的结果，返回全部解析结果

### 3. Trie（基数树）高效网段查找
- 使用 [cidranger](https://github.com/yl2chen/cidranger) 实现网段的 Trie 存储与查找，查找复杂度低，支持大规模网段。
- 每次热加载内网网段数据时自动重建 Trie 索引。

### 4. LRU 缓存热点 IP 查询
- 使用 [golang-lru](https://github.com/hashicorp/golang-lru) 实现最近最少使用缓存。
- IP->内外网归属缓存，热点 IP 查询可直接命中缓存，极大提升性能。
- 缓存容量可通过 `cache_size` 参数配置，默认 1024 条。
- 热加载内网网段数据时自动清空缓存，保证数据一致性。

### 5. 配置示例

```conf
splitnet {
    cidr_api http://localhost:8080/internal_cidr
    refresh_interval 60s
    cache_size 2048
}
```

### 6. 配置参数说明
- `cidr_api`：内网网段API地址
- `refresh_interval`：API刷新间隔，默认60s
- `cache_size`：LRU缓存最大条目数，默认1024

### 7. API 接口格式示例

```json
[
    {"cidr": "10.0.0.0/8", "desc": "内网A段"},
    {"cidr": "192.168.0.0/16", "desc": "内网C段"},
    {"cidr": "172.16.0.0/12", "desc": "内网B段"},
    {"cidr": "127.0.0.0/8", "desc": "本地回环"}
]
```

### 8. 内存占用估算
- 1000 条内网网段时，splitnet 插件总占用约 330KB
- 1万条内网网段时，约 2MB
- LRU缓存最大占用 = cache_size × 单条entry大小（可配置，默认1024条，最大8K条也仅约0.5MB）

### 9. 性能收益
- Trie结构查找大幅降低单次查找延迟
- LRU缓存极大提升热点IP查询性能，降低后端压力
- 支持大规模网段和高并发场景

## 使用场景
- 企业内网DNS解析，内网用户访问内网IP，外网用户访问公网IP
- 多地域部署，就近解析
- 内外网服务分离
- 与 hosts、file 等插件配合，实现智能路由

## 典型配置示例

```conf
.:53 {
    splitnet {
        cidr_api http://localhost:8080/internal_cidr
        refresh_interval 60s
        cache_size 2048
    }
    hosts ./hosts {
        fallthrough
    }
    forward . 8.8.8.8
    log
}
```

## 参考
- [cidranger](https://github.com/yl2chen/cidranger)
- [golang-lru](https://github.com/hashicorp/golang-lru) 