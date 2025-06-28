# CoreDNS-Plugins - CoreDNS 智能路由插件集合

CoreDNS-Plugins 是一套基于 CoreDNS 的智能DNS解析插件集合，包含三个核心插件：

- **azroute**: 可用区智能路由插件
- **splitnet**: 内外网区分解析插件  
- **geoip**: 基于地理位置的就近解析插件

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

## 项目结构

```
coredns-plugins/
├── plugins/           # 插件源码
│   ├── azroute/      # 可用区智能路由插件
│   ├── splitnet/     # 内外网区分解析插件
│   ├── geoip/        # 地理位置就近解析插件
│   └── common/       # 公共函数包
├── az-mock-api/      # API模拟服务
├── examples/         # 配置示例和测试脚本
└── docs/            # 详细文档
```

## 快速开始

### 1. 编译插件

```bash
# 编译所有插件
cd plugins/azroute && go build -buildmode=plugin -o azroute.so
cd ../splitnet && go build -buildmode=plugin -o splitnet.so  
cd ../geoip && go build -buildmode=plugin -o geoip.so
```

### 2. 启动API服务

```bash
cd az-mock-api
go run main.go
```

### 3. 配置CoreDNS

参考 `examples/Corefile` 进行配置：

```corefile
.:53 {
    geoip {
        geoip_db /path/to/GeoLite2-City.mmdb
        cache_size 2048
        distance_threshold 1000
    }
    
    splitnet {
        api_url http://localhost:8080/internal_cidr
        api_interval 30s
        cache_size 1024
    }
    
    azroute {
        api_url http://localhost:8080/azmap
        api_interval 30s
        cache_size 1024
    }
    
    hosts ./hosts
    forward . 8.8.8.8
    cache
}
```

### 4. 测试

```bash
cd examples
./test.sh
```

## 插件详情

### azroute 插件

根据客户端可用区信息，从解析结果中优选同可用区的IP地址。

**特性**:
- 支持动态可用区映射配置
- LRU缓存提升性能
- 自动热加载配置更新

**配置参数**:
- `api_url`: 可用区映射API地址
- `api_interval`: API刷新间隔
- `cache_size`: 缓存大小

### splitnet 插件

根据客户端IP类型（内网/外网），过滤解析结果中的服务器IP。

**特性**:
- 动态获取内网CIDR配置
- 支持IPv4和IPv6
- 缓存机制减少API调用

**配置参数**:
- `api_url`: 内网CIDR获取API地址
- `api_interval`: API刷新间隔
- `cache_size`: 缓存大小

### geoip 插件

基于GeoIP2数据库，根据客户端地理位置进行就近解析。

**特性**:
- 支持GeoIP2 City数据库
- 内网IP自动识别
- 距离阈值过滤
- LRU缓存优化性能

**配置参数**:
- `geoip_db`: GeoIP2数据库文件路径
- `cache_size`: LRU缓存大小
- `distance_threshold`: 距离阈值（公里）

## 工作流程示例

### 内网客户端访问
1. 客户端IP: `192.168.1.100` (内网)
2. geoip插件: 识别为内网IP，返回所有服务器IP
3. splitnet插件: 优先返回内网服务器IP，如果没有内网IP则返回所有服务器IP
4. azroute插件: 根据可用区筛选最优内网IP
5. 返回结果

### 外网客户端访问
1. 客户端IP: `203.0.113.1` (外网)
2. geoip插件: 根据地理位置计算距离，筛选最优服务器IP
3. splitnet插件: 优先返回外网服务器IP，如果没有外网IP则返回所有服务器IP
4. azroute插件: 根据可用区筛选最优外网IP
5. 返回结果

## 文档

- [Corefile配置示例](docs/Corefile_配置示例.md)
- [GeoIP插件优化说明](docs/geoip_插件优化说明.md)
- [插件编译测试指南](docs/插件编译测试指南.md)
- [GeoIP2数据库配置指南](docs/GeoIP2_数据库配置指南.md)

## 许可证

MIT License