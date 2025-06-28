#!/bin/bash

# 稳定性测试脚本
# 使用方法: ./run-stability-test.sh [DNS_SERVER] [DURATION]

set -e

# 默认参数
DNS_SERVER=${1:-"coredns"}
DNS_PORT=${2:-"53"}
DURATION=${3:-"3600"}  # 默认1小时

# 测试文件
QUERY_FILE="/tests/queries.txt"

# 结果目录
RESULT_DIR="/results/stability_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "=== CoreDNS 稳定性测试 ==="
echo "DNS服务器: $DNS_SERVER:$DNS_PORT"
echo "测试文件: $QUERY_FILE"
echo "持续时间: ${DURATION}秒 ($(($DURATION/3600))小时)"
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
CONCURRENCY=100
QPS=1000

# 创建监控脚本
MONITOR_SCRIPT="$RESULT_DIR/monitor.sh"
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
# 系统资源监控脚本

INTERVAL=30
LOG_FILE="$1"

while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # CPU 使用率
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    
    # 内存使用率
    memory_info=$(free | grep Mem)
    memory_total=$(echo $memory_info | awk '{print $2}')
    memory_used=$(echo $memory_info | awk '{print $3}')
    memory_usage=$(echo "scale=2; $memory_used * 100 / $memory_total" | bc)
    
    # 网络连接数
    connection_count=$(netstat -an | grep ESTABLISHED | wc -l)
    
    # CoreDNS 进程信息
    if pgrep coredns > /dev/null; then
        coredns_pid=$(pgrep coredns)
        coredns_cpu=$(ps -p $coredns_pid -o %cpu= 2>/dev/null || echo "N/A")
        coredns_mem=$(ps -p $coredns_pid -o %mem= 2>/dev/null || echo "N/A")
    else
        coredns_cpu="N/A"
        coredns_mem="N/A"
    fi
    
    # 写入日志
    echo "$timestamp,CPU:${cpu_usage}%,MEM:${memory_usage}%,CONN:${connection_count},COREDNS_CPU:${coredns_cpu}%,COREDNS_MEM:${coredns_mem}%" >> "$LOG_FILE"
    
    sleep $INTERVAL
done
EOF

chmod +x "$MONITOR_SCRIPT"

# 启动监控
MONITOR_LOG="$RESULT_DIR/system_monitor.log"
echo "timestamp,cpu_usage,memory_usage,connection_count,coredns_cpu,coredns_mem" > "$MONITOR_LOG"
"$MONITOR_SCRIPT" "$MONITOR_LOG" &
MONITOR_PID=$!

# 启动稳定性测试
echo "开始稳定性测试..."
STABILITY_LOG="$RESULT_DIR/stability_test.log"
dnsperf -s $DNS_SERVER -p $DNS_PORT -d $QUERY_FILE -l $DURATION -c $CONCURRENCY -Q $QPS > "$STABILITY_LOG" 2>&1 &
DNSPERF_PID=$!

# 等待测试完成
echo "测试进行中，预计完成时间: $(date -d "+$DURATION seconds")"
wait $DNSPERF_PID

# 停止监控
kill $MONITOR_PID 2>/dev/null || true

# 解析结果
echo "解析测试结果..."
if [ -f "$STABILITY_LOG" ]; then
    echo "=== 稳定性测试结果 ==="
    grep "Queries per second" "$STABILITY_LOG" || echo "未找到 QPS 信息"
    grep "Average response time" "$STABILITY_LOG" || echo "未找到平均延迟信息"
    grep "Response time percentiles" "$STABILITY_LOG" || echo "未找到延迟分位数信息"
    grep "Queries sent" "$STABILITY_LOG" || echo "未找到查询数量信息"
    grep "Queries completed" "$STABILITY_LOG" || echo "未找到完成查询信息"
    grep "Queries lost" "$STABILITY_LOG" || echo "未找到丢失查询信息"
    
    # 提取关键指标
    qps_result=$(grep "Queries per second" "$STABILITY_LOG" | awk '{print $4}' || echo "N/A")
    avg_latency=$(grep "Average response time" "$STABILITY_LOG" | awk '{print $4}' || echo "N/A")
    queries_sent=$(grep "Queries sent" "$STABILITY_LOG" | awk '{print $3}' || echo "N/A")
    queries_completed=$(grep "Queries completed" "$STABILITY_LOG" | awk '{print $3}' || echo "N/A")
    queries_lost=$(grep "Queries lost" "$STABILITY_LOG" | awk '{print $3}' || echo "0")
    
    # 计算错误率
    if [ "$queries_sent" != "N/A" ] && [ "$queries_sent" -gt 0 ]; then
        error_rate=$(echo "scale=2; $queries_lost * 100 / $queries_sent" | bc 2>/dev/null || echo "N/A")
    else
        error_rate="N/A"
    fi
    
    echo ""
    echo "=== 关键指标 ==="
    echo "QPS: $qps_result"
    echo "平均延迟: $avg_latency"
    echo "发送查询数: $queries_sent"
    echo "完成查询数: $queries_completed"
    echo "错误率: $error_rate%"
    
    # 分析系统资源使用情况
    echo ""
    echo "=== 系统资源分析 ==="
    if [ -f "$MONITOR_LOG" ]; then
        # 计算平均 CPU 使用率
        avg_cpu=$(tail -n +2 "$MONITOR_LOG" | awk -F',' '{sum+=$2} END {print sum/NR}' 2>/dev/null || echo "N/A")
        # 计算平均内存使用率
        avg_mem=$(tail -n +2 "$MONITOR_LOG" | awk -F',' '{sum+=$3} END {print sum/NR}' 2>/dev/null || echo "N/A")
        # 计算最大连接数
        max_conn=$(tail -n +2 "$MONITOR_LOG" | awk -F',' '{if($4>max) max=$4} END {print max}' 2>/dev/null || echo "N/A")
        
        echo "平均CPU使用率: $avg_cpu%"
        echo "平均内存使用率: $avg_mem%"
        echo "最大连接数: $max_conn"
    fi
    
    # 保存详细指标
    cat > "$RESULT_DIR/stability_metrics.json" << EOF
{
    "test_type": "stability_test",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "parameters": {
        "dns_server": "$DNS_SERVER:$DNS_PORT",
        "duration": $DURATION,
        "concurrency": $CONCURRENCY,
        "qps": $QPS
    },
    "results": {
        "qps": "$qps_result",
        "avg_latency": "$avg_latency",
        "queries_sent": "$queries_sent",
        "queries_completed": "$queries_completed",
        "queries_lost": "$queries_lost",
        "error_rate": "$error_rate",
        "avg_cpu_usage": "$avg_cpu",
        "avg_memory_usage": "$avg_mem",
        "max_connections": "$max_conn"
    },
    "files": {
        "test_log": "$STABILITY_LOG",
        "monitor_log": "$MONITOR_LOG"
    }
}
EOF
    
    echo "详细指标已保存到: $RESULT_DIR/stability_metrics.json"
else
    echo "错误: 稳定性测试日志文件未生成"
    exit 1
fi

echo ""
echo "稳定性测试完成，结果保存在: $RESULT_DIR"
echo "测试日志: $STABILITY_LOG"
echo "监控日志: $MONITOR_LOG" 