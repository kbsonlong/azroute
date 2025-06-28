#!/bin/bash

# 一键运行所有性能测试脚本
# 使用方法: ./run-all-tests.sh [DNS_SERVER] [DURATION]

set -e

# 默认参数
DNS_SERVER=${1:-"coredns"}
DNS_PORT=${2:-"53"}
DURATION=${3:-"60"}

# 结果根目录
RESULT_ROOT="/results/all_tests_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_ROOT"

echo "=== CoreDNS 完整性能测试套件 ==="
echo "DNS服务器: $DNS_SERVER:$DNS_PORT"
echo "测试持续时间: ${DURATION}秒"
echo "结果根目录: $RESULT_ROOT"
echo ""

# 检查服务是否就绪
echo "检查 CoreDNS 服务状态..."
until dig @$DNS_SERVER -p $DNS_PORT example.com > /dev/null 2>&1; do
    echo "等待 CoreDNS 服务启动..."
    sleep 5
done
echo "CoreDNS 服务已就绪"
echo ""

# 1. 基础性能测试
echo "=== 1. 基础性能测试 ==="
BASIC_RESULT="$RESULT_ROOT/basic_test"
mkdir -p "$BASIC_RESULT"
cd "$BASIC_RESULT"
/scripts/run-basic-test.sh "$DNS_SERVER" "$DNS_PORT" "$DURATION" 100 1000
echo "基础性能测试完成"
echo ""

# 2. 并发性能测试
echo "=== 2. 并发性能测试 ==="
CONCURRENT_RESULT="$RESULT_ROOT/concurrent_test"
mkdir -p "$CONCURRENT_RESULT"
cd "$CONCURRENT_RESULT"
/scripts/run-concurrent-test.sh "$DNS_SERVER" "$DNS_PORT" "$DURATION"
echo "并发性能测试完成"
echo ""

# 3. 插件性能测试
echo "=== 3. 插件性能测试 ==="
PLUGIN_RESULT="$RESULT_ROOT/plugin_test"
mkdir -p "$PLUGIN_RESULT"
cd "$PLUGIN_RESULT"
/scripts/run-plugin-test.sh "$DNS_SERVER" "$DNS_PORT" "$DURATION"
echo "插件性能测试完成"
echo ""

# 4. 稳定性测试（短时间版本）
echo "=== 4. 稳定性测试（短时间版本）==="
STABILITY_RESULT="$RESULT_ROOT/stability_test"
mkdir -p "$STABILITY_RESULT"
cd "$STABILITY_RESULT"
# 使用较短的稳定性测试时间
STABILITY_DURATION=$((DURATION * 2))
/scripts/run-stability-test.sh "$DNS_SERVER" "$DNS_PORT" "$STABILITY_DURATION"
echo "稳定性测试完成"
echo ""

# 生成综合报告
echo "=== 生成综合报告 ==="
REPORT_FILE="$RESULT_ROOT/comprehensive_report.json"

# 收集所有测试结果
BASIC_METRICS=""
if [ -f "$BASIC_RESULT/metrics.json" ]; then
    BASIC_METRICS=$(cat "$BASIC_RESULT/metrics.json")
fi

CONCURRENT_SUMMARY=""
if [ -f "$CONCURRENT_RESULT/summary.csv" ]; then
    CONCURRENT_SUMMARY=$(cat "$CONCURRENT_RESULT/summary.csv")
fi

PLUGIN_SUMMARY=""
if [ -f "$PLUGIN_RESULT/plugin_summary.csv" ]; then
    PLUGIN_SUMMARY=$(cat "$PLUGIN_RESULT/plugin_summary.csv")
fi

STABILITY_METRICS=""
if [ -f "$STABILITY_RESULT/stability_metrics.json" ]; then
    STABILITY_METRICS=$(cat "$STABILITY_RESULT/stability_metrics.json")
fi

# 生成综合报告
cat > "$REPORT_FILE" << EOF
{
    "test_suite": "CoreDNS 完整性能测试套件",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "parameters": {
        "dns_server": "$DNS_SERVER:$DNS_PORT",
        "test_duration": $DURATION,
        "stability_duration": $STABILITY_DURATION
    },
    "test_results": {
        "basic_test": $BASIC_METRICS,
        "concurrent_test": {
            "summary": "$CONCURRENT_SUMMARY"
        },
        "plugin_test": {
            "summary": "$PLUGIN_SUMMARY"
        },
        "stability_test": $STABILITY_METRICS
    },
    "directories": {
        "basic_test": "$BASIC_RESULT",
        "concurrent_test": "$CONCURRENT_RESULT",
        "plugin_test": "$PLUGIN_RESULT",
        "stability_test": "$STABILITY_RESULT"
    }
}
EOF

# 生成测试摘要
SUMMARY_FILE="$RESULT_ROOT/test_summary.txt"
cat > "$SUMMARY_FILE" << EOF
CoreDNS 完整性能测试套件 - 测试摘要
=====================================

测试时间: $(date)
DNS服务器: $DNS_SERVER:$DNS_PORT
测试持续时间: ${DURATION}秒
稳定性测试时间: ${STABILITY_DURATION}秒

测试项目:
1. 基础性能测试 - $BASIC_RESULT
2. 并发性能测试 - $CONCURRENT_RESULT
3. 插件性能测试 - $PLUGIN_RESULT
4. 稳定性测试 - $STABILITY_RESULT

关键文件:
- 综合报告: $REPORT_FILE
- 测试摘要: $SUMMARY_FILE

测试完成时间: $(date)
EOF

echo "综合报告已生成: $REPORT_FILE"
echo "测试摘要已生成: $SUMMARY_FILE"
echo ""

# 显示测试摘要
echo "=== 测试摘要 ==="
cat "$SUMMARY_FILE"

echo ""
echo "=== 所有测试完成 ==="
echo "结果保存在: $RESULT_ROOT"
echo ""
echo "查看详细结果:"
echo "  - 基础性能测试: $BASIC_RESULT"
echo "  - 并发性能测试: $CONCURRENT_RESULT"
echo "  - 插件性能测试: $PLUGIN_RESULT"
echo "  - 稳定性测试: $STABILITY_RESULT"
echo "  - 综合报告: $REPORT_FILE" 