# CoreDNS azroute 插件

## 项目简介
azroute 是一个为 CoreDNS 设计的可用区（AZ）就近调度插件，结合 hosts 插件和 API 动态网段-AZ 映射，实现内部服务 DNS 解析的智能就近返回。

## 主要特性
- 支持通过 API 动态获取网段与可用区（AZ）映射
- 与 hosts 插件配合，自动优选同 AZ 的 IP 返回
- 支持 A/AAAA 记录，IPv4/IPv6
- API 热加载，异常自动容错
- 用户只需维护 hosts 文件，无需关心 AZ 信息

## 目录结构
```
.
├── azroute/         # 插件源码
├── az-mock-api/     # Gin API 示例服务
├── docs/            # 使用文档与设计文档
└── README.md
```

## 快速上手
1. 按照 [docs/usage.md](docs/usage.md) 配置 Corefile、hosts 和 API 服务
2. 集成插件到 CoreDNS 主项目并编译
3. 启动 CoreDNS 和 API 服务，体验就近调度

## 详细说明
- [使用文档](docs/usage.md)
- [设计文档](docs/design.md)