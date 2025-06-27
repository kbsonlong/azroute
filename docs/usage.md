# azroute 插件使用文档

## 1. 插件简介
azroute 是一个 CoreDNS 插件，支持基于可用区（AZ）就近调度 DNS 解析。它通过 API 动态获取网段与可用区的映射，结合 hosts 插件返回的 IP，实现同可用区优先返回。

## 2. 依赖环境
- CoreDNS 1.11.x 及以上
- Go 1.20 及以上
- hosts 插件（CoreDNS 默认自带）
- API 服务，返回网段与 AZ 的映射关系

## 3. 关键点（务必注意！）

> **插件顺序极其重要！**
>
> - `plugin.cfg` 中 azroute 必须在 hosts 之前：
>   ```
>   azroute:azroute
>   hosts:hosts
>   forward:forward
>   log:log
>   ...
>   ```
> - Corefile 中顺序也要保持一致：
>   ```
>   azroute {
>       azmap_api http://localhost:8080/azmap
>   }
>   hosts ./hosts {
>       fallthrough
>   }
>   forward . 8.8.8.8
>   log
>   ```
> - **否则 azroute ServeDNS 不会被调用，调度逻辑无效！**

## 4. API 服务格式
API 返回 JSON 数组，每项格式如下：
```json
[
  {"sub": "127.0.0.0/24", "az": "az-01"},
  {"sub": "10.90.0.0/24", "az": "az-02"}
]
```

## 5. demo plugin.cfg 配置

```txt
azroute:azroute
hosts:hosts
forward:forward
log:log
```

## 6. demo Corefile 配置

```txt
. {
    azroute {
        azmap_api http://localhost:8080/azmap
    }
    hosts ./hosts {
        fallthrough
    }
    forward . 8.8.8.8
    log
}
```

## 7. hosts 文件配置示例
```txt
1.1.1.1   example.com
2.2.2.2   example.com
127.0.0.100   example.com
2001:db8::1 example.com
4.4.4.4   test.com
5.5.5.5   test.com
```

## 8. 启动 API 服务（示例 Gin 代码）
见 az-mock-api/main.go 示例。

## 9. 编译与运行
1. 将 azroute 插件集成到 CoreDNS 主项目。
2. 按照 plugin.cfg 和 Corefile 配置启动 CoreDNS。
3. 启动 API 服务。

## 10. 测试
使用 dig 或 nslookup 测试：
```bash
dig @127.0.0.1 example.com
```
插件会优先返回与客户端同 AZ 的 IP，否则返回全部。

## 11. 常见问题
- API 服务不可用时，插件会打印日志，使用上一次缓存的数据。
- **azroute 必须在 hosts 之前，否则调度无效！**
- 支持 A/AAAA 记录，其他类型直接透传。 