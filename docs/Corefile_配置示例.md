# CoreDNS 配置示例

本文档提供了结合 `azroute`、`splitnet` 和 `geoip` 插件的完整 CoreDNS 配置示例。

## 完整配置示例

```corefile
# Corefile - 结合 azroute、splitnet 和 geoip 插件的智能DNS配置
# 适用于企业内网DNS解析场景，支持地理位置就近解析

.:53 {
    # 日志记录
    log
    
    # 错误处理
    errors
    
    # 健康检查
    health :8081
    
    # 指标监控
    prometheus :9153
    
    # geoip插件 - 基于地理位置的就近解析
    geoip {
        geoip_db /path/to/GeoLite2-City.mmdb
        cache_size 2048
        distance_threshold 1000
    }
    
    # 可用区智能路由插件 - 根据客户端可用区优选IP
    azroute {
        api_url http://localhost:8080/azmap
        api_interval 30s
        cache_size 1024
    }
    
    # 内外网区分解析插件 - 根据客户端IP过滤解析结果
    splitnet {
        api_url http://localhost:8080/internal_cidr
        api_interval 30s
        cache_size 1024
    }
    
    # hosts 插件提供基础解析
    hosts ./hosts {
        fallthrough
    }
    
    # 转发到上游DNS
    forward . 8.8.8.8 8.8.4.4
    
    # 缓存
    cache
}

# 内网域名专用配置
internal. {
    log
    errors
    
    # 仅使用azroute和splitnet插件，不使用geoip
    azroute {
        api_url http://localhost:8080/azmap
        api_interval 30s
        cache_size 1024
    }
    
    splitnet {
        api_url http://localhost:8080/internal_cidr
        api_interval 30s
        cache_size 1024
    }
    
    hosts {
        192.168.1.10 internal.example.com
        10.0.0.10 internal.example.com
        fallthrough
    }
    
    forward . 8.8.8.8
    cache
}
```

## 插件配置详解

### 1. azroute 插件

可用区智能路由插件，根据客户端IP所属的可用区优选服务器IP。

```corefile
azroute {
    api_url http://localhost:8080/azmap      # 可用区映射API地址
    api_interval 30s                         # API刷新间隔
    cache_size 1024                          # LRU缓存大小
}
```

**参数说明：**
- `api_url`: 可用区映射API地址，返回IP网段与可用区的映射关系
- `api_interval`: API数据刷新间隔，支持热加载
- `cache_size`: LRU缓存大小，用于缓存IP归属查询结果

### 2. splitnet 插件

内外网区分解析插件，根据客户端IP是否为内网IP来过滤解析结果。

```corefile
splitnet {
    api_url http://localhost:8080/internal_cidr  # 内网网段API地址
    api_interval 30s                             # API刷新间隔
    cache_size 1024                              # LRU缓存大小
}
```

**参数说明：**
- `api_url`: 内网网段API地址，返回内网IP网段列表
- `api_interval`: API数据刷新间隔，支持热加载
- `cache_size`: LRU缓存大小，用于缓存IP归属查询结果

### 3. geoip 插件

基于地理位置的就近解析插件，根据客户端地理位置选择最近的服务器IP。

```corefile
geoip {
    geoip_db /path/to/GeoLite2-City.mmdb    # GeoIP2数据库文件路径
    cache_size 2048                          # 地理位置缓存大小
    distance_threshold 1000                  # 距离阈值（公里）
}
```

**参数说明：**
- `geoip_db`: GeoIP2数据库文件路径（如GeoLite2-City.mmdb）
- `cache_size`: 地理位置查询缓存大小
- `distance_threshold`: 距离阈值，超过此距离的服务器IP将被过滤

## 插件执行顺序

正确的插件执行顺序为：
```
客户端请求 → geoip → splitnet → azroute → hosts → forward → 返回结果
```

## 处理逻辑

1. **geoip 插件**: 识别客户端IP类型
   - 内网IP: 返回所有服务器IP
   - 外网IP: 根据地理位置计算距离，筛选最优服务器IP

