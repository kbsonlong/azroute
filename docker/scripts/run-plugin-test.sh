#!/bin/bash

# 插件性能测试脚本
# 使用方法: ./run-plugin-test.sh [DNS_SERVER] [DURATION]

set -e

# 默认参数
DNS_SERVER=${1:-"coredns"}
DNS_PORT=${2:-"53"}
DURATION=${3:-"60"}

# 测试文件
INTERNAL_QUERIES="/tests/internal_queries.txt"
EXTERNAL_QUERIES="/tests/external_queries.txt"
MIXED_QUERIES="/tests/mixed_queries.txt"

# 结果目录
RESULT_DIR="/results/plugin_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "=== CoreDNS 插件性能测试 ==="
echo "DNS服务器: $DNS_SERVER:$DNS_PORT"
echo "持续时间: ${DURATION}秒"
echo "结果目录: $RESULT_DIR"
echo ""

# 检查服务是否就绪
echo "检查 CoreDNS 服务状态..."
until dig @$DNS_SERVER -p $DNS_PORT example.com > /dev/null 2>&1; do
    echo "等待 CoreDNS 服务启动..."
    sleep 5
done
echo "CoreDNS 服务已就绪"

# 测试参数
CONCURRENCY=50
QPS=500

# 1. geoip 插件测试
echo "=== 1. geoip 插件测试 ==="

# 内网客户端测试
echo "1.1 内网客户端测试..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $INTERNAL_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/geoip_internal.log" 2>&1

# 外网客户端测试
echo "1.2 外网客户端测试..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $EXTERNAL_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/geoip_external.log" 2>&1

# 混合客户端测试
echo "1.3 混合客户端测试..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $MIXED_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/geoip_mixed.log" 2>&1

# 2. splitnet 插件测试
echo "=== 2. splitnet 插件测试 ==="

# 内网客户端访问内网域名
echo "2.1 内网客户端访问内网域名..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $INTERNAL_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/splitnet_internal_internal.log" 2>&1

# 外网客户端访问外网域名
echo "2.2 外网客户端访问外网域名..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $EXTERNAL_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/splitnet_external_external.log" 2>&1

# 边界测试：内网客户端访问外网域名
echo "2.3 边界测试：内网客户端访问外网域名..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $EXTERNAL_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/splitnet_internal_external.log" 2>&1

# 3. azroute 插件测试
echo "=== 3. azroute 插件测试 ==="

# 同可用区测试
echo "3.1 同可用区测试..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $MIXED_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/azroute_same_az.log" 2>&1

# 跨可用区测试
echo "3.2 跨可用区测试..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $MIXED_QUERIES -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/azroute_cross_az.log" 2>&1

# 解析结果
echo "=== 解析测试结果 ==="

# 创建汇总文件
SUMMARY_FILE="$RESULT_DIR/plugin_summary.csv"
echo "插件,测试场景,QPS,平均延迟(ms),发送查询数,完成查询数,错误率(%)" > "$SUMMARY_FILE"

# 函数：解析单个测试结果
parse_test_result() {
    local test_file=$1
    local plugin=$2
    local scenario=$3
    
    if [ -f "$test_file" ]; then
        qps_result=$(grep "Queries per second" "$test_file" | awk '{print $4}' || echo "N/A")
        avg_latency=$(grep "Average response time" "$test_file" | awk '{print $4}' | sed 's/ms//' || echo "N/A")
        queries_sent=$(grep "Queries sent" "$test_file" | awk '{print $3}' || echo "N/A")
        queries_completed=$(grep "Queries completed" "$test_file" | awk '{print $3}' || echo "N/A")
        queries_lost=$(grep "Queries lost" "$test_file" | awk '{print $3}' || echo "0")
        
        # 计算错误率
        if [ "$queries_sent" != "N/A" ] && [ "$queries_sent" -gt 0 ]; then
            error_rate=$(echo "scale=2; $queries_lost * 100 / $queries_sent" | bc 2>/dev/null || echo "N/A")
        else
            error_rate="N/A"
        fi
        
        echo "$plugin,$scenario,$qps_result,$avg_latency,$queries_sent,$queries_completed,$error_rate" >> "$SUMMARY_FILE"
        
        echo "$plugin - $scenario: QPS=$qps_result, 延迟=${avg_latency}ms, 错误率=${error_rate}%"
    else
        echo "$plugin - $scenario: 测试文件不存在"
    fi
}

# 解析所有测试结果
parse_test_result "$RESULT_DIR/geoip_internal.log" "geoip" "内网客户端"
parse_test_result "$RESULT_DIR/geoip_external.log" "geoip" "外网客户端"
parse_test_result "$RESULT_DIR/geoip_mixed.log" "geoip" "混合客户端"

parse_test_result "$RESULT_DIR/splitnet_internal_internal.log" "splitnet" "内网访问内网"
parse_test_result "$RESULT_DIR/splitnet_external_external.log" "splitnet" "外网访问外网"
parse_test_result "$RESULT_DIR/splitnet_internal_external.log" "splitnet" "内网访问外网"

parse_test_result "$RESULT_DIR/azroute_same_az.log" "azroute" "同可用区"
parse_test_result "$RESULT_DIR/azroute_cross_az.log" "azroute" "跨可用区"

echo ""
echo "=== 插件测试汇总 ==="
echo "插件,测试场景,QPS,平均延迟(ms),发送查询数,完成查询数,错误率(%)"
tail -n +2 "$SUMMARY_FILE"

# 生成详细报告
cat > "$RESULT_DIR/plugin_report.json" << EOF
{
    "test_type": "plugin_performance",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "parameters": {
        "dns_server": "$DNS_SERVER:$DNS_PORT",
        "duration": $DURATION,
        "concurrency": $CONCURRENCY,
        "qps": $QPS
    },
    "plugins_tested": ["geoip", "splitnet", "azroute"],
    "summary_file": "$SUMMARY_FILE"
}
EOF

echo ""
echo "测试完成，结果保存在: $RESULT_DIR"
echo "汇总文件: $SUMMARY_FILE"
echo "详细报告: $RESULT_DIR/plugin_report.json" 