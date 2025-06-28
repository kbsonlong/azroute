#!/bin/bash

# 下载CoreDNS源码脚本
set -e

# 默认下载目录
DEFAULT_DIR="$HOME/coredns-src"

# 检查是否提供了下载目录
DOWNLOAD_DIR=${1:-"$DEFAULT_DIR"}

echo "开始下载CoreDNS源码..."

# 检查目录是否已存在
if [ -d "$DOWNLOAD_DIR" ]; then
    echo "目录已存在: $DOWNLOAD_DIR"
    read -p "是否删除并重新下载？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "删除现有目录..."
        rm -rf "$DOWNLOAD_DIR"
    else
        echo "使用现有目录"
        echo "CoreDNS源码位置: $DOWNLOAD_DIR"
        exit 0
    fi
fi

# 创建目录
mkdir -p "$DOWNLOAD_DIR"

# 下载CoreDNS源码
echo "正在下载CoreDNS源码到: $DOWNLOAD_DIR"
git clone https://github.com/coredns/coredns.git "$DOWNLOAD_DIR"

# 检查下载是否成功
if [ -f "$DOWNLOAD_DIR/go.mod" ] && [ -f "$DOWNLOAD_DIR/plugin.cfg" ]; then
    echo "✅ CoreDNS源码下载成功！"
    echo "源码位置: $DOWNLOAD_DIR"
    echo ""
    echo "现在可以使用以下命令进行编译测试："
    echo "./build-test.sh $DOWNLOAD_DIR"
else
    echo "❌ CoreDNS源码下载失败！"
    exit 1
fi 