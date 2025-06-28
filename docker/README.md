# CoreDNS-Plugins 容器化压测方案

本文档提供了 CoreDNS-Plugins 项目的容器化压测方案，包括 Docker 环境搭建、测试脚本使用和结果分析。

## 📋 目录

- [环境准备](#环境准备)
- [快速开始](#快速开始)
- [测试脚本说明](#测试脚本说明)
- [监控和可视化](#监控和可视化)
- [结果分析](#结果分析)
- [故障排查](#故障排查)

## 🚀 环境准备

### 1. 系统要求

- Docker 20.10+
- Docker Compose 2.0+
- 至少 4GB 可用内存
- 至少 10GB 可用磁盘空间

### 2. 下载 GeoIP2 数据库

```bash
# 创建配置目录
mkdir -p docker/config

# 下载 GeoIP2 City 数据库（需要 MaxMind 账号）
# 访问 https://dev.maxmind.com/geoip/geoip2/geolite2/ 下载
# 将下载的文件重命名为 GeoLite2-City.mmdb 并放到 docker/config/ 目录
```

### 3. 准备测试数据

```bash
# 创建测试数据目录
mkdir -p docker/tests docker/results

# 生成测试域名列表
cat > docker/tests/queries.txt << EOF
www.example.com A
api.example.com A
cdn.example.com A
mail.example.com A
blog.example.com A
shop.example.com A
support.example.com A
docs.example.com A
EOF

# 生成内网查询列表
cat > docker/tests/internal_queries.txt << EOF
internal.example.com A
intranet.example.com A
dev.example.com A
test.example.com A
EOF

# 生成外网查询列表
cat > docker/tests/external_queries.txt << EOF
public.example.com A
www.example.com A
api.example.com A
EOF

# 生成混合查询列表
cat > docker/tests/mixed_queries.txt << EOF
www.example.com A
internal.example.com A
api.example.com A
intranet.example.com A
EOF
```

## 🏃‍♂️ 快速开始

### 1. 启动基础服务

```bash
# 进入 docker 目录
cd docker

# 启动 CoreDNS 和 Mock API 服务
docker-compose up -d coredns mock-api

# 检查服务状态
docker-compose ps
```

### 2. 运行基础性能测试

```bash
# 启动压测工具容器
docker-compose run --rm dnsperf

# 在容器内运行基础测试
./scripts/run-basic-test.sh coredns 53 60 100 1000
```

### 3. 运行完整测试套件

```bash
# 一键运行所有测试
docker-compose run --rm dnsperf ./scripts/run-all-tests.sh coredns 53 60
```

## 📊 测试脚本说明

### 1. 基础性能测试

```bash
# 使用方法
./scripts/run-basic-test.sh [DNS_SERVER] [DNS_PORT] [DURATION] [CONCURRENCY] [QPS]

# 示例
./scripts/run-basic-test.sh coredns 53 60 100 1000
```

**测试内容**:
- DNS 基础解析性能
- QPS 和延迟测试
- 错误率统计

### 2. 并发性能测试

```bash
# 使用方法
./scripts/run-concurrent-test.sh [DNS_SERVER] [DNS_PORT] [DURATION]

# 示例
./scripts/run-concurrent-test.sh coredns 53 30
```

**测试内容**:
- 不同并发数下的性能表现
- 并发数范围：50, 100, 200, 500, 1000, 2000
- 性能曲线分析

### 3. 插件性能测试

```bash
# 使用方法
./scripts/run-plugin-test.sh [DNS_SERVER] [DNS_PORT] [DURATION]

# 示例
./scripts/run-plugin-test.sh coredns 53 60
```

**测试内容**:
- geoip 插件：内网/外网/混合客户端测试
- splitnet 插件：内外网分流测试
- azroute 插件：可用区路由测试

### 4. 稳定性测试

```bash
# 使用方法
./scripts/run-stability-test.sh [DNS_SERVER] [DNS_PORT] [DURATION]

# 示例（1小时稳定性测试）
./scripts/run-stability-test.sh coredns 53 3600
```

**测试内容**:
- 长时间运行稳定性
- 系统资源监控
- 性能衰减分析

### 5. 一键完整测试

```bash
# 使用方法
./scripts/run-all-tests.sh [DNS_SERVER] [DNS_PORT] [DURATION]

# 示例
./scripts/run-all-tests.sh coredns 53 60
```

**测试内容**:
- 执行所有测试类型
- 生成综合报告
- 结果汇总分析

## 📈 监控和可视化

### 1. 启动监控服务

```bash
# 启动 Prometheus 和 Grafana
docker-compose --profile monitoring up -d prometheus grafana

# 访问地址
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/admin)
```

### 2. 配置 Grafana 数据源

1. 登录 Grafana (http://localhost:3000)
2. 用户名/密码：admin/admin
3. 添加 Prometheus 数据源：http://prometheus:9090

### 3. 导入 Dashboard

```bash
# 复制 Dashboard 配置
cp config/grafana/dashboards/coredns-dashboard.json config/grafana/dashboards/

# 在 Grafana 中导入 Dashboard
```

## 📊 结果分析

### 1. 测试结果目录结构

```
results/
├── all_tests_20231201_143022/
│   ├── basic_test/
│   │   ├── basic_test.log
│   │   └── metrics.json
│   ├── concurrent_test/
│   │   ├── concurrent_50.log
│   │   ├── concurrent_100.log
│   │   ├── ...
│   │   └── summary.csv
│   ├── plugin_test/
│   │   ├── geoip_internal.log
│   │   ├── geoip_external.log
│   │   ├── ...
│   │   └── plugin_summary.csv
│   ├── stability_test/
│   │   ├── stability_test.log
│   │   ├── system_monitor.log
│   │   └── stability_metrics.json
│   ├── comprehensive_report.json
│   └── test_summary.txt
```

### 2. 关键指标说明

| 指标 | 说明 | 目标值 |
|------|------|--------|
| QPS | 每秒查询数 | > 10,000 |
| 平均延迟 | 查询平均响应时间 | < 10ms |
| P95延迟 | 95%查询响应时间 | < 50ms |
| 错误率 | 查询失败率 | < 0.1% |
| CPU使用率 | 系统CPU占用 | < 80% |
| 内存使用率 | 系统内存占用 | < 80% |

### 3. 结果分析示例

```bash
# 查看基础测试结果
cat results/all_tests_*/basic_test/metrics.json | jq '.'

# 查看并发测试汇总
cat results/all_tests_*/concurrent_test/summary.csv

# 查看插件测试汇总
cat results/all_tests_*/plugin_test/plugin_summary.csv

# 查看综合报告
cat results/all_tests_*/comprehensive_report.json | jq '.'
```

## 🔧 故障排查

### 1. 常见问题

#### 服务启动失败
```bash
# 检查服务状态
docker-compose ps

# 查看服务日志
docker-compose logs coredns
docker-compose logs mock-api

# 检查端口占用
netstat -tuln | grep :53
```

#### 插件编译失败
```bash
# 重新构建镜像
docker-compose build --no-cache coredns

# 检查插件文件
docker exec coredns-plugins ls -la /plugins/
```

#### 测试连接失败
```bash
# 检查网络连通性
docker-compose exec dnsperf ping coredns

# 测试DNS解析
docker-compose exec dnsperf dig @coredns example.com

# 检查防火墙设置
sudo ufw status
```

### 2. 性能调优

#### 系统参数优化
```bash
# 增加文件描述符限制
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# 优化网络参数
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf
sysctl -p
```

#### Docker 资源限制
```yaml
# 在 docker-compose.yml 中添加资源限制
services:
  coredns:
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 4G
        reservations:
          cpus: '2.0'
          memory: 2G
```

### 3. 日志分析

```bash
# 查看 CoreDNS 日志
docker-compose logs -f coredns

# 查看 Mock API 日志
docker-compose logs -f mock-api

# 查看测试日志
tail -f results/*/basic_test.log
```

## 📝 使用示例

### 完整测试流程

```bash
# 1. 准备环境
cd docker
mkdir -p config tests results

# 2. 下载 GeoIP2 数据库到 config/ 目录

# 3. 生成测试数据
cat > tests/queries.txt << EOF
www.example.com A
api.example.com A
EOF

# 4. 启动服务
docker-compose up -d coredns mock-api

# 5. 等待服务就绪
sleep 30

# 6. 运行完整测试
docker-compose run --rm dnsperf ./scripts/run-all-tests.sh coredns 53 60

# 7. 查看结果
ls -la results/
cat results/*/test_summary.txt
```

### 自定义测试

```bash
# 自定义并发测试
docker-compose run --rm dnsperf bash -c "
  dnsperf -s coredns -p 53 -d /tests/queries.txt -l 120 -c 500 -Q 2000
"

# 自定义插件测试
docker-compose run --rm dnsperf bash -c "
  dnsperf -s coredns -p 53 -d /tests/internal_queries.txt -l 60 -c 100 -Q 1000
"
```

## 🎯 总结

容器化压测方案提供了：

1. **环境隔离**: 使用 Docker 容器隔离测试环境
2. **自动化测试**: 提供完整的测试脚本套件
3. **结果分析**: 自动生成测试报告和指标汇总
4. **监控可视化**: 集成 Prometheus 和 Grafana
5. **易于扩展**: 支持自定义测试场景和参数

通过这套方案，可以快速、准确地评估 CoreDNS-Plugins 的性能表现，为生产环境部署提供数据支撑。 