2. **splitnet 插件**: 根据客户端IP类型过滤服务器IP
   - 内网客户端: 优先返回内网服务器IP，如果没有内网IP则返回所有服务器IP
   - 外网客户端: 优先返回外网服务器IP，如果没有外网IP则返回所有服务器IP

3. **azroute 插件**: 根据可用区进行智能路由
   - 从过滤后的IP列表中，选择与客户端同可用区的IP
   - 如果没有同可用区IP，则返回所有可用IP

## 工作流程

### 1. 请求处理流程
```
客户端请求 → geoip → splitnet → azroute → hosts → forward → 返回结果
```

### 2. 处理逻辑示例

**场景1：内网用户访问 www.example.com**
1. 客户端IP: 192.168.1.100
2. geoip: 识别为内网IP，返回所有服务器IP给splitnet处理
3. splitnet: 优先返回内网IP，如果没有内网IP则返回所有IP
4. azroute: 根据可用区筛选最优内网IP
5. hosts: 返回 [10.1.2.3, 1.2.3.4]
6. geoip: 返回所有IP（内网客户端）
7. splitnet: 返回内网IP [10.1.2.3]
8. azroute: 根据可用区筛选，假设返回 [10.1.2.3]

**场景2：外网用户访问 www.example.com**
1. 客户端IP: 203.0.113.1
2. geoip: 识别为外网IP，获取地理位置，过滤距离过远的服务器
3. splitnet: 优先返回外网IP，如果没有外网IP则返回所有IP
4. azroute: 根据可用区筛选最优外网IP
5. hosts: 返回 [10.1.2.3, 1.2.3.4]
6. geoip: 根据距离过滤，假设1.2.3.4距离更近
7. splitnet: 返回外网IP [1.2.3.4]
8. azroute: 根据可用区筛选，假设返回 [1.2.3.4]

## 配置验证

### 1. 语法验证
```bash
./coredns -conf Corefile -validate
```

### 2. 功能测试
```bash
# 测试内网解析
dig @127.0.0.1 www.example.com

# 测试外网解析
dig @127.0.0.1 api.example.com
```

### 3. 日志检查
```bash
# 查看插件日志
grep -E "\[geoip\]|\[azroute\]|\[splitnet\]" /var/log/coredns.log
```

## API 接口格式

### azroute API (`/azmap`)

```json
[
    {
        "sub": "127.0.0.0/24",
        "az": "az-01"
    },
    {
        "sub": "10.90.0.0/24",
        "az": "az-02"
    }
]
```

### splitnet API (`/internal_cidr`)

```json
[
    {
        "cidr": "10.0.0.0/8",
        "desc": "内网A段"
    },
    {
        "cidr": "192.168.0.0/16",
        "desc": "内网C段"
    }
]
```

## 性能优化建议

1. **缓存配置**: 根据实际负载调整各插件的缓存大小
2. **API间隔**: 根据数据更新频率调整API刷新间隔
3. **插件顺序**: 确保插件按正确顺序执行，避免重复计算
4. **监控指标**: 启用prometheus插件监控DNS查询性能
5. **距离阈值**: 根据业务需求调整geoip插件的距离阈值

## 故障排查

1. **检查API服务**: 确保所有API接口正常响应
2. **查看日志**: 通过log插件查看详细的插件执行日志
3. **验证配置**: 使用`coredns -conf Corefile -validate`验证配置
4. **测试解析**: 使用`dig`命令测试DNS解析结果
5. **地理位置**: 确保GeoIP2数据库文件和插件配置正确

## 注意事项

1. 需要下载GeoIP2数据库文件（如GeoLite2-City.mmdb）
2. 确保API服务提供准确的数据格式
3. 合理配置缓存大小，避免内存占用过高
4. 定期更新GeoIP2数据库以保持地理位置信息准确性
5. 内网IP检测基于预定义的网段范围，可根据需要调整 