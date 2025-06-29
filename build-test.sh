#!/bin/bash

# 本地编译测试脚本 - 无交互自动化集成版本
set -e

echo "开始本地编译测试..."

# 检查是否提供了CoreDNS源码目录
COREDNS_SRC=${1:-""}
if [ -z "$COREDNS_SRC" ]; then
    echo "用法: $0 <coredns源码目录路径>"
    echo "示例: $0 /path/to/coredns"
    echo ""
    echo "如果没有CoreDNS源码，请先下载："
    echo "git clone https://github.com/coredns/coredns.git /path/to/coredns"
    exit 1
fi

# 检查CoreDNS源码目录是否存在
if [ ! -d "$COREDNS_SRC" ]; then
    echo "错误: CoreDNS源码目录不存在: $COREDNS_SRC"
    exit 1
fi

# 检查是否是有效的CoreDNS源码目录
if [ ! -f "$COREDNS_SRC/go.mod" ] || [ ! -f "$COREDNS_SRC/plugin.cfg" ]; then
    echo "错误: 指定的目录不是有效的CoreDNS源码目录: $COREDNS_SRC"
    exit 1
fi

echo "使用CoreDNS源码目录: $COREDNS_SRC"

# 创建临时工作目录
TEMP_DIR=$(mktemp -d)
echo "使用临时工作目录: $TEMP_DIR"

# 复制CoreDNS源码到临时目录
echo "复制CoreDNS源码..."
cp -r "$COREDNS_SRC" "$TEMP_DIR/coredns"

# 复制插件源码
echo "复制插件源码..."
cp -r plugins/azroute/ "$TEMP_DIR/coredns/plugin/"
cp -r plugins/splitnet/ "$TEMP_DIR/coredns/plugin/"
cp -r plugins/georoute/ "$TEMP_DIR/coredns/plugin/"

# 修改 plugin.cfg - 避免重复追加
echo "修改 plugin.cfg..."
PLUGIN_CFG="$TEMP_DIR/coredns/plugin.cfg"

# 检查并添加azroute插件
if ! grep -q "^azroute:" "$PLUGIN_CFG"; then
    sed -i '' '/^hosts:hosts/a\\
azroute:azroute\\
splitnet:splitnet\\
georoute:georoute
' "$PLUGIN_CFG"
    echo "✅ 已添加 azroute/splitnet/georoute 插件到 plugin.cfg"
else
    echo "⚠️  azroute 插件已存在于 plugin.cfg"
fi

# 检查并添加splitnet插件
if ! grep -q "^splitnet:" "$PLUGIN_CFG"; then
    echo "splitnet:splitnet" >> "$PLUGIN_CFG"
    echo "✅ 已添加 splitnet 插件到 plugin.cfg"
else
    echo "⚠️  splitnet 插件已存在于 plugin.cfg"
fi

# 检查并添加georoute插件
if ! grep -q "^georoute:" "$PLUGIN_CFG"; then
    echo "georoute:georoute" >> "$PLUGIN_CFG"
    echo "✅ 已添加 georoute 插件到 plugin.cfg"
else
    echo "⚠️  georoute 插件已存在于 plugin.cfg"
fi

# 进入 CoreDNS 目录
cd "$TEMP_DIR/coredns"

# 修改go.mod，将module路径改为本地路径，避免go proxy查找
echo "修改go.mod以使用本地源码..."
sed -i.bak 's|^module github.com/coredns/coredns|module coredns-local|' go.mod
echo "✅ 已将module路径修改为本地路径"

# 处理依赖
echo "处理依赖..."
go mod tidy
go generate

# 尝试编译
echo "开始编译..."
if go build -o coredns; then
    echo "✅ 编译成功！"
    echo "编译后的文件大小: $(ls -lh coredns)"
    echo "编译后的文件位置: $TEMP_DIR/coredns/coredns"
    
    # 询问是否复制编译结果到当前目录
    OUTPUT_DIR="./build-output"
    mkdir -p "$OUTPUT_DIR"
    cp coredns "$OUTPUT_DIR/coredns-with-plugins"
    echo "✅ 编译结果已复制到: $OUTPUT_DIR/coredns-with-plugins"
    
    # 显示编译信息
    echo ""
    echo "🎉 编译完成！"
    echo "=========================================="
    echo "编译信息:"
    echo "- 临时工作目录: $TEMP_DIR"
    echo "- 输出文件: $OUTPUT_DIR/coredns-with-plugins"
    echo "- 文件大小: $(ls -lh $OUTPUT_DIR/coredns-with-plugins | awk '{print $5}')"
    echo ""
    echo "集成的插件:"
    echo "- azroute: 可用区智能路由"
    echo "- splitnet: 内外网区分解析"
    echo "- georoute: 地理路由就近解析"
    echo ""
    echo "使用方法:"
    echo "./build-output/coredns-with-plugins -conf Corefile"
    echo ""
    echo "注意: 临时目录将在脚本结束后自动清理"
    
else
    echo "❌ 编译失败！"
    echo "尝试手动添加依赖..."
    
    # 如果编译失败，尝试手动添加依赖
    go get github.com/oschwald/geoip2-golang@v1.9.0
    go get github.com/oschwald/maxminddb-golang@v1.12.0
    go get github.com/hashicorp/golang-lru@v1.0.2
    go get github.com/yl2chen/cidranger@v1.0.2
    
    go mod tidy
    
    if go build -o coredns; then
        echo "✅ 编译成功！"
        echo "编译后的文件大小: $(ls -lh coredns)"
        echo "编译后的文件位置: $TEMP_DIR/coredns/coredns"
        
        # 复制编译结果
        OUTPUT_DIR="./build-output"
        mkdir -p "$OUTPUT_DIR"
        cp coredns "$OUTPUT_DIR/coredns-with-plugins"
        echo "✅ 编译结果已复制到: $OUTPUT_DIR/coredns-with-plugins"
        
    else
        echo "❌ 编译仍然失败！"
        echo "请检查错误信息并修复问题"
        echo "临时目录: $TEMP_DIR"
        exit 1
    fi
fi

# 清理临时文件
echo "清理临时文件..."
sleep 3600
rm -rf "$TEMP_DIR"

echo "✅ 测试完成！" 