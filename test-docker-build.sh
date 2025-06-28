#!/bin/bash

# Docker编译测试脚本
set -e

echo "开始Docker编译测试..."

# 检查Docker是否运行
if ! docker info > /dev/null 2>&1; then
    echo "错误: Docker未运行，请启动Docker服务"
    exit 1
fi

# 构建镜像
echo "构建Docker镜像..."
if docker build -f docker/Dockerfile.coredns -t coredns-with-plugins-test .; then
    echo "✅ Docker构建成功！"
    
    # 测试运行容器
    echo "测试运行容器..."
    if docker run --rm --name coredns-test coredns-with-plugins-test -version; then
        echo "✅ 容器运行测试成功！"
        echo "CoreDNS版本信息已显示"
    else
        echo "❌ 容器运行测试失败！"
        exit 1
    fi
    
    # 清理测试镜像
    read -p "是否删除测试镜像？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker rmi coredns-with-plugins-test
        echo "测试镜像已删除"
    else
        echo "测试镜像保留: coredns-with-plugins-test"
    fi
else
    echo "❌ Docker构建失败！"
    exit 1
fi

echo "Docker测试完成！" 