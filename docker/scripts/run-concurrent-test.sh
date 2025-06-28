#!/bin/bash

# 并发性能测试脚本
# 使用方法: ./run-concurrent-test.sh [DNS_SERVER] [DURATION]

set -e

# 默认参数
DNS_SERVER=${1:-"coredns"}
DNS_PORT=${2:-"53"}
DURATION=${3:-"30"}

# 测试文件
QUERY_FILE="/tests/queries.txt"

# 并发数列表
CONCURRENCY_LIST=(50 100 200 500 1000 2000)

# 结果目录
RESULT_DIR="/results/concurrent_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "=== CoreDNS 并发性能测试 ==="
echo "DNS服务器: $DNS_SERVER:$DNS_PORT"
echo "测试文件: $QUERY_FILE"
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

# 创建结果汇总文件
SUMMARY_FILE="$RESULT_DIR/summary.csv"
echo "并发数,QPS,平均延迟(ms),发送查询数,完成查询数,错误率(%)" > "$SUMMARY_FILE"

# 执行并发测试
for concurrency in "${CONCURRENCY_LIST[@]}"; do
    echo "测试并发数: $concurrency"
    
    # 计算 QPS (并发数 * 2)
    qps=$((concurrency * 2))
    
    # 执行测试
    test_log="$RESULT_DIR/concurrent_${concurrency}.log"
    dnsperf -s $DNS_SERVER -p $DNS_PORT -d $QUERY_FILE -l $DURATION -c $concurrency -Q $qps > "$test_log" 2>&1
    
    # 提取关键指标
    qps_result=$(grep "Queries per second" "$test_log" | awk '{print $4}' || echo "N/A")
    avg_latency=$(grep "Average response time" "$test_log" | awk '{print $4}' | sed 's/ms//' || echo "N/A")
    queries_sent=$(grep "Queries sent" "$test_log" | awk '{print $3}' || echo "N/A")
    queries_completed=$(grep "Queries completed" "$test_log" | awk '{print $3}' || echo "N/A")
    queries_lost=$(grep "Queries lost" "$test_log" | awk '{print $3}' || echo "0")
    
    # 计算错误率
    if [ "$queries_sent" != "N/A" ] && [ "$queries_sent" -gt 0 ]; then
        error_rate=$(echo "scale=2; $queries_lost * 100 / $queries_sent" | bc 2>/dev/null || echo "N/A")
    else
        error_rate="N/A"
    fi
    
    echo "并发数: $concurrency, QPS: $qps_result, 平均延迟: $avg_latency ms, 错误率: $error_rate%"
    
    # 写入汇总文件
    echo "$concurrency,$qps_result,$avg_latency,$queries_sent,$queries_completed,$error_rate" >> "$SUMMARY_FILE"
    
    # 保存详细指标
    cat > "$RESULT_DIR/metrics_${concurrency}.json" << EOF
{
    "test_type": "concurrent_performance",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "parameters": {
        "dns_server": "$DNS_SERVER:$DNS_PORT",
        "duration": $DURATION,
        "concurrency": $concurrency,
        "qps": $qps
    },
    "results": {
        "qps": "$qps_result",
        "avg_latency": "$avg_latency",
        "queries_sent": "$queries_sent",
        "queries_completed": "$queries_completed",
        "queries_lost": "$queries_lost",
        "error_rate": "$error_rate"
    }
}
EOF
    
    # 等待一段时间再进行下一个测试
    sleep 10
done

echo ""
echo "=== 测试汇总 ==="
echo "并发数,QPS,平均延迟(ms),发送查询数,完成查询数,错误率(%)"
tail -n +2 "$SUMMARY_FILE"

echo ""
echo "测试完成，结果保存在: $RESULT_DIR"
echo "汇总文件: $SUMMARY_FILE" 