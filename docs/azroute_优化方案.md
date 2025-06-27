# azroute 插件高性能网段查找与缓存优化方案

## 1. 背景

在大规模多可用区（AZ）环境下，DNS 查询需根据客户端 IP 快速判断其所属可用区，并返回最优的解析结果。原始实现每次都遍历所有网段，性能瓶颈明显。

## 2. 优化目标
- 提升 IP->AZ 查找性能，支持大规模网段数据。
- 支持高并发、热点 IP 查询场景。
- 降低内存占用，防止缓存无限增长。
- 支持灵活配置缓存容量。

## 3. 主要优化方案

### 3.1 基数树（Trie）高效网段查找
- 使用 [github.com/yl2chen/cidranger](https://github.com/yl2chen/cidranger) 实现网段的 Trie 存储与查找。
- 启动或热加载 AZ 数据时，将所有网段构建为 Trie 结构，查找复杂度大幅降低。
- 代码集成：
  - `AzRoute` 结构体新增 `Ranger cidranger.Ranger` 字段。
  - `fetchAzMap` 方法中构建和更新 Trie。
  - `findAZ` 方法用 Trie 查找 IP 所属 AZ。

### 3.2 LRU 缓存热点 IP 查询
- 使用 [github.com/hashicorp/golang-lru](https://github.com/hashicorp/golang-lru) 实现最近最少使用（LRU）缓存。
- 缓存 IP->AZ 映射，热点 IP 查询可直接命中缓存，极大提升性能。
- 缓存容量可配置，防止内存无限增长。
- 热加载 AZ 数据时自动清空缓存，保证数据一致性。
- 代码集成：
  - `AzRoute` 结构体新增 `AzCache *lru.Cache` 字段。
  - `findAZ` 查询时优先查缓存，未命中再查 Trie 并写入缓存。
  - `fetchAzMap` 热加载时清空缓存。

### 3.3 缓存容量可配置
- 支持在 Corefile/配置文件中通过 `lru_size` 参数灵活配置缓存最大条目数。
- 代码集成：
  - `AzRoute` 结构体新增 `LruSize int` 字段。
  - `setup.go` 支持 `lru_size` 参数解析。
  - `InitAndUpdateAzMap` 初始化缓存时使用该配置。

## 4. 配置示例

```conf
azroute {
    azmap_api http://localhost:8080/azmap
    lru_size 4096
}
```
- `lru_size` 表示缓存最大条目数（不是字节数）。

## 5. 性能收益
- Trie结构查找大幅降低单次查找延迟。
- LRU缓存极大提升热点IP查询性能，降低后端压力。
- 支持大规模网段和高并发场景。

## 6. 参考
- [cidranger](https://github.com/yl2chen/cidranger)
- [golang-lru](https://github.com/hashicorp/golang-lru) 