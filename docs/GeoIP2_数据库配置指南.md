# GeoIP2 数据库配置指南

本文档提供 GeoIP2 数据库的下载、配置和使用指南，用于 geoip 插件的客户端地理位置识别功能。

## 概述

GeoIP2 是 MaxMind 公司提供的 IP 地理位置数据库，可以准确识别 IP 地址对应的国家、地区、城市等地理位置信息。geoip 插件使用 GeoIP2 数据库来实现基于地理位置的智能 DNS 解析。

## 数据库类型

### 1. GeoLite2 免费版
- **GeoLite2-City**: 城市级别的地理位置信息
- **GeoLite2-Country**: 国家级别的地理位置信息
- **GeoLite2-ASN**: 自治系统编号信息

### 2. GeoIP2 商业版
- **GeoIP2-City**: 更精确的城市级别信息
- **GeoIP2-Country**: 更精确的国家级别信息
- **GeoIP2-ISP**: ISP 信息
- **GeoIP2-Connection-Type**: 连接类型信息

## 获取数据库

### 1. 注册 MaxMind 账号

1. 访问 [MaxMind 官网](https://www.maxmind.com/)
2. 点击 "Sign Up" 注册免费账号
3. 验证邮箱地址
4. 登录账号

### 2. 获取 License Key

1. 登录 MaxMind 账号
2. 进入 "My License Key" 页面
3. 生成新的 License Key
4. 记录 License Key（用于下载数据库）

### 3. 下载数据库

#### 方法一：使用 wget 下载

```bash
# 下载 GeoLite2-City 数据库
wget "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_LICENSE_KEY&suffix=tar.gz" -O GeoLite2-City.tar.gz

# 下载 GeoLite2-Country 数据库
wget "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=YOUR_LICENSE_KEY&suffix=tar.gz" -O GeoLite2-Country.tar.gz
```

#### 方法二：使用 curl 下载

```bash
# 下载 GeoLite2-City 数据库
curl -L "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_LICENSE_KEY&suffix=tar.gz" -o GeoLite2-City.tar.gz

# 下载 GeoLite2-Country 数据库
curl -L "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=YOUR_LICENSE_KEY&suffix=tar.gz" -o GeoLite2-Country.tar.gz
```

#### 方法三：使用官方工具

```bash
# 安装 geoipupdate 工具
# Ubuntu/Debian
sudo apt-get install geoipupdate

# CentOS/RHEL
sudo yum install geoipupdate

# 配置 geoipupdate
sudo nano /etc/GeoIP.conf

# 添加以下配置
AccountID YOUR_ACCOUNT_ID
LicenseKey YOUR_LICENSE_KEY
EditionIDs GeoLite2-City GeoLite2-Country

# 下载数据库
sudo geoipupdate
```

## 数据库安装

### 1. 解压数据库文件

```bash
# 解压 GeoLite2-City 数据库
tar -xzf GeoLite2-City.tar.gz

# 解压 GeoLite2-Country 数据库
tar -xzf GeoLite2-Country.tar.gz

# 查看解压后的文件
ls -la GeoLite2-City_*/
ls -la GeoLite2-Country_*/
```

### 2. 复制数据库文件

```bash
# 创建数据库目录
sudo mkdir -p /usr/local/share/GeoIP

# 复制数据库文件
sudo cp GeoLite2-City_*/GeoLite2-City.mmdb /usr/local/share/GeoIP/
sudo cp GeoLite2-Country_*/GeoLite2-Country.mmdb /usr/local/share/GeoIP/

# 设置权限
sudo chmod 644 /usr/local/share/GeoIP/*.mmdb
sudo chown root:root /usr/local/share/GeoIP/*.mmdb
```

### 3. 验证数据库文件

```bash
# 检查文件类型
file /usr/local/share/GeoIP/GeoLite2-City.mmdb

# 检查文件大小（应该大于 10MB）
ls -lh /usr/local/share/GeoIP/GeoLite2-City.mmdb

# 使用 geoip2-golang 库测试数据库
cat > test_geoip.go << 'EOF'
package main

import (
    "fmt"
    "log"
    "net"

    "github.com/oschwald/geoip2-golang"
)

func main() {
    db, err := geoip2.Open("/usr/local/share/GeoIP/GeoLite2-City.mmdb")
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    ip := net.ParseIP("8.8.8.8")
    record, err := db.City(ip)
    if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("IP: %s\n", ip)
    fmt.Printf("Country: %s\n", record.Country.Names["en"])
    fmt.Printf("City: %s\n", record.City.Names["en"])
    fmt.Printf("Latitude: %f\n", record.Location.Latitude)
    fmt.Printf("Longitude: %f\n", record.Location.Longitude)
}
EOF

go run test_geoip.go
```

## CoreDNS 配置

### 1. 更新 Corefile

编辑 CoreDNS 配置文件，添加 geoip 插件配置：

```corefile
.:53 {
    # geoip插件 - 基于地理位置的就近解析
    geoip {
        geoip_db /usr/local/share/GeoIP/GeoLite2-City.mmdb
        api_url http://localhost:8080/api/servers
        api_interval 60s
        cache_size 2048
    }
    
    # 其他插件配置...
    hosts ./hosts {
        fallthrough
    }
    
    forward . 8.8.8.8
    cache
}
```

### 2. 验证配置

```bash
# 验证 Corefile 语法
./coredns -conf Corefile -validate

# 启动 CoreDNS
./coredns -conf Corefile
```

## 自动化更新

### 1. 创建更新脚本

```bash
cat > /usr/local/bin/update_geoip.sh << 'EOF'
#!/bin/bash

# GeoIP2 数据库自动更新脚本

LICENSE_KEY="YOUR_LICENSE_KEY"
DB_DIR="/usr/local/share/GeoIP"
TEMP_DIR="/tmp/geoip_update"

# 创建临时目录
mkdir -p $TEMP_DIR
cd $TEMP_DIR

# 下载最新数据库
echo "Downloading GeoLite2-City database..."
wget -q "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=$LICENSE_KEY&suffix=tar.gz" -O GeoLite2-City.tar.gz

if [ $? -eq 0 ]; then
    # 解压数据库
    tar -xzf GeoLite2-City.tar.gz
    
    # 备份旧数据库
    if [ -f "$DB_DIR/GeoLite2-City.mmdb" ]; then
        cp "$DB_DIR/GeoLite2-City.mmdb" "$DB_DIR/GeoLite2-City.mmdb.bak"
    fi
    
    # 复制新数据库
    cp GeoLite2-City_*/GeoLite2-City.mmdb "$DB_DIR/"
    
    # 设置权限
    chmod 644 "$DB_DIR/GeoLite2-City.mmdb"
    chown root:root "$DB_DIR/GeoLite2-City.mmdb"
    
    echo "GeoIP2 database updated successfully"
    
    # 重启 CoreDNS（如果使用 systemd）
    if systemctl is-active --quiet coredns; then
        systemctl reload coredns
        echo "CoreDNS reloaded"
    fi
else
    echo "Failed to download GeoIP2 database"
    exit 1
fi

# 清理临时文件
rm -rf $TEMP_DIR
EOF

chmod +x /usr/local/bin/update_geoip.sh
```

### 2. 设置定时任务

```bash
# 编辑 crontab
crontab -e

# 添加以下行（每周二凌晨 2 点更新）
0 2 * * 2 /usr/local/bin/update_geoip.sh >> /var/log/geoip_update.log 2>&1
```

### 3. 使用 geoipupdate 工具

```bash
# 安装 geoipupdate
sudo apt-get install geoipupdate

# 配置 geoipupdate
sudo tee /etc/GeoIP.conf > /dev/null << EOF
AccountID YOUR_ACCOUNT_ID
LicenseKey YOUR_LICENSE_KEY
EditionIDs GeoLite2-City GeoLite2-Country
EOF

# 设置定时任务
echo "0 2 * * 2 /usr/bin/geoipupdate && systemctl reload coredns" | sudo crontab -
```

## 性能优化

### 1. 数据库选择

- **GeoLite2-City**: 提供城市级别信息，适合大多数应用场景
- **GeoLite2-Country**: 仅提供国家级别信息，文件更小，查询更快
- **GeoIP2-City**: 商业版，提供更精确的信息

### 2. 缓存配置

```corefile
geoip {
    geoip_db /usr/local/share/GeoIP/GeoLite2-City.mmdb
    api_url http://localhost:8080/api/servers
    api_interval 60s
    cache_size 4096  # 增加缓存大小
}
```

### 3. 内存优化

```bash
# 监控内存使用
watch -n 1 'ps aux | grep coredns'

# 调整系统内存限制
echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
sysctl -p
```

## 故障排查

### 1. 数据库文件问题

```bash
# 检查数据库文件
file /usr/local/share/GeoIP/GeoLite2-City.mmdb

# 验证数据库完整性
go run test_geoip.go

# 检查文件权限
ls -la /usr/local/share/GeoIP/
```

### 2. 下载问题

```bash
# 检查网络连接
curl -I https://download.maxmind.com

# 验证 License Key
curl "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_LICENSE_KEY&suffix=tar.gz"

# 检查下载配额
# 免费版每天有下载次数限制
```

### 3. 插件问题

```bash
# 查看 CoreDNS 日志
journalctl -u coredns -f

# 检查插件配置
./coredns -conf Corefile -validate

# 测试地理位置查询
dig @127.0.0.1 example.com
```

## 安全考虑

### 1. 文件权限

```bash
# 设置正确的文件权限
sudo chmod 644 /usr/local/share/GeoIP/*.mmdb
sudo chown root:root /usr/local/share/GeoIP/*.mmdb
```

### 2. 网络安全

```bash
# 限制数据库文件访问
sudo chmod 600 /usr/local/share/GeoIP/*.mmdb

# 使用防火墙限制访问
sudo ufw allow from 127.0.0.1 to any port 53
```

### 3. 隐私保护

- GeoIP2 数据库不包含个人身份信息
- 仅提供地理位置信息
- 符合 GDPR 等隐私法规要求

## 总结

通过正确配置 GeoIP2 数据库，geoip 插件可以为用户提供基于地理位置的智能 DNS 解析服务。关键点：

1. **选择合适的数据库**: 根据需求选择 City 或 Country 级别
2. **定期更新**: 确保数据库信息是最新的
3. **性能优化**: 合理配置缓存和内存使用
4. **安全配置**: 保护数据库文件和网络访问
5. **监控告警**: 监控数据库更新和插件运行状态 