# GeoIP 插件

基于 GeoIP2 IP 地址库的 CoreDNS 就近解析插件，可以根据客户端的地理位置信息，智能返回最近的服务器IP。当客户端是内网IP时，插件会将所有服务器IP返回给下游的azroute插件进行可用区调度。

## 功能特性

- **地理位置识别**: 使用 GeoIP2 数据库识别客户端和服务器地理位置
- **就近解析**: 根据客户端位置选择最近的服务器IP
- **内网检测**: 自动识别内网IP，交由azroute插件处理可用区调度
- **LRU缓存**: 内置地理位置查询缓存，提升性能
- **距离阈值**: 可配置的距离阈值，灵活控制就近范围

## 配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `geoip_db` | string | - | GeoIP2数据库文件路径 |
| `cache_size` | int | 1024 | 地理位置缓存大小 |
| `distance_threshold` | float | 1000 | 距离阈值（公里） |

## 配置示例

```corefile
. {
    geoip {
        geoip_db /path/to/GeoLite2-City.mmdb
        cache_size 2048
        distance_threshold 500
    }
    azroute {
        api_url http://localhost:8080/azmap
        api_interval 30s
        cache_size 1024
    }
    hosts {
        192.168.1.10 example.com
        10.0.0.10 example.com
        172.16.0.10 example.com
        8.8.8.8 example.com
        fallthrough
    }
    forward . 8.8.8.8 8.8.4.4
    cache
}
```

## 工作原理

### 1. 客户端IP检测
插件首先检测客户端IP是否为内网IP：
- **内网IP范围**: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8

### 2. 处理逻辑
- **内网客户端**: 直接返回所有服务器IP，由下游的azroute插件根据可用区进行调度
- **外网客户端**: 使用GeoIP2数据库获取客户端和服务器地理位置，计算距离，返回距离阈值内的服务器IP

### 3. 距离计算
插件使用Haversine公式计算客户端与服务器之间的地理距离：
- 距离 ≤ 阈值：返回该服务器IP
- 距离 > 阈值：过滤掉该服务器IP

## 插件执行顺序

建议的插件执行顺序：
```
客户端请求 → geoip → azroute → hosts → forward → 返回结果
```

### 执行流程示例

**场景1：内网用户访问 example.com**
1. 客户端IP: 192.168.1.100
2. geoip: 识别为内网IP，返回所有服务器IP
3. azroute: 根据可用区筛选最优IP
4. hosts: 返回 [192.168.1.10, 10.0.0.10, 172.16.0.10, 8.8.8.8]
5. azroute: 筛选同可用区IP（假设192.168.1.10）
6. 最终返回: 192.168.1.10

**场景2：外网用户访问 example.com**
1. 客户端IP: 203.0.113.1
2. geoip: 识别为外网IP，获取地理位置
3. geoip: 计算与各服务器的距离，过滤距离过远的服务器
4. azroute: 根据可用区进一步筛选
5. hosts: 返回符合条件的IP列表
6. 最终返回: 距离最近且同可用区的IP

## 性能优化

- **LRU缓存**: 地理位置查询结果缓存，避免重复查询
- **并发安全**: 使用读写锁保护共享数据
- **高效算法**: 使用Haversine公式进行精确距离计算
- **内存优化**: 合理的内存使用和垃圾回收

## 依赖

- `github.com/oschwald/geoip2-golang`: GeoIP2数据库查询
- `github.com/hashicorp/golang-lru`: LRU缓存实现

## 注意事项

1. 需要下载GeoIP2数据库文件（如GeoLite2-City.mmdb）
2. 插件会修改DNS响应，确保下游插件配置正确
3. 内网IP检测基于预定义的网段范围
4. 距离阈值可根据实际需求调整
5. 地理位置查询可能影响性能，建议合理设置缓存大小

## 故障排查

### 1. 数据库问题
```bash
# 检查数据库文件
file /path/to/GeoLite2-City.mmdb

# 验证数据库完整性
# 使用geoip2-golang库的测试程序验证
```

### 2. 配置问题
```bash
# 验证Corefile语法
./coredns -conf Corefile -validate

# 查看插件日志
grep "\[geoip\]" /var/log/coredns.log
```

### 3. 性能问题
```bash
# 监控内存使用
ps aux | grep coredns

# 调整缓存大小
# 修改Corefile中的cache_size参数
``` 