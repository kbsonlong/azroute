#!/bin/bash

# 插件代码语法测试脚本
set -e

echo "开始插件代码语法测试..."

# 检查Go是否安装
if ! command -v go &> /dev/null; then
    echo "错误: Go未安装，请先安装Go"
    exit 1
fi

echo "Go版本: $(go version)"

# 创建临时模块
TEMP_DIR=$(mktemp -d)
echo "使用临时目录: $TEMP_DIR"

cd "$TEMP_DIR"

# 初始化临时模块
go mod init test-plugins

# 添加必要的依赖
go get github.com/coredns/coredns@v1.11.3
go get github.com/miekg/dns@latest
go get github.com/hashicorp/golang-lru@v1.0.2
go get github.com/yl2chen/cidranger@v1.0.2
go get github.com/oschwald/geoip2-golang@v1.9.0
go get github.com/oschwald/maxminddb-golang@v1.12.0

# 复制插件源码
echo "复制插件源码..."
mkdir -p azroute splitnet georoute
cp /Users/zengshenglong/Code/GoWorkSpace/coredns-plugins/plugins/azroute/*.go ./azroute/
cp /Users/zengshenglong/Code/GoWorkSpace/coredns-plugins/plugins/splitnet/*.go ./splitnet/
cp /Users/zengshenglong/Code/GoWorkSpace/coredns-plugins/plugins/georoute/*.go ./georoute/

# 测试azroute插件
echo "测试azroute插件..."
cd azroute
if go build -o /dev/null .; then
    echo "✅ azroute插件语法正确"
else
    echo "❌ azroute插件语法错误"
    exit 1
fi
cd ..

# 测试splitnet插件
echo "测试splitnet插件..."
cd splitnet
if go build -o /dev/null .; then
    echo "✅ splitnet插件语法正确"
else
    echo "❌ splitnet插件语法错误"
    exit 1
fi
cd ..

# 测试georoute插件
echo "测试georoute插件..."
cd georoute
if go build -o /dev/null .; then
    echo "✅ georoute插件语法正确"
else
    echo "❌ georoute插件语法错误"
    exit 1
fi
cd ..

# 清理
echo "清理临时文件..."
rm -rf "$TEMP_DIR"

echo "🎉 所有插件语法测试通过！"
echo ""
echo "插件重命名总结："
echo "- geoip → georoute (地理路由)"
echo "- 避免了与CoreDNS内置geoip插件的冲突"
echo "- 名称更有诗意和意境"
echo ""
echo "下一步可以："
echo "1. 使用 ./test-docker-build.sh 进行Docker编译测试"
echo "2. 使用 ./build-test.sh ~/coredns-src 进行本地编译测试"
echo "3. 查看 docs/静态编译指南.md 了解详细使用方法" 