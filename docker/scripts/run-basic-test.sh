#!/bin/bash

# 基础性能测试脚本
# 使用方法: ./run-basic-test.sh [DNS_SERVER] [DURATION] [CONCURRENCY] [QPS]

set -e

# 默认参数
DNS_SERVER=${1:-"coredns"}
DNS_PORT=${2:-"53"}
DURATION=${3:-"60"}
CONCURRENCY=${4:-"100"}
QPS=${5:-"1000"}

# 测试文件
QUERY_FILE="/tests/queries.txt"

# 结果目录
RESULT_DIR="/results/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "=== CoreDNS 基础性能测试 ==="
echo "DNS服务器: $DNS_SERVER:$DNS_PORT"
echo "测试文件: $QUERY_FILE"
echo "持续时间: ${DURATION}秒"
echo "并发数: $CONCURRENCY"
echo "QPS: $QPS"
echo "结果目录: $RESULT_DIR"
echo ""

# 检查服务是否就绪
echo "检查 CoreDNS 服务状态..."
until dig @$DNS_SERVER -p $DNS_PORT example.com > /dev/null 2>&1; do
    echo "等待 CoreDNS 服务启动..."
    sleep 5
done
echo "CoreDNS 服务已就绪"

# 执行基础性能测试
echo "开始基础性能测试..."
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $QUERY_FILE -l $DURATION -c $CONCURRENCY -Q $QPS > "$RESULT_DIR/basic_test.log" 2>&1

# 解析结果
echo "解析测试结果..."
if [ -f "$RESULT_DIR/basic_test.log" ]; then
    echo "=== 测试结果 ==="
    grep "Queries per second" "$RESULT_DIR/basic_test.log" || echo "未找到 QPS 信息"
    grep "Average response time" "$RESULT_DIR/basic_test.log" || echo "未找到平均延迟信息"
    grep "Response time percentiles" "$RESULT_DIR/basic_test.log" || echo "未找到延迟分位数信息"
    grep "Queries sent" "$RESULT_DIR/basic_test.log" || echo "未找到查询数量信息"
    grep "Queries completed" "$RESULT_DIR/basic_test.log" || echo "未找到完成查询信息"
    grep "Queries lost" "$RESULT_DIR/basic_test.log" || echo "未找到丢失查询信息"
    
    # 提取关键指标
    QPS_RESULT=$(grep "Queries per second" "$RESULT_DIR/basic_test.log" | awk '{print $4}' || echo "N/A")
    AVG_LATENCY=$(grep "Average response time" "$RESULT_DIR/basic_test.log" | awk '{print $4}' || echo "N/A")
    QUERIES_SENT=$(grep "Queries sent" "$RESULT_DIR/basic_test.log" | awk '{print $3}' || echo "N/A")
    QUERIES_COMPLETED=$(grep "Queries completed" "$RESULT_DIR/basic_test.log" | awk '{print $3}' || echo "N/A")
    
    echo ""
    echo "=== 关键指标 ==="
    echo "QPS: $QPS_RESULT"
    echo "平均延迟: $AVG_LATENCY"
    echo "发送查询数: $QUERIES_SENT"
    echo "完成查询数: $QUERIES_COMPLETED"
    
    # 保存指标到文件
    cat > "$RESULT_DIR/metrics.json" << EOF
{
    "test_type": "basic_performance",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "parameters": {
        "dns_server": "$DNS_SERVER:$DNS_PORT",
        "duration": $DURATION,
        "concurrency": $CONCURRENCY,
        "qps": $QPS
    },
    "results": {
        "qps": "$QPS_RESULT",
        "avg_latency": "$AVG_LATENCY",
        "queries_sent": "$QUERIES_SENT",
        "queries_completed": "$QUERIES_COMPLETED"
    }
}
EOF
    
    echo "指标已保存到: $RESULT_DIR/metrics.json"
else
    echo "错误: 测试日志文件未生成"
    exit 1
fi

echo ""
echo "测试完成，结果保存在: $RESULT_DIR" 