# SQLMap 自动化扫描平台

一个基于 Web 的 SQLMap 自动化扫描工具，支持批量提交扫描任务、实时查看结果。

## 功能特性

- 📤 **简单提交**: 直接粘贴 HTTP 请求包即可提交扫描
- 🔄 **自动解析**: 自动解析请求包中的目标、参数、Cookie 等
- 📊 **实时状态**: WebSocket 实时推送扫描进度和结果
- 💾 **任务管理**: SQLite 存储所有任务，支持查看历史
- 🚀 **并发扫描**: 支持多任务并发执行
- 🎨 **现代界面**: 美观的 Web 管理界面

## 快速开始

### 1. 安装依赖

确保已安装:
- Go 1.21+
- SQLMap (`apt install sqlmap` 或 `pip install sqlmap`)

### 2. 编译

```bash
cd sqlmap-web
go build -o sqlmap-web
```

### 3. 运行

```bash
./sqlmap-web
```

访问 http://localhost:8080

## 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-addr` | 监听地址 | `:8080` |
| `-sqlmap` | SQLMap 路径 | `sqlmap` |
| `-workers` | 最大同时执行数 | `2` |
| `-db` | 数据库路径 | `sqlmap-web.db` |
| `-workdir` | 工作目录 | `./output` |

### 示例

```bash
# 监听 80 端口，5 个并发
./sqlmap-web -addr :80 -workers 5

# 指定 sqlmap 路径
./sqlmap-web -sqlmap /usr/bin/sqlmap

# 指定数据库文件
./sqlmap-web -db /data/sqlmap.db
```

## 使用方法

### 1. 提交扫描任务

在 Web 界面粘贴完整的 HTTP 请求包:

```http
GET /news.php?id=1 HTTP/1.1
Host: target.com
Cookie: session=abc123
User-Agent: Mozilla/5.0
```

或者 POST 请求:

```http
POST /login.php HTTP/1.1
Host: target.com
Content-Type: application/x-www-form-urlencoded
Cookie: session=abc123

username=admin&password=test
```

### 2. 额外参数

可以添加 SQLMap 额外参数:

```
--level=5 --risk=3      # 更深入的测试
--dbs                   # 获取数据库列表
--tables -D dbname      # 获取表列表
--dump -T users         # 导出数据
--os-shell              # 获取 shell
```

### 3. 查看结果

- 绿色 = 发现漏洞
- 红色 = 未发现漏洞
- 橙色 = 扫描中
- 蓝色 = 等待中

## API 接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/tasks` | GET | 获取任务列表 |
| `/api/tasks` | POST | 创建新任务 |
| `/api/tasks/:id` | GET | 获取任务详情 |
| `/api/tasks/:id` | DELETE | 删除任务 |
| `/api/stats` | GET | 获取统计信息 |
| `/ws` | WebSocket | 实时状态推送 |

### 创建任务

```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "测试任务",
    "request": "GET /page.php?id=1 HTTP/1.1\nHost: example.com",
    "options": "--level=3"
  }'
```

## 架构

```
┌─────────────────────────────────────────────────────────┐
│                    Web 浏览器                            │
│                        │                                │
│            HTTP/WebSocket                               │
│                        ▼                                │
├─────────────────────────────────────────────────────────┤
│                    Go 服务器                             │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐            │
│  │ HTTP API │   │ WebSocket│   │ 任务调度  │            │
│  └──────────┘   └──────────┘   └────┬─────┘            │
│                                     │                   │
│                              ┌──────┴──────┐           │
│                              ▼             ▼           │
│                         ┌────────┐   ┌────────┐       │
│                         │Worker 1│   │Worker N│       │
│                         └───┬────┘   └───┬────┘       │
│                             │            │             │
├─────────────────────────────┼────────────┼─────────────┤
│                             ▼            ▼             │
│                    ┌─────────────────────────┐         │
│                    │        SQLMap           │         │
│                    └─────────────────────────┘         │
│                                                        │
│                    ┌─────────────────────────┐         │
│                    │   SQLite 数据库          │         │
│                    └─────────────────────────┘         │
└─────────────────────────────────────────────────────────┘
```

## Docker 部署

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o sqlmap-web

FROM python:3.11-alpine
RUN pip install sqlmap
WORKDIR /app
COPY --from=builder /app/sqlmap-web .
EXPOSE 8080
CMD ["./sqlmap-web"]
```

```bash
docker build -t sqlmap-web .
docker run -d -p 8080:8080 sqlmap-web
```

## 注意事项

⚠️ **安全警告**

- 仅用于授权的渗透测试
- 不要对未授权目标进行扫描
- 建议在隔离网络环境中使用
- 扫描结果可能包含敏感信息，注意保护

## 许可证

MIT License - 仅用于合法的安全测试
