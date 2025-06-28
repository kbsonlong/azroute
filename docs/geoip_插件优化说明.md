# GeoIP 插件优化说明

## 优化背景

最初的 geoip 插件设计依赖外部 API 服务动态获取服务器位置信息，结合 GeoIP2 库查询客户端位置，计算距离筛选服务器IP。这种设计虽然功能完整，但增加了系统复杂性和依赖关系。

## 优化方案

### 简化设计

取消 geoip 插件对 API 的依赖，改为直接通过 GeoIP2 库查询服务器IP的地理位置信息：

1. **内网IP客户端**: 直接返回所有服务器IP，由 azroute 插件处理同可用区调度
2. **外网IP客户端**: 通过 GeoIP2 查询服务器IP位置，计算距离筛选最优服务器

### 工作流程

```
客户端请求 → geoip → splitnet → azroute → hosts → forward → 返回结果
```

**处理逻辑**:
1. **geoip 插件**: 识别客户端IP类型
   - 内网IP: 返回所有服务器IP
   - 外网IP: 根据地理位置计算距离，筛选最优服务器IP

2. **splitnet 插件**: 根据客户端IP类型过滤服务器IP
   - 内网客户端: 只返回内网服务器IP
   - 外网客户端: 只返回外网服务器IP

3. **azroute 插件**: 根据可用区进行智能路由
   - 从过滤后的IP列表中，选择与客户端同可用区的IP
   - 如果没有同可用区IP，则返回所有可用IP

## 配置参数

### 新增参数

- `distance_threshold`: 距离阈值（公里），超过此距离的服务器将被过滤
- `cache_size`: LRU缓存大小，提升地理位置查询性能

### 配置示例

```corefile
geoip {
    geoip_db /path/to/GeoLite2-City.mmdb
    cache_size 2048
    distance_threshold 1000
}
```

## 性能优化

### 1. LRU缓存

- 缓存客户端地理位置查询结果
- 缓存服务器IP地理位置信息
- 可配置缓存大小，平衡内存使用和性能

### 2. 内网IP检测

- 自动识别内网IP地址
- 内网客户端直接返回所有服务器IP
- 减少不必要的地理位置计算

### 3. 距离阈值过滤

- 可配置的距离阈值
- 过滤距离过远的服务器
- 提升解析精度和性能

## 使用场景

### 场景1: 内网客户端访问

1. 客户端IP: `192.168.1.100` (内网)
2. geoip插件: 识别为内网IP，返回所有服务器IP
3. splitnet插件: 过滤出内网服务器IP
4. azroute插件: 根据可用区筛选最优内网IP
5. 返回结果

### 场景2: 外网客户端访问

1. 客户端IP: `203.0.113.1` (外网)
2. geoip插件: 根据地理位置计算距离，筛选最优服务器IP
3. splitnet插件: 过滤出外网服务器IP
4. azroute插件: 根据可用区筛选最优外网IP
5. 返回结果

## 优势

1. **简化架构**: 移除API依赖，降低系统复杂度
2. **提升可靠性**: 减少外部依赖，提高系统稳定性
3. **性能优化**: LRU缓存和内网IP检测提升查询效率
4. **配置灵活**: 可配置的距离阈值和缓存大小
5. **维护简单**: 减少运维成本和故障点

## 注意事项

1. 确保GeoIP2数据库文件路径正确
2. 根据实际需求调整距离阈值
3. 合理配置缓存大小，避免内存占用过高
4. 定期更新GeoIP2数据库以保持准确性

## 技术实现

### 1. 内网IP检测
```go
// 预定义的内网IP范围
s.InternalRanges = []*net.IPNet{
    {IP: net.ParseIP("10.0.0.0"), Mask: net.CIDRMask(8, 32)},   // 10.0.0.0/8
    {IP: net.ParseIP("172.16.0.0"), Mask: net.CIDRMask(12, 32)}, // 172.16.0.0/12
    {IP: net.ParseIP("192.168.0.0"), Mask: net.CIDRMask(16, 32)}, // 192.168.0.0/16
    {IP: net.ParseIP("127.0.0.0"), Mask: net.CIDRMask(8, 32)},   // 127.0.0.0/8
}
```

### 2. 服务器地理位置查询
```go
// 直接使用GeoIP2数据库查询服务器IP地理位置
serverLocation := s.getServerLocation(serverIP)
if serverLocation != nil {
    distance := calculateDistance(
        clientLocation.Latitude, clientLocation.Longitude,
        serverLocation.Latitude, serverLocation.Longitude,
    )
    return distance <= s.DistanceThreshold
}
```

### 3. 距离计算优化
```go
// 使用Haversine公式计算地理距离
func calculateDistance(lat1, lon1, lat2, lon2 float64) float64 {
    const R = 6371 // 地球半径（公里）
    
    lat1Rad := lat1 * (math.Pi / 180)
    lon1Rad := lon1 * (math.Pi / 180)
    lat2Rad := lat2 * (math.Pi / 180)
    lon2Rad := lon2 * (math.Pi / 180)
    
    dlat := lat2Rad - lat1Rad
    dlon := lon2Rad - lon1Rad
    
    a := math.Sin(dlat/2)*math.Sin(dlat/2) + math.Cos(lat1Rad)*math.Cos(lat2Rad)*math.Sin(dlon/2)*math.Sin(dlon/2)
    c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
    
    return R * c
}
```

## 迁移指南

### 1. 配置更新
```bash
# 添加距离阈值配置
geoip {
    geoip_db /path/to/GeoLite2-City.mmdb
    cache_size 2048
    distance_threshold 1000  # 新增参数
}
```

### 2. 测试验证
```bash
# 测试内网客户端
dig @127.0.0.1 example.com

# 测试外网客户端
dig @203.0.113.1 example.com

# 查看日志验证处理逻辑
grep "\[geoip\]" /var/log/coredns.log
```

## 总结

通过这次优化，geoip插件变得更加简洁、高效和可靠。移除了API依赖，简化了配置，提升了性能，同时保持了核心的地理位置就近解析功能。内网IP的特殊处理逻辑更符合企业级使用场景，与azroute插件的配合更加紧密。 