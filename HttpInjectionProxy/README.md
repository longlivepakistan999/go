# HTTP HTML 注入代理

在 HTTP 响应中自动注入自定义 HTML 内容。提供多种实现方式。

## 为什么不用 eBPF？

| 问题 | 说明 |
|------|------|
| HTTPS | 内核层无法解密 HTTPS 流量 |
| 压缩 | gzip/brotli 内容需要先解压 |
| TCP 分片 | HTTP 响应可能跨多个包 |
| 包大小 | 修改内容需要重新计算校验和 |

**结论**：使用反向代理是更实际的方案。

## 方案选择

### 方案 1: Nginx（推荐）

最成熟稳定的方案。

```bash
# 安装 nginx
apt install nginx

# 复制配置
cp nginx-injection.conf /etc/nginx/sites-available/injection
ln -s /etc/nginx/sites-available/injection /etc/nginx/sites-enabled/

# 测试并重载
nginx -t && nginx -s reload
```

### 方案 2: Caddy

自动 HTTPS，配置简单。

```bash
# 安装 caddy（需要 replace 插件）
xcaddy build --with github.com/caddyserver/replace-response

# 运行
caddy run --config caddy-injection.Caddyfile
```

### 方案 3: Go 代理程序

独立程序，无需 Web 服务器。

```bash
cd go-proxy

# 编译
go build -o injection-proxy

# 运行
./injection-proxy -listen :80 -backend http://127.0.0.1:8080 -owner "我的公司"
```

参数说明：
- `-listen`: 监听地址，默认 `:80`
- `-backend`: 后端服务器地址
- `-owner`: 显示的所有者名称

## 架构图

```
用户请求
    │
    ▼
┌─────────────────┐
│   代理服务器     │  ◄── Nginx / Caddy / Go 代理
│   (端口 80/443) │
└────────┬────────┘
         │ 转发请求
         ▼
┌─────────────────┐
│   后端服务器     │  ◄── 你的实际 Web 服务
│   (端口 8080)   │
└────────┬────────┘
         │ 返回响应
         ▼
┌─────────────────┐
│   代理服务器     │  ◄── 注入 HTML 内容
└────────┬────────┘
         │
         ▼
    返回给用户
    (包含注入内容)
```

## 效果

每个 HTML 页面顶部会显示：

```
┌────────────────────────────────────────────┐
│        此网址属于 XXX 拥有                   │
└────────────────────────────────────────────┘
```

## 自定义样式

修改注入的 HTML/CSS：

**Nginx**: 编辑 `sub_filter` 指令中的内容

**Caddy**: 编辑 `replace` 块中的内容

**Go 代理**: 修改 `getInjectedHTML()` 函数

## 处理 HTTPS

- **Nginx**: 配置 SSL 证书，见配置文件中的 HTTPS 部分
- **Caddy**: 自动获取和续期 Let's Encrypt 证书
- **Go 代理**: 需要额外添加 TLS 支持

## 注意事项

⚠️ 此工具仅应用于您拥有和控制的服务器和网站。
