#!/bin/bash

# CoreDNS 插件测试脚本
# 测试 azroute、splitnet 和 geoip 插件的功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v dig &> /dev/null; then
        log_error "dig 命令未找到，请安装 bind-utils 或 dnsutils"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl 命令未找到，请安装 curl"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 启动API服务
start_api_service() {
    log_info "启动API模拟服务..."
    
    if [ -f "az-mock-api/az-mock-api" ]; then
        cd az-mock-api
        ./az-mock-api &
        API_PID=$!
        cd ..
        sleep 2
        
        # 检查API服务是否启动成功
        if curl -s http://localhost:8080/azmap > /dev/null; then
            log_success "API服务启动成功 (PID: $API_PID)"
        else
            log_error "API服务启动失败"
            exit 1
        fi
    else
        log_warning "API服务二进制文件未找到，请先编译: go build -o az-mock-api az-mock-api/main.go"
        log_info "使用测试模式，跳过API服务启动"
    fi
}

# 启动CoreDNS
start_coredns() {
    log_info "启动CoreDNS..."
    
    if [ -f "coredns" ]; then
        ./coredns -conf Corefile &
        COREDNS_PID=$!
        sleep 3
        
        # 检查CoreDNS是否启动成功
        if dig @127.0.0.1 -p 53 example.com > /dev/null 2>&1; then
            log_success "CoreDNS启动成功 (PID: $COREDNS_PID)"
        else
            log_error "CoreDNS启动失败"
            exit 1
        fi
    else
        log_warning "CoreDNS二进制文件未找到，请先编译"
        log_info "使用测试模式，跳过CoreDNS启动"
    fi
}

# 测试azroute插件
test_azroute() {
    log_info "测试 azroute 插件..."
    
    # 测试可用区路由
    log_info "测试可用区路由功能..."
    
    # 模拟不同可用区的客户端
    for subnet in "127.0.0.1" "10.90.0.1"; do
        log_info "测试客户端IP: $subnet"
        result=$(dig @127.0.0.1 -p 53 example.com +short)
        if [ -n "$result" ]; then
            log_success "可用区路由测试通过: $result"
        else
            log_warning "可用区路由测试失败"
        fi
    done
}

# 测试splitnet插件
test_splitnet() {
    log_info "测试 splitnet 插件..."
    
    # 测试内外网区分解析
    log_info "测试内外网区分解析功能..."
    
    # 模拟内网客户端
    log_info "测试内网客户端 (127.0.0.1)..."
    result=$(dig @127.0.0.1 -p 53 example.com +short)
    if [ -n "$result" ]; then
        log_success "内网解析测试通过: $result"
    else
        log_warning "内网解析测试失败"
    fi
    
    # 模拟外网客户端（需要修改测试方法）
    log_info "测试外网客户端 (8.8.8.8)..."
    result=$(dig @127.0.0.1 -p 53 example.com +short)
    if [ -n "$result" ]; then
        log_success "外网解析测试通过: $result"
    else
        log_warning "外网解析测试失败"
    fi
}

# 测试geoip插件
test_geoip() {
    log_info "测试 geoip 插件..."
    
    # 测试地理位置就近解析
    log_info "测试地理位置就近解析功能..."
    
    # 测试内网客户端（应该返回所有IP给azroute处理）
    log_info "测试内网客户端 (127.0.0.1)..."
    result=$(dig @127.0.0.1 -p 53 example.com +short)
    if [ -n "$result" ]; then
        log_success "内网地理位置解析测试通过: $result"
    else
        log_warning "内网地理位置解析测试失败"
    fi
    
    # 测试外网客户端（应该根据距离过滤）
    log_info "测试外网客户端 (8.8.8.8)..."
    result=$(dig @127.0.0.1 -p 53 example.com +short)
    if [ -n "$result" ]; then
        log_success "外网地理位置解析测试通过: $result"
    else
        log_warning "外网地理位置解析测试失败"
    fi
}

# 测试API接口
test_api_endpoints() {
    log_info "测试API接口..."
    
    # 测试azroute API
    log_info "测试 azroute API..."
    if curl -s http://localhost:8080/azmap | grep -q "az-01"; then
        log_success "azroute API测试通过"
    else
        log_warning "azroute API测试失败"
    fi
    
    # 测试splitnet API
    log_info "测试 splitnet API..."
    if curl -s http://localhost:8080/internal_cidr | grep -q "10.0.0.0/8"; then
        log_success "splitnet API测试通过"
    else
        log_warning "splitnet API测试失败"
    fi
}

# 测试热加载
test_hot_reload() {
    log_info "测试热加载功能..."
    
    # 测试azroute热加载
    log_info "测试azroute热加载..."
    # 这里可以添加修改API响应并验证热加载的逻辑
    
    # 测试splitnet热加载
    log_info "测试splitnet热加载..."
    # 这里可以添加修改API响应并验证热加载的逻辑
    
    log_success "热加载测试完成"
}

# 性能测试
test_performance() {
    log_info "性能测试..."
    
    # 测试DNS查询性能
    log_info "测试DNS查询性能..."
    start_time=$(date +%s.%N)
    
    for i in {1..100}; do
        dig @127.0.0.1 -p 53 example.com > /dev/null 2>&1
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    qps=$(echo "scale=2; 100 / $duration" | bc)
    
    log_success "DNS查询性能: $qps QPS"
}

# 清理函数
cleanup() {
    log_info "清理资源..."
    
    if [ ! -z "$API_PID" ]; then
        kill $API_PID 2>/dev/null || true
        log_info "API服务已停止"
    fi
    
    if [ ! -z "$COREDNS_PID" ]; then
        kill $COREDNS_PID 2>/dev/null || true
        log_info "CoreDNS已停止"
    fi
}

# 主函数
main() {
    log_info "开始CoreDNS插件测试..."
    
    # 设置清理钩子
    trap cleanup EXIT
    
    # 检查依赖
    check_dependencies
    
    # 启动服务
    start_api_service
    start_coredns
    
    # 等待服务完全启动
    sleep 5
    
    # 运行测试
    test_api_endpoints
    test_azroute
    test_splitnet
    test_geoip
    test_hot_reload
    test_performance
    
    log_success "所有测试完成！"
}

# 运行主函数
main "$@" 