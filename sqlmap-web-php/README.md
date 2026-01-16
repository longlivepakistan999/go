# SQLMap 自动化扫描平台 (PHP 版本)

基于 PHP 的 SQLMap 自动化扫描 Web 平台。

## 功能特性

- 📤 提交 HTTP 请求包自动扫描
- 🔄 后台 Worker 自动执行任务
- 📊 实时状态更新
- 🔍 支持按状态筛选任务
- 💾 SQLite 数据库存储
- 🎨 美观的 Web 界面

## 快速开始

### 方法 1: 一键启动

```bash
chmod +x start.sh
./start.sh

# 或指定端口
./start.sh 80
```

### 方法 2: 手动启动

```bash
# 1. 启动 Worker (后台处理任务)
php worker.php &

# 2. 启动 Web 服务器
php -S 0.0.0.0:8080

# 访问 http://localhost:8080
```

## 文件结构

```
sqlmap-web-php/
├── index.php           # Web 界面 + API
├── worker.php          # 后台任务处理
├── config.php          # 配置文件
├── start.sh            # 一键启动脚本
├── includes/
│   ├── Database.php    # 数据库类
│   └── Task.php        # 任务管理类
├── data/               # 数据目录
│   ├── sqlmap.db       # SQLite 数据库
│   └── worker.log      # Worker 日志
└── output/             # SQLMap 输出目录
```

## 配置

编辑 `config.php`:

```php
return [
    'db_path' => __DIR__ . '/data/sqlmap.db',
    'sqlmap_path' => 'sqlmap',          // SQLMap 路径
    'work_dir' => __DIR__ . '/output',
    'max_workers' => 2,                  // 最大并发数
    'default_args' => [
        '--batch',
        '--flush-session',
        '--is-dba',
    ],
];
```

## Worker 管理

```bash
# 前台运行
php worker.php

# 后台运行 (需要 pcntl 扩展)
php worker.php daemon

# 停止后台进程
php worker.php stop

# 查看状态
php worker.php status
```

## API 接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/tasks` | GET | 获取任务列表 |
| `/api/tasks` | POST | 创建任务 |
| `/api/tasks/{id}` | GET | 获取任务详情 |
| `/api/tasks/{id}` | DELETE | 删除任务 |
| `/api/stats` | GET | 获取统计信息 |

### 创建任务示例

```bash
curl -X POST http://localhost:8080/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "测试任务",
    "request": "GET /page.php?id=1 HTTP/1.1\nHost: example.com",
    "options": "--level=3"
  }'
```

## 系统要求

- PHP 7.4+
- SQLite3 扩展
- SQLMap (`pip install sqlmap`)
- pcntl 扩展 (可选，用于并发处理)

## 与 Go 版本对比

| 特性 | PHP 版本 | Go 版本 |
|------|----------|---------|
| 部署 | 简单 (只需 PHP) | 需要编译 |
| 实时更新 | 轮询 (3秒) | WebSocket |
| 并发 | 需要 pcntl | 原生支持 |
| 性能 | 良好 | 更好 |
| 适用场景 | 共享主机、快速部署 | 生产环境 |

## 注意事项

⚠️ **安全警告**

- 仅用于授权的渗透测试
- 不要对未授权目标进行扫描
- 建议在隔离网络环境中使用

## 许可证

MIT License - 仅用于合法的安全测试
